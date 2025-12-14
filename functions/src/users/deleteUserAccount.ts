/**
 * Cloud Function: deleteUserAccount
 *
 * Deleta todos os registros do usuário no Firestore, EXCETO na coleção Events.
 *
 * Coleções afetadas:
 * - Users (documento principal)
 * - applications (sub-coleção e documentos onde userId aparece)
 * - reviews (documentos onde userId é reviewer ou reviewed)
 * - Connections (conversas onde userId é membro)
 * - Chats (mensagens enviadas pelo usuário)
 * - Notifications (notificações do usuário)
 * - profile_visits (visitas feitas ou recebidas)
 * - ranking (documentos de ranking do usuário)
 * - UserLocations (localização do usuário)
 * - blocked_users (bloqueios feitos ou recebidos)
 *
 * NÃO DELETA:
 * - events (mantém eventos criados pelo usuário para histórico)
 * - Firebase Auth (deve ser deletado manualmente pelo usuário ou admin)
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * Helper: Deleta documentos em lote
 * @param {string} collection Nome da coleção
 * @param {FirebaseFirestore.Query} query Query do Firestore
 * @param {number} batchSize Tamanho do lote
 * @return {Promise<number>} Número de documentos deletados
 */
async function batchDelete(
  collection: string,
  query: FirebaseFirestore.Query,
  batchSize = 500
): Promise<number> {
  let deletedCount = 0;

  const snapshot = await query.limit(batchSize).get();

  if (snapshot.empty) {
    return 0;
  }

  const batch = db.batch();
  snapshot.docs.forEach((doc) => {
    batch.delete(doc.ref);
    deletedCount++;
  });

  await batch.commit();

  // Se ainda há mais documentos, continua recursivamente
  if (snapshot.size >= batchSize) {
    const moreDeleted = await batchDelete(collection, query, batchSize);
    deletedCount += moreDeleted;
  }

  return deletedCount;
}

/**
 * Helper: Deleta sub-coleção de um documento
 * @param {FirebaseFirestore.DocumentReference} parentRef
 * Referência do documento pai
 * @param {string} subcollectionName Nome da sub-coleção
 * @return {Promise<number>} Número de documentos deletados
 */
async function deleteSubcollection(
  parentRef: FirebaseFirestore.DocumentReference,
  subcollectionName: string
): Promise<number> {
  const query = parentRef.collection(subcollectionName);
  return await batchDelete(subcollectionName, query);
}

export const deleteUserAccount = functions.https.onCall(
  async (data, context) => {
    console.log("🗑️ [DELETE_ACCOUNT] Iniciando Cloud Function");

    // Validação de autenticação
    if (!context.auth) {
      console.error("🗑️ [DELETE_ACCOUNT] ❌ Não autenticado");
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Usuário não autenticado"
      );
    }

    const userId = data.userId;

    // Validação do userId
    if (!userId || typeof userId !== "string") {
      console.error("🗑️ [DELETE_ACCOUNT] ❌ userId inválido");
      throw new functions.https.HttpsError(
        "invalid-argument",
        "userId é obrigatório"
      );
    }
    // Validação de permissão (apenas pode deletar própria conta)
    if (context.auth.uid !== userId) {
      console.error(
        "🗑️ [DELETE_ACCOUNT] ❌ Permissão negada. " +
        `Auth: ${context.auth.uid}, Requested: ${userId}`
      );
      throw new functions.https.HttpsError(
        "permission-denied",
        "Você só pode deletar sua própria conta"
      );
    }

    console.log(`🗑️ [DELETE_ACCOUNT] UserId: ${userId.substring(0, 8)}...`);

    const deletionStats = {
      users: 0,
      applications: 0,
      reviews: 0,
      connections: 0,
      chats: 0,
      notifications: 0,
      profileVisits: 0,
      ranking: 0,
      userLocations: 0,
      blockedUsers: 0,
    };

    try {
      // 1. Deletar sub-coleções do documento Users
      console.log("🗑️ [1/11] Deletando sub-coleções de Users...");
      const userRef = db.collection("Users").doc(userId);

      // Deletar applications sub-coleção
      const applicationsDeleted = await deleteSubcollection(
        userRef,
        "applications"
      );
      deletionStats.applications += applicationsDeleted;
      console.log(`✅ Deletadas ${applicationsDeleted} applications`);

      // 2. Deletar documento principal do usuário
      console.log("🗑️ [2/11] Deletando documento Users...");
      await userRef.delete();
      deletionStats.users = 1;
      console.log("✅ Documento Users deletado");

      // 3. Deletar reviews (como reviewer)
      console.log("🗑️ [3/11] Deletando reviews como reviewer...");
      const reviewsAsReviewer = await batchDelete(
        "Reviews",
        db.collection("Reviews").where("reviewer_id", "==", userId)
      );
      deletionStats.reviews += reviewsAsReviewer;
      console.log(`✅ Deletadas ${reviewsAsReviewer} reviews como reviewer`);

      // 4. Deletar reviews (como reviewed)
      console.log("🗑️ [4/11] Deletando reviews como reviewed...");
      const reviewsAsReviewed = await batchDelete(
        "Reviews",
        db.collection("Reviews").where("reviewee_id", "==", userId)
      );
      deletionStats.reviews += reviewsAsReviewed;
      console.log(`✅ Deletadas ${reviewsAsReviewed} reviews como reviewed`);

      // 5. Remover usuário de Connections (conversas)
      console.log("🗑️ [5/11] Removendo de Connections...");
      const connectionsSnapshot = await db
        .collection("Connections")
        .where("memberIds", "array-contains", userId)
        .get();

      const connectionBatch = db.batch();
      connectionsSnapshot.docs.forEach((doc) => {
        const data = doc.data();
        const memberIds = data.memberIds || [];
        const updatedMembers = memberIds.filter((id: string) => id !== userId);

        if (updatedMembers.length === 0) {
          // Se era a única pessoa, deleta a conversa
          connectionBatch.delete(doc.ref);
          deletionStats.connections++;
        } else {
          // Remove apenas o usuário da lista de membros
          connectionBatch.update(doc.ref, {
            memberIds: updatedMembers,
            [`members.${userId}`]: admin.firestore.FieldValue.delete(),
            lastMessageTime: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      });
      await connectionBatch.commit();
      console.log(`✅ Removido de ${connectionsSnapshot.size} Connections`);

      // 6. Deletar mensagens do Chats
      console.log("🗑️ [6/11] Deletando mensagens de Chats...");
      const chatsDeleted = await batchDelete(
        "Chats",
        db.collection("Chats").where("senderId", "==", userId)
      );
      deletionStats.chats = chatsDeleted;
      console.log(`✅ Deletadas ${chatsDeleted} mensagens`);

      // 7. Deletar notificações
      console.log("🗑️ [7/11] Deletando Notifications...");
      const notificationsDeleted = await batchDelete(
        "Notifications",
        db.collection("Notifications").where("userId", "==", userId)
      );
      deletionStats.notifications = notificationsDeleted;
      console.log(`✅ Deletadas ${notificationsDeleted} notificações`);

      // 8. Deletar visitas ao perfil (feitas) - ProfileVisits
      console.log("🗑️ [8/11] Deletando ProfileVisits (feitas)...");
      const visitsAsVisitor = await batchDelete(
        "ProfileVisits",
        db.collection("ProfileVisits").where("visitorId", "==", userId)
      );
      deletionStats.profileVisits += visitsAsVisitor;
      console.log(`✅ Deletadas ${visitsAsVisitor} visitas feitas`);

      // 9. Deletar visitas ao perfil (recebidas) - ProfileVisits
      console.log("🗑️ [9/11] Deletando ProfileVisits (recebidas)...");
      const visitsAsVisited = await batchDelete(
        "ProfileVisits",
        db.collection("ProfileVisits").where("visitedUserId", "==", userId)
      );
      deletionStats.profileVisits += visitsAsVisited;
      console.log(`✅ Deletadas ${visitsAsVisited} visitas recebidas`);

      // 9.5. Deletar visualizações para notificações - ProfileViews
      console.log("🗑️ [9.5/11] Deletando ProfileViews (como viewer)...");
      const viewsAsViewer = await batchDelete(
        "ProfileViews",
        db.collection("ProfileViews").where("viewerId", "==", userId)
      );
      console.log(`✅ Deletadas ${viewsAsViewer} views como viewer`);

      console.log("🗑️ [9.6/11] Deletando ProfileViews (recebidas)...");
      const viewsReceived = await batchDelete(
        "ProfileViews",
        db.collection("ProfileViews").where("viewedUserId", "==", userId)
      );
      console.log(`✅ Deletadas ${viewsReceived} views recebidas`);

      // 10. Deletar ranking
      console.log("🗑️ [10/11] Deletando ranking...");
      const rankingDeleted = await batchDelete(
        "ranking",
        db.collection("ranking").where("userId", "==", userId)
      );
      deletionStats.ranking = rankingDeleted;
      console.log(`✅ Deletados ${rankingDeleted} registros de ranking`);

      // 11. Deletar localização do usuário
      console.log("🗑️ [11/11] Deletando UserLocations...");
      const locationRef = db.collection("UserLocations").doc(userId);
      await locationRef.delete();
      deletionStats.userLocations = 1;
      console.log("✅ UserLocation deletada");

      // 12. Deletar bloqueios (como bloqueador)
      console.log("🗑️ [12/12] Deletando blocked_users (como bloqueador)...");
      const blocksAsBlocker = await batchDelete(
        "blocked_users",
        db.collection("blocked_users").where("blockerId", "==", userId)
      );
      deletionStats.blockedUsers += blocksAsBlocker;
      console.log(`✅ Deletados ${blocksAsBlocker} bloqueios feitos`);

      // 13. Deletar bloqueios (como bloqueado)
      console.log("🗑️ [13/13] Deletando blocked_users (como bloqueado)...");
      const blocksAsBlocked = await batchDelete(
        "blocked_users",
        db.collection("blocked_users").where("blockedUserId", "==", userId)
      );
      deletionStats.blockedUsers += blocksAsBlocked;
      console.log(`✅ Deletados ${blocksAsBlocked} bloqueios recebidos`);

      console.log("🗑️ [DELETE_ACCOUNT] ✅ Todos os dados deletados");
      console.log("📊 Estatísticas:", deletionStats);

      return {
        success: true,
        message: "Conta deletada com sucesso",
        stats: deletionStats,
      };
    } catch (error) {
      console.error("🗑️ [DELETE_ACCOUNT] ❌ Erro:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Erro ao deletar conta",
        error
      );
    }
  }
);
