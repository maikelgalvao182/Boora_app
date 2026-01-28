import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Inicializa o admin SDK se ainda não foi inicializado
if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Calcula a distância em km entre dois pontos (Haversine formula).
 * @param {number} lat1 Latitude 1
 * @param {number} lon1 Longitude 1
 * @param {number} lat2 Latitude 2
 * @param {number} lon2 Longitude 2
 * @return {number} Distância
 */
function calculateDistance(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371; // Raio da Terra em km
  const toRad = (val: number) => (val * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Converte distância em KM para graus de Latitude.
 * @param {number} km Distancia em km
 * @return {number} Graus de latitude
 */
function kmToLatDeg(km: number): number {
  return km / 111;
}

/**
 * Converte distância em KM para graus de Longitude (dependente da latitude).
 * @param {number} km Distancia em km
 * @param {number} atLatDeg Latitude de referência
 * @return {number} Graus de longitude
 */
function kmToLngDeg(km: number, atLatDeg: number): number {
  const latRad = (atLatDeg * Math.PI) / 180;
  const kmPerDeg = 111 * Math.cos(latRad);
  // Proteção para latitudes extremas (polos)
  return kmPerDeg > 0.0001 ? (km / kmPerDeg) : 180;
}

/**
 * Quantiza um valor numérico em passos definidos.
 * @param {number} value Valor original
 * @param {number} stepDeg Passo
 * @return {number} Valor quantizado
 */
function quantize(value: number, stepDeg: number): number {
  return Number((Math.round(value / stepDeg) * stepDeg).toFixed(5));
}

/**
 * Cloud Function para buscar pessoas próximas com limite baseado em VIP.
 *
 * 🔒 SEGURANÇA SERVER-SIDE:
 * - Verifica status VIP no Firestore (fonte da verdade)
 * - Limita quantidade de resultados (Free: 17, VIP: ilimitado/capped)
 * - Ordenação garantida: vip_priority → overallRating → distância
 * - Firestore Rules bloqueiam acesso direto
 * - Validação de Bounding Box para evitar scraping agressivo
 *
 * Deploy: firebase deploy --only functions:getPeople
 */
export const getPeople = functions.https.onCall(async (data, context) => {
  // 1. Autenticação Obrigatória
  const userId = context.auth?.uid;
  if (!userId) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "O usuário precisa estar logado para buscar pessoas."
    );
  }

  // TODO: Habilitar App Check para prevenir abusos
  // if (context.app == undefined) {
  //   throw new functions.https.HttpsError(
  //     'failed-precondition',
  //     'A função deve ser chamada de um app verificado.'
  //   );
  // }

  try {
    // 2. Parâmetros recebidos do client
    const {
      boundingBox, // { minLat, maxLat, minLng, maxLng }
      filters,
      center, // { lat, lng } - Opcional (melhora precisão)
      radiusKm, // Opcional (KM). Filtra fora deste raio.
    } = data;

    if (!boundingBox) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "boundingBox é obrigatório"
      );
    }

    // 2.1 Validação de Segurança do Bounding Box (Anti-Scraping / Performance)
    // Limite arbitrário de delta (aprox 111km por grau). 0.6 graus ~ 66km.
    const MAX_DELTA_DEG = 0.6;
    const deltaLat = Math.abs(boundingBox.maxLat - boundingBox.minLat);
    const deltaLng = Math.abs(boundingBox.maxLng - boundingBox.minLng);

    if (deltaLat > MAX_DELTA_DEG || deltaLng > MAX_DELTA_DEG) {
      // Opcional: Logar tentativa de abuso
      console.warn(
        `[getPeople] BoundingBox muito grande solicitado por ${userId}. ` +
        `LatDelta: ${deltaLat}, LngDelta: ${deltaLng}`
      );
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Área de busca muito grande. Por favor, aproxime o zoom."
      );
    }

    // Centro da busca: Usa o enviado pelo client ou calcula do box
    // Validação robusta de center para evitar NaN/Infinite
    const isLatValid = typeof center?.latitude === "number" &&
      Number.isFinite(center.latitude);
    const centerLat = isLatValid ?
      center.latitude :
      (boundingBox.minLat + boundingBox.maxLat) / 2;

    const isLngValid = typeof center?.longitude === "number" &&
      Number.isFinite(center.longitude);
    const centerLng = isLngValid ?
      center.longitude :
      (boundingBox.minLng + boundingBox.maxLng) / 2;

    // 3. Verificar Status VIP (Fonte da Verdade: Firestore)
    const userDoc = await admin.firestore()
      .collection("Users")
      .doc(userId)
      .get();
    const userData = userDoc.data();

    if (!userData) {
      throw new functions.https.HttpsError(
        "not-found",
        "Usuário não encontrado"
      );
    }

    // Verifica flag de VIP e expiração
    const now = admin.firestore.Timestamp.now();
    const isVip = userData.user_is_vip === true ||
      (userData.vipExpiresAt && userData.vipExpiresAt > now);

    // 4. Definir Limites
    // Resultados: Free: 17, VIP: 300
    const limit = isVip ? 300 : 17;

    // Cap de Raio por Plano (Segurança e Custo)
    // Free: max 15km | VIP: max 50km
    const planCap = isVip ? 50 : 15;

    // Default Radius: Evita busca "BoxOnly" que pode ser muito ampla/custosa
    const defaultRadius = isVip ? 20 : 8;

    const validRadiusKm = typeof radiusKm === "number" ?
      Math.min(radiusKm, planCap) :
      defaultRadius;

    // Firestore Limit: Tenta buscar um pouco mais para VIPs em áreas densas
    const fetchLimit = isVip ? 800 : 400;

    console.log(
      `🔍 [getPeople] User ${userId} - VIP:${isVip}, ` +
      `FetchLimit:${fetchLimit}, Radius:${validRadiusKm.toFixed(1)}km`
    );

    // 5. Query Firestore com bounding box (primeira filtragem)
    // Band-aid: .limit(fetchLimit) evita estouro de reads.
    const query = admin.firestore()
      .collection("Users")
      .where("latitude", ">=", boundingBox.minLat)
      .where("latitude", "<=", boundingBox.maxLat)
      .limit(fetchLimit);

    const usersSnap = await query.get();

    console.log(`📦 [getPeople] Firestore: ${usersSnap.docs.length} users`);

    // 6. Filtrar em memória e Mapear DTO
    const candidates = usersSnap.docs
      // Passo 1: Pré-cálculo e Filtros
      .map((doc) => {
        const d = doc.data();
        // Calcula distância para uso em filtro e sort
        // Se lat/lng inválidos, joga distância para infinito.
        const lat = d.latitude;
        const lng = d.longitude;

        const hasCoord = typeof lat === "number" && typeof lng === "number";

        const dist = hasCoord ?
          calculateDistance(centerLat, centerLng, lat, lng) :
          999999;

        return {doc, d, dist, lat, lng};
      })
      .filter(({doc, d, dist, lng}) => {
        if (doc.id === userId) return false; // Excluir próprio usuário

        // Status do usuário: por segurança, não retornar perfis inativos.
        const status = d.status;
        if (status != null && status !== "active") {
          return false;
        }

        // Filtro de longitude (Firestore só permite 1 range query)
        // Correção bug lng=0: checagem explicita de tipo
        if (
          typeof lng !== "number" ||
          lng < boundingBox.minLng ||
          lng > boundingBox.maxLng
        ) {
          return false;
        }

        // Filtro de Raio Real (Circular)
        // Agora sempre existe um limite de raio (Client ou Default)
        if (dist > validRadiusKm) {
          return false;
        }

        // Aplicar filtros avançados se fornecidos
        if (filters) {
          // Gender (Case-insensitive)
          if (filters.gender && filters.gender !== "all") {
            const userGender = d.gender ?
              String(d.gender).trim().toLowerCase() :
              "";
            const filterGender = String(filters.gender).trim().toLowerCase();
            if (userGender !== filterGender) return false;
          }

          // Age
          if (filters.minAge || filters.maxAge) {
            const age = d.age;
            if (typeof age === "number") {
              if (filters.minAge && age < filters.minAge) return false;
              if (filters.maxAge && age > filters.maxAge) return false;
            }
          }

          // Verified
          if (filters.isVerified === true && !d.user_is_verified) {
            return false;
          }

          // Sexual Orientation (Case-insensitive)
          if (filters.sexualOrientation &&
              filters.sexualOrientation !== "all") {
            const userOrientation = d.sexualOrientation ?
              String(d.sexualOrientation).trim().toLowerCase() : "";
            const filterOrientation = String(filters.sexualOrientation)
              .trim().toLowerCase();

            if (userOrientation !== filterOrientation) {
              return false;
            }
          }

          // Interests (Pelo menos UM interesse em comum)
          if (filters.interests &&
            Array.isArray(filters.interests) &&
            filters.interests.length > 0) {
            const userInterests: string[] = Array.isArray(d.interests) ?
              d.interests.map((i: unknown) =>
                String(i).trim().toLowerCase()
              ) :
              [];

            const filterInterests = filters.interests.map((i: string) =>
              String(i).trim().toLowerCase());

            // Verifica se há intersecção entre users e filter interests
            const hasCommonInterest = filterInterests.some((interest: string) =>
              userInterests.includes(interest)
            );

            if (!hasCommonInterest) return false;
          }
        }

        return true;
      })
      .map(({doc, d, dist, lat, lng}) => {
        // DTO (Data Transfer Object) - Whitelist Estrita
        const PRIVACY_KM = 2.5;

        let quantizedLat: number | null = null;
        let quantizedLng: number | null = null;

        if (typeof lat === "number" && typeof lng === "number") {
          const latDeg = kmToLatDeg(PRIVACY_KM);
          const lngDeg = kmToLngDeg(PRIVACY_KM, lat);

          quantizedLat = quantize(lat, latDeg);
          quantizedLng = quantize(lng, lngDeg);
        }

        return {
          userId: doc.id,
          fullName: d.fullName,
          photoUrl: d.photoUrl,
          // 🔒 Privacidade: Quantização (~2.5km)
          // Retorna apenas o centro do tile, impedindo triangulação exata.
          latitude: quantizedLat,
          longitude: quantizedLng,
          // Tile ID para Clusterização no Client
          // (evita empilhamento visual de markers/dízimas)
          tileId:
            (quantizedLat !== null && quantizedLng !== null) ?
              `${quantizedLat.toFixed(5)}:${quantizedLng.toFixed(5)}` :
              null,
          distanceInKm: Math.round(dist),
          // Distância arredondada (privacy-friendly: 5km, 6km...)
          age: d.age,
          gender: d.gender,
          user_is_verified: d.user_is_verified,
          overallRating: d.overallRating,
          vip_priority: d.vip_priority,
          sexualOrientation: d.sexualOrientation,
          interests: d.interests,
          _distance: dist, // Mantido para ordenação server-side
        };
      });

    console.log(`🔍 [getPeople] Após filtros: ${candidates.length} candidatos`);

    // 7. Ordenar por VIP Priority → Rating → Distância (Server-side sort)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    candidates.sort((a: any, b: any) => {
      // 1. VIP Priority (ASC: 1 vem antes de 2)
      const vipA = a.vip_priority ?? 2;
      const vipB = b.vip_priority ?? 2;
      if (vipA !== vipB) return vipA - vipB;

      // 2. Overall Rating (DESC: maior vem antes)
      const ratingA = a.overallRating ?? 0;
      const ratingB = b.overallRating ?? 0;
      if (ratingA !== ratingB) return ratingB - ratingA;

      // 3. Distância: Usamos a pré-calculada
      return a._distance - b._distance;
    });

    // 8. Aplicar limite server-side e remover metadados internos
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const limitedUsers = candidates
      .slice(0, limit)
      .map(({_distance, ...u}) => u);

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const top3 = limitedUsers.slice(0, 3).map((u: any) =>
      `[${u.userId}] (VIP:${u.vip_priority ?? 2}, ` +
      `⭐${u.overallRating?.toFixed(1) ?? "N/A"})`
    ).join(", ");
    console.log(`🏆 [getPeople] Top 3 metadados: ${top3}`);

    // 9. Retornar dados completos (client precisa para UI e Analytics)
    return {
      users: limitedUsers,
      isVip: isVip,
      limitApplied: limit,
      fetchedCount: usersSnap.size,
      totalCandidates: candidates.length,
      returnedCount: limitedUsers.length,
    };
  } catch (error) {
    console.error("❌ Erro em getPeople:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Erro ao buscar pessoas: " + (error as Error).message
    );
  }
});
