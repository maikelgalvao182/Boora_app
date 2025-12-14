import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Inicializa o admin SDK se ainda não foi inicializado
if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Cloud Function para buscar pessoas próximas com limite baseado em VIP.
 *
 * Esta função deve ser usada em substituição à query direta no client
 * para garantir que usuários não-VIP nunca recebam mais dados do que o
 * permitido.
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
    // 2. Verificar Status VIP (Fonte da Verdade: Firestore)
    // Não confiamos no client enviando "isVip: true"
    const userDoc = await admin.firestore()
      .collection("Users")
      .doc(userId)
      .get();
    const userData = userDoc.data();

    // Verifica flag de VIP e expiração
    const isVip = userData?.hasActiveVip === true ||
      (userData?.vipExpiresAt &&
        userData.vipExpiresAt.toDate() > new Date());

    // 3. Definir Limite
    // Free: 13 pessoas
    // VIP: 50 pessoas (ou mais, dependendo da regra de negócio)
    const limit = isVip ? 50 : 13;

    console.log(`🔍 getPeople: User ${userId} isVip=${isVip}, limit=${limit}`);

    // 4. Parâmetros de Busca (recebidos do client)
    // Nota: Geoqueries complexas no Firestore nativo são limitadas.
    // Idealmente usar Geofire ou apenas filtrar por bounding box simples aqui.
    // Para este exemplo, vamos assumir uma busca simples por usuários ativos.

    // TODO: Implementar lógica de geohash ou bounding box se necessário
    // no server-side.
    // Por enquanto, retornamos os usuários mais recentes/ativos até o limite.

    const usersSnap = await admin.firestore()
      .collection("Users")
      .where("is_active", "==", true)
      // Ordenação VIP (1) -> Free (2)
      .orderBy("vip_priority", "asc")
      // Ordenação secundária por score (se existir) ou data de registro
      // .orderBy("ranking_score", "desc")
      // Excluir o próprio usuário (requer índice composto ou filtro em
      // memória se a lista for pequena)
      // .where(admin.firestore.FieldPath.documentId(), "!=", userId)
      .limit(limit)
      .get();

    // 5. Retornar Dados Sanitizados
    // Retornamos apenas os dados públicos necessários para o card
    const users = usersSnap.docs
      .filter((doc) => doc.id !== userId) // Filtro de segurança extra
      .map((doc) => {
        const d = doc.data();
        return {
          userId: doc.id,
          fullName: d.fullName,
          photoUrl: d.photoUrl,
          age: d.age,
          gender: d.gender,
          // Não retornar dados sensíveis!
          // location: d.location (se for preciso calcular distância no client)
        };
      });

    return {
      users: users,
      isVip: isVip,
      limitApplied: limit,
    };
  } catch (error) {
    console.error("❌ Erro em getPeople:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Erro ao buscar pessoas."
    );
  }
});
