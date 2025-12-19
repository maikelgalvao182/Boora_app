import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Inicializa o admin SDK se ainda não foi inicializado
if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Cloud Function para buscar pessoas próximas com limite baseado em VIP.
 *
 * 🔒 SEGURANÇA SERVER-SIDE:
 * - Verifica status VIP no Firestore (fonte da verdade)
 * - Limita quantidade de resultados (Free: 17, VIP: ilimitado)
 * - Ordenação garantida: vip_priority → overallRating → distância
 * - Firestore Rules bloqueiam acesso direto
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

  try {
    // 2. Parâmetros recebidos do client
    const {
      boundingBox, // { minLat, maxLat, minLng, maxLng }
      filters,
    } = data;

    if (!boundingBox) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "boundingBox é obrigatório"
      );
    }

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

    // 4. Definir Limite (Free: 17 para mostrar 12 + VipLockedCard)
    const limit = isVip ? 100 : 17;

    console.log(`🔍 [getPeople] User ${userId} - VIP:${isVip}, Limit:${limit}`);

    // 5. Query Firestore com bounding box (primeira filtragem)
    const query = admin.firestore()
      .collection("Users")
      .where("latitude", ">=", boundingBox.minLat)
      .where("latitude", "<=", boundingBox.maxLat);

    const usersSnap = await query.get();

    console.log(`📦 [getPeople] Firestore: ${usersSnap.docs.length} users`);

    // 6. Filtrar em memória (longitude, próprio usuário, filtros avançados)
    const candidates = usersSnap.docs
      .filter((doc) => {
        if (doc.id === userId) return false; // Excluir próprio usuário

        const d = doc.data();
        const lng = d.longitude;

        // Filtro de longitude (Firestore só permite 1 range query)
        if (!lng || lng < boundingBox.minLng || lng > boundingBox.maxLng) {
          return false;
        }

        // Aplicar filtros avançados se fornecidos
        if (filters) {
          // Gender
          if (filters.gender && filters.gender !== "all") {
            if (d.gender !== filters.gender) return false;
          }

          // Age
          if (filters.minAge || filters.maxAge) {
            const age = d.age;
            if (age) {
              if (filters.minAge && age < filters.minAge) return false;
              if (filters.maxAge && age > filters.maxAge) return false;
            }
          }

          // Verified
          if (filters.isVerified === true && !d.user_is_verified) {
            return false;
          }

          // Sexual Orientation
          if (filters.sexualOrientation &&
              filters.sexualOrientation !== "all") {
            if (d.sexualOrientation !== filters.sexualOrientation) {
              return false;
            }
          }
        }

        return true;
      })
      .map((doc) => ({
        userId: doc.id,
        ...doc.data(),
      }));

    console.log(`🔍 [getPeople] Após filtros: ${candidates.length} candidatos`);

    // 7. Ordenar por VIP Priority → Rating → (distância calculada no client)
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

      // 3. Sem distância aqui, será calculada no client
      return 0;
    });

    // 8. Aplicar limite server-side (SEGURANÇA)
    const limitedUsers = candidates.slice(0, limit);

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const top3 = limitedUsers.slice(0, 3).map((u: any) =>
      `${u.fullName} (VIP:${u.vip_priority ?? 2}, ` +
      `⭐${u.overallRating?.toFixed(1) ?? "N/A"})`
    ).join(", ");
    console.log(`🏆 [getPeople] Top 3: ${top3}`);

    // 9. Retornar dados completos (client precisa para UI)
    return {
      users: limitedUsers,
      isVip: isVip,
      limitApplied: limit,
      totalCandidates: candidates.length,
    };
  } catch (error) {
    console.error("❌ Erro em getPeople:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Erro ao buscar pessoas: " + (error as Error).message
    );
  }
});
