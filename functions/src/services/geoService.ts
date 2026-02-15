/**
 * GEO SERVICE - Serviço de geolocalização para Cloud Functions
 *
 * Replica a lógica do GeoIndexService do Flutter para uso no backend.
 * Responsável por:
 * - Bounding box para queries otimizadas
 * - Cálculo de distância (Haversine)
 * - Busca de usuários em raio geográfico
 */

import * as admin from "firebase-admin";

const EARTH_RADIUS_KM = 6371.0;
const DEFAULT_RADIUS_KM = 30.0;

interface BoundingBox {
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
}

/** Coordenadas geográficas normalizadas (latitude/longitude). */
type UserCoordinates = {latitude: number; longitude: number};

/**
 * Converte um valor desconhecido para número finito (ou null).
 * @param {unknown} value - Valor de entrada
 * @return {number|null} Número finito ou null
 */
function asFiniteNumber(value: unknown): number | null {
  const num = typeof value === "number" ? value : null;
  return num != null && Number.isFinite(num) ? num : null;
}

/**
 * Extrai coordenadas do documento de usuário suportando schemas atual
 * e legado. Prioriza displayLatitude/displayLongitude (com offset de privacidade)
 * @param {FirebaseFirestore.DocumentData} data - Dados do documento
 * Users/{userId}
 * @return {UserCoordinates|null} Coordenadas ou null se ausentes
 */
function extractUserCoordinates(
  data: FirebaseFirestore.DocumentData
): UserCoordinates | null {
  // 🔒 SEGURANÇA: Prioriza displayLatitude/displayLongitude (com offset ~1-3km)
  const displayLat = asFiniteNumber(data.displayLatitude);
  const displayLng = asFiniteNumber(data.displayLongitude);
  if (displayLat != null && displayLng != null) {
    return {latitude: displayLat, longitude: displayLng};
  }

  // Fallback: latitude/longitude no top-level (dados legados)
  const topLat = asFiniteNumber(data.latitude);
  const topLng = asFiniteNumber(data.longitude);
  if (topLat != null && topLng != null) {
    return {latitude: topLat, longitude: topLng};
  }

  // Schema legado (lastLocation.{latitude,longitude})
  const legacyLat = asFiniteNumber(data.lastLocation?.latitude);
  const legacyLng = asFiniteNumber(data.lastLocation?.longitude);
  if (legacyLat != null && legacyLng != null) {
    return {latitude: legacyLat, longitude: legacyLng};
  }

  // Fallback: alguns documentos podem ter GeoPoint em `location`
  const geoPointLat = asFiniteNumber(data.location?.latitude);
  const geoPointLng = asFiniteNumber(data.location?.longitude);
  if (geoPointLat != null && geoPointLng != null) {
    return {latitude: geoPointLat, longitude: geoPointLng};
  }

  return null;
}

/**
 * Busca coordenadas reais de um usuário da subcoleção privada
 * @param {string} userId - ID do usuário
 * @return {Promise<UserCoordinates|null>} Coordenadas ou null
 */
async function getPrivateUserCoordinates(
  userId: string
): Promise<UserCoordinates | null> {
  const firestore = admin.firestore();

  // Tenta Users/{userId}/private/location primeiro (novo schema)
  const privateDoc = await firestore
    .collection("Users")
    .doc(userId)
    .collection("private")
    .doc("location")
    .get();

  if (privateDoc.exists) {
    const data = privateDoc.data();
    const lat = asFiniteNumber(data?.latitude);
    const lng = asFiniteNumber(data?.longitude);
    if (lat != null && lng != null) {
      return {latitude: lat, longitude: lng};
    }
  }

  // Fallback: ler do documento principal (dados legados)
  const userDoc = await firestore.collection("Users").doc(userId).get();
  if (userDoc.exists) {
    return extractUserCoordinates(userDoc.data() || {});
  }

  return null;
}

/**
 * Calcula bounding box para query inicial
 * @param {number} latitude - Latitude do centro
 * @param {number} longitude - Longitude do centro
 * @param {number} radiusKm - Raio em km
 * @return {BoundingBox} Limites do bounding box
 */
function calculateBoundingBox(
  latitude: number,
  longitude: number,
  radiusKm: number
): BoundingBox {
  const latDelta = radiusKm / 111.0; // ~111km por grau de latitude
  const lngDelta = radiusKm / (111.0 * Math.cos((latitude * Math.PI) / 180));

  return {
    minLat: latitude - latDelta,
    maxLat: latitude + latDelta,
    minLng: longitude - lngDelta,
    maxLng: longitude + lngDelta,
  };
}

/**
 * Calcula distância real usando fórmula de Haversine
 * @param {number} lat1 - Latitude do ponto 1
 * @param {number} lng1 - Longitude do ponto 1
 * @param {number} lat2 - Latitude do ponto 2
 * @param {number} lng2 - Longitude do ponto 2
 * @return {number} Distância em km
 */
function distanceKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_KM * c;
}

/**
 * Busca usuários dentro de um raio geográfico
 * @param {object} options - Opções de busca
 * @return {Promise<string[]>} Lista de IDs de usuários dentro do raio
 */
export async function findUsersInRadius(options: {
  latitude: number;
  longitude: number;
  radiusKm?: number;
  excludeUserIds?: string[];
  limit?: number;
}): Promise<string[]> {
  const {
    latitude,
    longitude,
    radiusKm = DEFAULT_RADIUS_KM,
    excludeUserIds = [],
    limit = 100,
  } = options;

  console.log("\n🌍 [GeoService] findUsersInRadius()");
  console.log(`   Centro: (${latitude}, ${longitude})`);
  console.log(`   Raio: ${radiusKm}km`);
  console.log(`   Excluir: ${excludeUserIds.length} IDs`);

  const excludeSet = new Set(excludeUserIds);
  const bounds = calculateBoundingBox(latitude, longitude, radiusKm);

  const firestore = admin.firestore();

  // 🔒 SEGURANÇA: Usa displayLatitude/displayLongitude (com offset ~1-3km)
  // ✅ Query única — legacy paths removidos (economia de 2 queries extras)
  const snapshot = await firestore
    .collection("Users")
    .where("displayLatitude", ">=", bounds.minLat)
    .where("displayLatitude", "<=", bounds.maxLat)
    .limit(limit)
    .get();

  console.log(
    `📍 [GeoService] ${snapshot.size} usuários no bounding box (displayLatitude)`
  );

  if (snapshot.empty) {
    console.log("⚠️ [GeoService] Nenhum usuário no bounding box");
    return [];
  }

  // Filtrar por distância real e longitude
  const usersInRadius: string[] = [];

  for (const doc of snapshot.docs) {
    // Excluir IDs especificados
    if (excludeSet.has(doc.id)) {
      continue;
    }

    const data = doc.data();
    const coords = extractUserCoordinates(data);
    if (coords == null) {
      continue;
    }

    const userLat = coords.latitude;
    const userLng = coords.longitude;

    // Filtrar longitude (bounding box só filtra latitude)
    if (userLng < bounds.minLng || userLng > bounds.maxLng) {
      continue;
    }

    // Calcular distância real
    const distance = distanceKm(latitude, longitude, userLat, userLng);

    if (distance <= radiusKm) {
      usersInRadius.push(doc.id);

      if (usersInRadius.length >= limit) {
        break;
      }
    }
  }

  console.log(`✅ [GeoService] ${usersInRadius.length} usuários no raio`);
  return usersInRadius;
}

/**
 * Raio máximo de busca para notificações (em km)
 * Usuários podem definir raios de 1 a 30km via advancedSettings.eventNotificationRadiusKm
 */
const MAX_EVENT_NOTIFICATION_RADIUS_KM = 30.0;

/**
 * Raio padrão de notificações se usuário não definiu
 */
const DEFAULT_EVENT_NOTIFICATION_RADIUS_KM = 30.0;

/**
 * Busca usuários que devem receber notificação de evento baseado no raio
 * personalizado de cada usuário (advancedSettings.eventNotificationRadiusKm)
 *
 * @param {object} options - Opções de busca
 * @return {Promise<string[]>} Lista de IDs de usuários elegíveis
 */
export async function findUsersForEventNotification(options: {
  eventLatitude: number;
  eventLongitude: number;
  excludeUserIds?: string[];
  limit?: number;
}): Promise<string[]> {
  const {
    eventLatitude,
    eventLongitude,
    excludeUserIds = [],
    limit = 100,
  } = options;

  console.log("\n🔔 [GeoService] findUsersForEventNotification()");
  console.log(`   Evento em: (${eventLatitude}, ${eventLongitude})`);
  console.log(`   Raio máximo de busca: ${MAX_EVENT_NOTIFICATION_RADIUS_KM}km`);

  const excludeSet = new Set(excludeUserIds);

  // Buscar todos usuários no raio máximo
  const bounds = calculateBoundingBox(
    eventLatitude,
    eventLongitude,
    MAX_EVENT_NOTIFICATION_RADIUS_KM
  );

  const firestore = admin.firestore();

  // ✅ Query única — legacy paths removidos (economia de 1 query extra)
  const snapshot = await firestore
    .collection("Users")
    .where("displayLatitude", ">=", bounds.minLat)
    .where("displayLatitude", "<=", bounds.maxLat)
    .limit(limit * 2) // Buscar mais para compensar filtros
    .get();

  console.log(`📍 [GeoService] ${snapshot.size} usuários no bounding box`);

  if (snapshot.empty) {
    return [];
  }

  // Filtrar por distância real E raio personalizado do usuário
  const eligibleUsers: string[] = [];

  for (const doc of snapshot.docs) {
    if (excludeSet.has(doc.id)) {
      continue;
    }

    const data = doc.data();
    const coords = extractUserCoordinates(data);
    if (coords == null) {
      continue;
    }

    // Filtrar longitude
    if (coords.longitude < bounds.minLng || coords.longitude > bounds.maxLng) {
      continue;
    }

    // Calcular distância do usuário até o evento
    const distance = distanceKm(
      eventLatitude,
      eventLongitude,
      coords.latitude,
      coords.longitude
    );

    // Obter raio personalizado do usuário
    const userRadius = (
      data.advancedSettings?.eventNotificationRadiusKm as number | undefined
    ) ?? DEFAULT_EVENT_NOTIFICATION_RADIUS_KM;

    // Usuário recebe notificação se evento está dentro do raio dele
    if (distance <= userRadius) {
      eligibleUsers.push(doc.id);

      if (eligibleUsers.length >= limit) {
        break;
      }
    }
  }

  console.log(
    `✅ [GeoService] ${eligibleUsers.length} usuários elegíveis ` +
    "(respeitando raio personalizado)"
  );
  return eligibleUsers;
}

/**
 * Busca participantes de um evento (status approved/autoApproved)
 * @param {string} eventId - ID do evento
 * @return {Promise<string[]>} Lista de IDs dos participantes
 */
export async function getEventParticipants(
  eventId: string
): Promise<string[]> {
  const snapshot = await admin
    .firestore()
    .collection("EventApplications")
    .where("eventId", "==", eventId)
    .where("status", "in", ["approved", "autoApproved"])
    .get();

  if (snapshot.empty) {
    return [];
  }

  return snapshot.docs.map((doc) => doc.data().userId as string);
}
/**
 * Busca a localização real de um usuário (da subcoleção privada)
 * Deve ser usado APENAS em Cloud Functions para cálculos de distância
 * @param {string} userId - ID do usuário
 * @return {Promise<{latitude: number, longitude: number}|null>} Coordenadas ou null
 */
export {getPrivateUserCoordinates};
