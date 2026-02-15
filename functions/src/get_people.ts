import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {buildInterestBuckets} from "./utils/interestBuckets";

type PeopleCacheEntry = {
  value: {
    users: unknown[];
    isVip: boolean;
    limitApplied: number;
    fetchedCount: number;
    totalCandidates: number;
    returnedCount: number;
  };
  expiresAt: number;
};

const PEOPLE_CACHE_TTL_MS = 60 * 60 * 1000; // 1 hora
const PEOPLE_CACHE_MAX_ENTRIES = 200;
const peopleCache = new Map<string, PeopleCacheEntry>();

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

const GRID_BUCKET_SIZE_DEG = 0.05;
const CACHE_KEY_BUCKET_DEG = 0.01;

function gridBucket(value: number, bucketSize: number): number {
  return Math.floor(value / bucketSize);
}

function buildGridIdsForBounds(
  boundingBox: {minLat: number; maxLat: number; minLng: number; maxLng: number},
  bucketSize: number
): string[] {
  const minLatBucket = gridBucket(boundingBox.minLat, bucketSize);
  const maxLatBucket = gridBucket(boundingBox.maxLat, bucketSize);
  const minLngBucket = gridBucket(boundingBox.minLng, bucketSize);
  const maxLngBucket = gridBucket(boundingBox.maxLng, bucketSize);

  const gridIds: string[] = [];
  for (let latBucket = minLatBucket; latBucket <= maxLatBucket; latBucket++) {
    for (let lngBucket = minLngBucket; lngBucket <= maxLngBucket; lngBucket++) {
      gridIds.push(`${latBucket}_${lngBucket}`);
    }
  }
  return gridIds;
}

function normalizeFilters(filters: Record<string, unknown> | undefined) {
  if (!filters) return {};
  const normalized = {...filters};
  const interests = normalized.interests as unknown;
  if (Array.isArray(interests)) {
    normalized.interests = interests
      .map((i) => String(i).trim().toLowerCase())
      .filter((i) => i.length > 0)
      .sort();
  }
  return normalized;
}

function computeZoomBucket(deltaLat: number, deltaLng: number): string {
  const maxDelta = Math.max(deltaLat, deltaLng);
  if (maxDelta > 0.3) return "z0";
  if (maxDelta > 0.15) return "z1";
  if (maxDelta > 0.07) return "z2";
  return "z3";
}

function buildCacheKey(params: {
  boundingBox: {minLat: number; maxLat: number; minLng: number; maxLng: number};
  filters: Record<string, unknown> | undefined;
  plan: string;
}): string {
  const {boundingBox, filters, plan} = params;
  const deltaLat = Math.abs(boundingBox.maxLat - boundingBox.minLat);
  const deltaLng = Math.abs(boundingBox.maxLng - boundingBox.minLng);
  const centerLat = (boundingBox.minLat + boundingBox.maxLat) / 2;
  const centerLng = (boundingBox.minLng + boundingBox.maxLng) / 2;
  const centerLatBucket = gridBucket(centerLat, CACHE_KEY_BUCKET_DEG);
  const centerLngBucket = gridBucket(centerLng, CACHE_KEY_BUCKET_DEG);
  const bucketCenterLat = centerLatBucket * CACHE_KEY_BUCKET_DEG;
  const bucketCenterLng = centerLngBucket * CACHE_KEY_BUCKET_DEG;
  const bucket = computeZoomBucket(deltaLat, deltaLng);
  const filtersHash = JSON.stringify(normalizeFilters(filters));
  const tileKey = `${bucketCenterLat.toFixed(3)}:${bucketCenterLng.toFixed(3)}`;
  return `${plan}|${bucket}|${tileKey}|${filtersHash}`;
}

function getCachedResponse(key: string) {
  const entry = peopleCache.get(key);
  if (!entry) return null;
  if (Date.now() > entry.expiresAt) {
    peopleCache.delete(key);
    return null;
  }
  peopleCache.delete(key);
  peopleCache.set(key, entry);
  return entry.value;
}

function setCachedResponse(key: string, value: PeopleCacheEntry["value"]) {
  if (peopleCache.has(key)) {
    peopleCache.delete(key);
  }
  peopleCache.set(key, {
    value,
    expiresAt: Date.now() + PEOPLE_CACHE_TTL_MS,
  });

  if (peopleCache.size > PEOPLE_CACHE_MAX_ENTRIES) {
    const firstKey = peopleCache.keys().next().value;
    if (firstKey) {
      peopleCache.delete(firstKey);
    }
  }
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

  const startTime = Date.now();

  try {
    // 2. Parâmetros recebidos do client
    const {
      boundingBox: rawBoundingBox, // { minLat, maxLat, minLng, maxLng }
      filters,
      center, // { lat, lng } - Opcional (melhora precisão)
      radiusKm, // Opcional (KM). Filtra fora deste raio.
    } = data;

    if (!rawBoundingBox || typeof rawBoundingBox !== "object") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "boundingBox é obrigatório"
      );
    }

    const rawMinLat = (rawBoundingBox as Record<string, unknown>).minLat;
    const rawMaxLat = (rawBoundingBox as Record<string, unknown>).maxLat;
    const rawMinLng = (rawBoundingBox as Record<string, unknown>).minLng;
    const rawMaxLng = (rawBoundingBox as Record<string, unknown>).maxLng;

    const isFiniteNumber = (value: unknown): value is number =>
      typeof value === "number" && Number.isFinite(value);

    if (
      !isFiniteNumber(rawMinLat) ||
      !isFiniteNumber(rawMaxLat) ||
      !isFiniteNumber(rawMinLng) ||
      !isFiniteNumber(rawMaxLng)
    ) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "boundingBox inválido (minLat/maxLat/minLng/maxLng)"
      );
    }

    let minLat = Math.min(rawMinLat, rawMaxLat);
    let maxLat = Math.max(rawMinLat, rawMaxLat);
    let minLng = Math.min(rawMinLng, rawMaxLng);
    let maxLng = Math.max(rawMinLng, rawMaxLng);

    minLat = Math.max(-90, Math.min(90, minLat));
    maxLat = Math.max(-90, Math.min(90, maxLat));
    minLng = Math.max(-180, Math.min(180, minLng));
    maxLng = Math.max(-180, Math.min(180, maxLng));

    const boundingBox = {
      minLat,
      maxLat,
      minLng,
      maxLng,
    };

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
    // Aceita {lat,lng} ou {latitude,longitude}
    const rawLat = center?.lat ?? center?.latitude;
    const rawLng = center?.lng ?? center?.longitude;

    const isLatValid = typeof rawLat === "number" &&
      Number.isFinite(rawLat);
    const centerLat = isLatValid ?
      rawLat :
      (boundingBox.minLat + boundingBox.maxLat) / 2;

    const isLngValid = typeof rawLng === "number" &&
      Number.isFinite(rawLng);
    const centerLng = isLngValid ?
      rawLng :
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
    // ✅ Verifica múltiplos campos por compatibilidade
    const now = admin.firestore.Timestamp.now();
    const hasVipFlag = userData.user_is_vip === true ||
      userData.isVip === true ||
      userData.vip === true;
    const hasVipLevel = userData.user_level === "vip";
    const hasValidExpiration = userData.vipExpiresAt &&
      userData.vipExpiresAt.toMillis &&
      userData.vipExpiresAt.toMillis() > now.toMillis();

    const isVip = hasVipFlag || hasVipLevel || hasValidExpiration;

    // 📊 Log detalhado para debug
    console.log(`👑 [getPeople] VIP Check for ${userId}:`, {
      user_is_vip: userData.user_is_vip,
      isVip_field: userData.isVip,
      vip_field: userData.vip,
      user_level: userData.user_level,
      vipExpiresAt: userData.vipExpiresAt?.toDate?.() || null,
      hasVipFlag,
      hasVipLevel,
      hasValidExpiration,
      finalIsVip: isVip,
    });

    // 4. Definir Limites
    // Free: 17 | VIP: 500 (cobre a maioria dos cenários reais)
    // Lista já vem ordenada por VIP → Rating → Distância
    const limit = isVip ? 500 : 17;

    // Cap de Raio por Plano (Segurança e Custo)
    // Free: max 15km | VIP: max 30km
    const planCap = isVip ? 30 : 15;

    // Default Radius: Evita busca "BoxOnly" que pode ser muito ampla/custosa
    const defaultRadius = isVip ? 20 : 8;

    const validRadiusKm = typeof radiusKm === "number" ?
      Math.min(radiusKm, planCap) :
      defaultRadius;

    // Firestore Limit: dinâmico (sobe se não atingir resultados mínimos)
    // VIP: busca mais agressiva para pegar todos disponíveis
    const baseFetchLimit = isVip ? 600 : 200;
    const maxFetchLimit = isVip ? 1500 : 400;
    const minResults = isVip ? 200 : 17;

    console.log(
      `🔍 [getPeople] User ${userId} - VIP:${isVip}, ` +
      `FetchLimit:${baseFetchLimit}, Radius:${validRadiusKm.toFixed(1)}km`
    );

    const cacheKey = buildCacheKey({
      boundingBox,
      filters,
      plan: isVip ? "vip" : "free",
    });

    const interestBuckets = buildInterestBuckets(filters?.interests);
    const gridIds = buildGridIdsForBounds(
      boundingBox,
      GRID_BUCKET_SIZE_DEG
    );
    const canUseGridQueryBase = gridIds.length > 0 && gridIds.length <= 10;

    const cachedResponse = getCachedResponse(cacheKey);
    if (cachedResponse) {
      const durationMs = Date.now() - startTime;
      console.log("📊 [getPeople] Cache HIT", {
        cacheKey,
        cacheSize: peopleCache.size,
        cacheKeyBucket: CACHE_KEY_BUCKET_DEG,
        durationMs,
        returnedCount: cachedResponse.returnedCount,
        totalCandidates: cachedResponse.totalCandidates,
      });
      return cachedResponse;
    }

    async function fetchCandidates(
      fetchLimit: number,
      options: {disableInterestBuckets?: boolean} = {}
    ) {
      const canUseGridQuery = canUseGridQueryBase;
      const canUseInterestBuckets = !canUseGridQuery &&
        !options.disableInterestBuckets &&
        interestBuckets.length > 0 &&
        interestBuckets.length <= 10;

      let queryPath: "interestBuckets" | "grid" | "latRange" | "usersFallback" =
        "latRange";

      let previewQuery = admin.firestore()
        .collection("users_preview")
        .where("status", "==", "active")
        .limit(fetchLimit);

      if (canUseInterestBuckets) {
        queryPath = "interestBuckets";
        previewQuery = previewQuery
          .where("interestBuckets", "array-contains-any", interestBuckets)
          .where("latitude", ">=", boundingBox.minLat)
          .where("latitude", "<=", boundingBox.maxLat);
      } else if (canUseGridQuery) {
        queryPath = "grid";
        previewQuery = previewQuery
          .where("gridId", "in", gridIds)
          .where("latitude", ">=", boundingBox.minLat)
          .where("latitude", "<=", boundingBox.maxLat);
      } else {
        queryPath = "latRange";
        previewQuery = previewQuery
          .where("latitude", ">=", boundingBox.minLat)
          .where("latitude", "<=", boundingBox.maxLat);
      }

      let usersSnap = await previewQuery.get();

      let interestBucketsFallbackUsed = false;
      if (usersSnap.empty && canUseInterestBuckets) {
        interestBucketsFallbackUsed = true;
        queryPath = "latRange";
        const fallbackPreviewQuery = admin.firestore()
          .collection("users_preview")
          .where("status", "==", "active")
          .where("latitude", ">=", boundingBox.minLat)
          .where("latitude", "<=", boundingBox.maxLat)
          .limit(fetchLimit);
        usersSnap = await fallbackPreviewQuery.get();
      }

      if (usersSnap.empty && canUseGridQuery) {
        queryPath = "latRange";
        const fallbackPreviewQuery = admin.firestore()
          .collection("users_preview")
          .where("status", "==", "active")
          .where("latitude", ">=", boundingBox.minLat)
          .where("latitude", "<=", boundingBox.maxLat)
          .limit(fetchLimit);
        usersSnap = await fallbackPreviewQuery.get();
      }

      if (usersSnap.empty) {
        queryPath = "usersFallback";
        const fallbackQuery = admin.firestore()
          .collection("Users")
          .where("status", "==", "active")
          .where("latitude", ">=", boundingBox.minLat)
          .where("latitude", "<=", boundingBox.maxLat)
          .limit(fetchLimit);
        usersSnap = await fallbackQuery.get();
      }

      console.log(`📦 [getPeople] Firestore: ${usersSnap.docs.length} users`);

      let discardedByLongitude = 0;
      let discardedByRadius = 0;
      let discardedByTags = 0;
      let discardedByAgeGender = 0;
      let discardedByVerified = 0;
      let discardedByStatus = 0;

      const candidates: any[] = [];

      for (const doc of usersSnap.docs) {
        const d = doc.data();
        if (doc.id === userId) continue;

        const status = d.status;
        if (status != null && status !== "active") {
          discardedByStatus++;
          continue;
        }

        const lat = d.latitude;
        const lng = d.longitude;
        const hasCoord = typeof lat === "number" && typeof lng === "number";

        if (
          !hasCoord ||
          lng < boundingBox.minLng ||
          lng > boundingBox.maxLng
        ) {
          discardedByLongitude++;
          continue;
        }

        const dist = calculateDistance(centerLat, centerLng, lat, lng);

        if (dist > validRadiusKm) {
          discardedByRadius++;
          continue;
        }

        if (filters) {
          if (filters.gender && filters.gender !== "all") {
            const userGender = d.gender ?
              String(d.gender).trim().toLowerCase() :
              "";
            const filterGender = String(filters.gender).trim().toLowerCase();
            if (userGender !== filterGender) {
              discardedByAgeGender++;
              continue;
            }
          }

          if (filters.minAge || filters.maxAge) {
            const age = d.age;
            if (typeof age === "number") {
              if (filters.minAge && age < filters.minAge) {
                discardedByAgeGender++;
                continue;
              }
              if (filters.maxAge && age > filters.maxAge) {
                discardedByAgeGender++;
                continue;
              }
            }
          }

          if (filters.isVerified === true && !d.user_is_verified) {
            discardedByVerified++;
            continue;
          }

          if (filters.sexualOrientation &&
              filters.sexualOrientation !== "all") {
            const userOrientation = d.sexualOrientation ?
              String(d.sexualOrientation).trim().toLowerCase() : "";
            const filterOrientation = String(filters.sexualOrientation)
              .trim().toLowerCase();

            if (userOrientation !== filterOrientation) {
              discardedByAgeGender++;
              continue;
            }
          }

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

            const hasCommonInterest = filterInterests.some((interest: string) =>
              userInterests.includes(interest)
            );

            if (!hasCommonInterest) {
              discardedByTags++;
              continue;
            }
          }
        }

        const PRIVACY_KM = 2.5;
        let quantizedLat: number | null = null;
        let quantizedLng: number | null = null;

        if (typeof lat === "number" && typeof lng === "number") {
          const latDeg = kmToLatDeg(PRIVACY_KM);
          const lngDeg = kmToLngDeg(PRIVACY_KM, lat);

          quantizedLat = quantize(lat, latDeg);
          quantizedLng = quantize(lng, lngDeg);
        }

        candidates.push({
          userId: doc.id,
          fullName: d.fullName,
          photoUrl: d.photoUrl,
          latitude: quantizedLat,
          longitude: quantizedLng,
          tileId:
            (quantizedLat !== null && quantizedLng !== null) ?
              `${quantizedLat.toFixed(5)}:${quantizedLng.toFixed(5)}` :
              null,
          distanceInKm: Math.round(dist / 2) * 2,
          age: d.age,
          isVerified: d.isVerified ?? d.user_is_verified,
          overallRating: d.overallRating,
          vip_priority: d.vip_priority,
          locality: d.locality,
          state: d.state,
          lastActiveAt: d.lastActiveAt,
          _distance: dist,
        });
      }

      console.log(`🔍 [getPeople] Após filtros: ${candidates.length} candidatos`);
      return {
        usersSnap,
        candidates,
        discardedByLongitude,
        discardedByRadius,
        discardedByTags,
        discardedByAgeGender,
        discardedByVerified,
        discardedByStatus,
        gridQueryUsed: canUseGridQuery,
        gridIdsCount: gridIds.length,
        interestBucketsUsed: canUseInterestBuckets,
        interestBucketsCount: interestBuckets.length,
        interestBucketsFallbackUsed,
        queryPath,
      };
    }

    let {
      usersSnap,
      candidates,
      discardedByLongitude,
      discardedByRadius,
      discardedByTags,
      discardedByAgeGender,
      discardedByVerified,
      discardedByStatus,
      gridQueryUsed,
      gridIdsCount,
      interestBucketsUsed,
      interestBucketsCount,
      interestBucketsFallbackUsed,
      queryPath,
    } = await fetchCandidates(baseFetchLimit);

    if (interestBucketsUsed && candidates.length < minResults) {
      console.log(
        `🔁 [getPeople] Fallback sem interestBuckets (candidatos ${candidates.length}/${minResults})`
      );
      ({
        usersSnap,
        candidates,
        discardedByLongitude,
        discardedByRadius,
        discardedByTags,
        discardedByAgeGender,
        discardedByVerified,
        discardedByStatus,
        gridQueryUsed,
        gridIdsCount,
        interestBucketsUsed,
        interestBucketsCount,
        interestBucketsFallbackUsed,
        queryPath,
      } = await fetchCandidates(baseFetchLimit, {
        disableInterestBuckets: true,
      }));
    }
    let fetchLimitUsed = baseFetchLimit;
    if (candidates.length < minResults && baseFetchLimit < maxFetchLimit) {
      console.log(
        `🔁 [getPeople] Subindo fetchLimit para ${maxFetchLimit} (candidatos ${candidates.length}/${minResults})`
      );
      ({
        usersSnap,
        candidates,
        discardedByLongitude,
        discardedByRadius,
        discardedByTags,
        discardedByAgeGender,
        discardedByVerified,
        discardedByStatus,
        gridQueryUsed,
        gridIdsCount,
        interestBucketsUsed,
        interestBucketsCount,
        interestBucketsFallbackUsed,
        queryPath,
      } = await fetchCandidates(maxFetchLimit));
      fetchLimitUsed = maxFetchLimit;

      if (interestBucketsUsed && candidates.length < minResults) {
        console.log(
          `🔁 [getPeople] Fallback sem interestBuckets (candidatos ${candidates.length}/${minResults})`
        );
        ({
          usersSnap,
          candidates,
          discardedByLongitude,
          discardedByRadius,
          discardedByTags,
          discardedByAgeGender,
          discardedByVerified,
          discardedByStatus,
          gridQueryUsed,
          gridIdsCount,
          interestBucketsUsed,
          interestBucketsCount,
          interestBucketsFallbackUsed,
          queryPath,
        } = await fetchCandidates(maxFetchLimit, {
          disableInterestBuckets: true,
        }));
      }
    }

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
    const hasMore = candidates.length > limit;
    const response = {
      users: limitedUsers,
      isVip: isVip,
      limitApplied: limit,
      fetchedCount: usersSnap.size,
      totalCandidates: candidates.length,
      returnedCount: limitedUsers.length,
      hasMore, // Indica se há mais usuários além do limite
    };

    const durationMs = Date.now() - startTime;
    const wasteRatioByReturned = limitedUsers.length > 0
      ? Number((usersSnap.size / limitedUsers.length).toFixed(3))
      : null;
    const wasteRatioByCandidates = candidates.length > 0
      ? Number((usersSnap.size / candidates.length).toFixed(3))
      : null;

    console.log("📊 [getPeople] Metrics", {
      cacheKey,
      cacheSize: peopleCache.size,
      cacheKeyBucket: CACHE_KEY_BUCKET_DEG,
      cacheHit: false,
      durationMs,
      scanLimitUsed: fetchLimitUsed,
      scannedDocs: usersSnap.size,
      queryPath,
      gridQueryUsed,
      gridIdsCount,
      interestBucketsUsed,
      interestBucketsCount,
      interestBucketsFallbackUsed,
      discardedByLongitude,
      discardedByRadius,
      discardedByTags,
      discardedByAgeGender,
      discardedByVerified,
      discardedByStatus,
      totalCandidates: candidates.length,
      returnedCount: limitedUsers.length,
      wasteRatioByReturned,
      wasteRatioByCandidates,
    });

    setCachedResponse(cacheKey, response);

    return response;
  } catch (error) {
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    const err = error as Error;
    console.error("❌ Erro em getPeople:", {
      message: err?.message,
      stack: err?.stack,
    });
    throw new functions.https.HttpsError(
      "internal",
      "Erro ao buscar pessoas: " + (err?.message ?? "unknown")
    );
  }
});
