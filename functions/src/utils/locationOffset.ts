/**
 * 🔒 LOCATION OFFSET UTILITY
 *
 * Gera coordenadas display com offset determinístico para proteger privacidade.
 *
 * Características:
 * - Offset entre 300m e 1.5km
 * - Determinístico (mesmo userId = mesmo offset)
 * - Usa userId como seed
 * - Não revela localização exata
 */

/**
 * Gera um número pseudo-aleatório determinístico baseado em uma string seed.
 * Usa algoritmo simples de hash para garantir reprodutibilidade.
 *
 * @param {string} seed - String usada como seed (ex: userId)
 * @param {number} index - Índice para gerar múltiplos valores da mesma seed
 * @return {number} Número entre 0 e 1
 */
function seededRandom(seed: string, index: number): number {
  // Combina seed + index para gerar diferentes valores
  const combined = `${seed}-${index}`;

  // Hash simples mas eficaz
  let hash = 0;
  for (let i = 0; i < combined.length; i++) {
    const char = combined.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32bit integer
  }

  // Normaliza para [0, 1] - usa máscara para evitar overflow do abs()
  // Math.abs(hash) pode ser 2147483648 (overflow), então usamos bitwise AND
  const normalized = (hash & 0x7fffffff) / 2147483647;
  return normalized;
}

/**
 * Calcula coordenadas display com offset determinístico.
 *
 * Regras:
 * - Offset mínimo: 300 metros
 * - Offset máximo: 1500 metros (1.5 km)
 * - Direção aleatória mas fixa por userId
 * - Reprodutível (mesmo input = mesmo output)
 *
 * @param {number} realLat - Latitude real do usuário
 * @param {number} realLng - Longitude real do usuário
 * @param {string} userId - ID do usuário (usado como seed)
 * @return {object} Objeto com displayLatitude e displayLongitude
 * @throws {Error} Se coordenadas estiverem fora dos limites válidos
 */
export function generateDisplayLocation(
  realLat: number,
  realLng: number,
  userId: string
): { displayLatitude: number; displayLongitude: number } {
  // 🚨 VALIDAÇÃO CRÍTICA: Garantir que coordenadas são lat/lng em graus
  if (realLat < -90 || realLat > 90) {
    throw new Error(
      `🚨 ERRO CRÍTICO: Latitude inválida: ${realLat}\n` +
      "Latitude deve estar entre -90 e +90 graus.\n" +
      "Valor recebido parece ser coordenada projetada (Web Mercator), " +
      "não latitude em graus."
    );
  }

  if (realLng < -180 || realLng > 180) {
    throw new Error(
      `🚨 ERRO CRÍTICO: Longitude inválida: ${realLng}\n` +
      "Longitude deve estar entre -180 e +180 graus.\n" +
      "Valor recebido parece ser coordenada projetada (Web Mercator), " +
      "não longitude em graus."
    );
  }

  if (!userId || userId.trim().length === 0) {
    throw new Error("userId não pode ser vazio");
  }

  // Constantes
  const MIN_OFFSET_METERS = 300;
  const MAX_OFFSET_METERS = 1500;
  const EARTH_RADIUS_KM = 6371;

  // Gera valores determinísticos baseados no userId
  const random1 = seededRandom(userId, 0); // Para distância
  const random2 = seededRandom(userId, 1); // Para ângulo

  // Calcula distância do offset (entre 300m e 1500m)
  const offsetMeters = MIN_OFFSET_METERS +
    (random1 * (MAX_OFFSET_METERS - MIN_OFFSET_METERS));
  const offsetKm = offsetMeters / 1000;

  // Calcula ângulo aleatório (0 a 360 graus)
  const angle = random2 * 2 * Math.PI;

  // Converte offset para graus
  // 1 grau de latitude ≈ 111 km
  // 1 grau de longitude varia com a latitude
  const latOffset = (offsetKm / EARTH_RADIUS_KM) * (180 / Math.PI);
  const lngOffset = (offsetKm / EARTH_RADIUS_KM) * (180 / Math.PI) /
    Math.cos(realLat * Math.PI / 180);

  // Aplica offset na direção do ângulo
  const displayLatitude = realLat + (latOffset * Math.cos(angle));
  const displayLongitude = realLng + (lngOffset * Math.sin(angle));

  // 🚨 VALIDAÇÃO PÓS-CÁLCULO: Garantir que resultado também é válido
  if (displayLatitude < -90 || displayLatitude > 90) {
    throw new Error(
      "🚨 BUG NO ALGORITMO: displayLatitude calculada está fora " +
      `do range: ${displayLatitude}\n` +
      `Input: realLat=${realLat}, realLng=${realLng}\n` +
      "Isso indica um bug no cálculo do offset."
    );
  }

  if (displayLongitude < -180 || displayLongitude > 180) {
    throw new Error(
      "🚨 BUG NO ALGORITMO: displayLongitude calculada está fora " +
      `do range: ${displayLongitude}\n` +
      `Input: realLat=${realLat}, realLng=${realLng}\n` +
      "Isso indica um bug no cálculo do offset."
    );
  }

  // Log para debug (apenas em desenvolvimento)
  if (process.env.NODE_ENV !== "production") {
    console.log(
      "🔒 [LocationOffset] Generated for user " +
      `${userId.substring(0, 8)}...`
    );
    console.log(`   - Offset: ${offsetMeters.toFixed(0)}m`);
    console.log(
      `   - Angle: ${(angle * 180 / Math.PI).toFixed(1)}°`
    );
    console.log(
      `   - Real: (${realLat.toFixed(6)}, ${realLng.toFixed(6)})`
    );
    console.log(
      `   - Display: (${displayLatitude.toFixed(6)}, ` +
      `${displayLongitude.toFixed(6)})`
    );
  }

  return {
    displayLatitude,
    displayLongitude,
  };
}

/**
 * Calcula a distância real entre dois pontos usando Haversine.
 *
 * IMPORTANTE: Esta função deve usar SEMPRE as coordenadas REAIS,
 * nunca as display. Apenas para uso interno/backend.
 *
 * @param {number} lat1 - Latitude do ponto 1
 * @param {number} lng1 - Longitude do ponto 1
 * @param {number} lat2 - Latitude do ponto 2
 * @param {number} lng2 - Longitude do ponto 2
 * @return {number} Distância em quilômetros
 */
export function calculateRealDistance(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const EARTH_RADIUS_KM = 6371;

  const toRadians = (degrees: number) => degrees * Math.PI / 180;

  const dLat = toRadians(lat2 - lat1);
  const dLng = toRadians(lng2 - lng1);

  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
    Math.cos(toRadians(lat2)) *
    Math.sin(dLng / 2) *
    Math.sin(dLng / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return EARTH_RADIUS_KM * c;
}
