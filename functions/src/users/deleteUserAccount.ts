/**
 * Cloud Function: deleteUserAccount
 *
 * Deleta todos os registros do usuário no Firestore, incluindo:
 * - eventos criados pelo usuário (coleção "events")
 * - coleções relacionadas a eventos (EventChats/Messages, EventApplications,
 *   conversas em Connections/Conversations, Notifications ligadas ao evento)
 *
 * Coleções afetadas:
 * - Users (documento principal)
 * - users_preview (documento de preview/cache do usuário)
 * - applications (sub-coleção e documentos onde userId aparece)
 * - reviews (documentos onde userId é reviewer ou reviewed)
 * - Connections (conversas onde userId é membro)
 * - Chats (mensagens enviadas pelo usuário)
 * - Notifications (notificações do usuário)
 * - ProfileVisits (visitas feitas ou recebidas)
 * - ProfileViews (visualizações para notificações)
 * - ranking (documentos de ranking do usuário)
 * - userRanking (ranking de usuário)
 * - locationRanking (ranking por localização)
 * - UserLocations (localização do usuário)
 * - blocked_users (bloqueios feitos ou recebidos)
 * - events (eventos criados pelo usuário)
 * - events_card_preview (previews de eventos criados)
 * - EventChats (+ subcoleção Messages) (chats dos eventos)
 * - EventApplications (aplicações/participações)
 * - EventPhotos (+ subcoleções comments e likes) (fotos de evento)
 * - feeds (items de feed recebidos por fanout + items criados pelo usuário)
 *
 * - Firebase Auth (deve ser deletado manualmente pelo usuário ou admin)
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const db = admin.firestore();

const BATCH_SIZE = 500;

type DeleteDirectChatResult = {
  messages: number;
  conversations: number;
};

/**
 * Deleta todos os docs de uma collection em batches.
 *
 * Observação: não deleta subcoleções dos documentos.
 *
 * @param {string} label Identificador para logs/debug.
 * @param {FirebaseFirestore.CollectionReference} collection Referência.
 * @param {number} batchSize Tamanho do batch (máx 500).
 * @return {Promise<number>} Quantidade de documentos deletados.
 */
async function deleteCollectionInBatches(
  label: string,
  collection: FirebaseFirestore.CollectionReference,
  batchSize: number = BATCH_SIZE
): Promise<number> {
  let deleted = 0;

  let hasMore = true;
  while (hasMore) {
    const snap = await collection.limit(batchSize).get();
    if (snap.empty) {
      hasMore = false;
      continue;
    }

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += snap.size;
  }

  // Mantém retorno explícito para agradar o lint/TS.
  return deleted;
}

/**
 * Deleta mensagens de um EventChat pertencentes ao usuário (por sender_id).
 *
 * @param {string} eventId ID do evento.
 * @param {string} userId ID do usuário.
 * @return {Promise<number>} Quantidade de mensagens deletadas.
 */
async function deleteEventChatMessagesBySender(
  eventId: string,
  userId: string
): Promise<number> {
  // EventChats/{eventId}/Messages onde sender_id == userId
  const query = db
    .collection("EventChats")
    .doc(eventId)
    .collection("Messages")
    .where("sender_id", "==", userId);

  return await batchDelete(
    `EventChats/${eventId}/Messages(sender_id=${userId})`,
    query
  );
}

/**
 * Deleta mensagens e conversas do chat 1x1 entre userId e otherUserId,
 * removendo ambos os lados (privacidade) e limpando Conversations.
 *
 * @param {string} userId ID do usuário.
 * @param {string} otherUserId ID do outro participante do chat.
 * @return {Promise<DeleteDirectChatResult>} Contagens removidas.
 */
async function deleteDirectChatPair(
  userId: string,
  otherUserId: string
): Promise<DeleteDirectChatResult> {
  let messages = 0;
  let conversations = 0;

  // Mensagens do usuário
  try {
    const ownThread = db
      .collection("Messages")
      .doc(userId)
      .collection(otherUserId);
    messages += await deleteCollectionInBatches(
      `Messages/${userId}/${otherUserId}`,
      ownThread
    );
  } catch (error) {
    console.warn(
      "🗑️ [DELETE_ACCOUNT] ⚠️ Falha ao deletar Messages do usuário:",
      userId,
      otherUserId,
      error
    );
  }

  // Mensagens do outro lado (privacidade)
  try {
    const otherThread = db
      .collection("Messages")
      .doc(otherUserId)
      .collection(userId);
    messages += await deleteCollectionInBatches(
      `Messages/${otherUserId}/${userId}`,
      otherThread
    );
  } catch (error) {
    console.warn(
      "🗑️ [DELETE_ACCOUNT] ⚠️ Falha ao deletar Messages do outro lado:",
      otherUserId,
      userId,
      error
    );
  }

  // Conversas (Connections) do usuário
  try {
    await db
      .collection("Connections")
      .doc(userId)
      .collection("Conversations")
      .doc(otherUserId)
      .delete();
    conversations += 1;
  } catch (_) {
    // best-effort
  }

  // Conversas (Connections) do outro lado
  try {
    await db
      .collection("Connections")
      .doc(otherUserId)
      .collection("Conversations")
      .doc(userId)
      .delete();
    conversations += 1;
  } catch (_) {
    // best-effort
  }

  return {messages, conversations};
}

type EventDeletionStats = {
  events: number;
  eventChats: number;
  eventChatMessages: number;
  eventApplications: number;
  eventConversations: number;
  eventNotifications: number;
};

/**
 * Deleta notificações relacionadas a um evento.
 * Busca por `eventId` no campo direto e também em `n_params.eventId`.
 * @param {string} eventId ID do evento
 * @return {Promise<number>} quantidade de notificações deletadas
 */
async function deleteEventNotifications(eventId: string): Promise<number> {
  let totalDeleted = 0;

  try {
    const directQuery = await db
      .collection("Notifications")
      .where("eventId", "==", eventId)
      .get();

    const paramsQuery = await db
      .collection("Notifications")
      .where("n_params.eventId", "==", eventId)
      .get();

    const docsToDelete = new Map<
      string,
      FirebaseFirestore.DocumentReference
    >();

    directQuery.docs.forEach((doc) => {
      docsToDelete.set(doc.id, doc.ref);
    });

    paramsQuery.docs.forEach((doc) => {
      docsToDelete.set(doc.id, doc.ref);
    });

    if (docsToDelete.size === 0) {
      return 0;
    }

    const refs = Array.from(docsToDelete.values());

    for (let i = 0; i < refs.length; i += BATCH_SIZE) {
      const batchRefs = refs.slice(i, i + BATCH_SIZE);
      const batch = db.batch();
      batchRefs.forEach((ref) => batch.delete(ref));
      await batch.commit();
    }

    totalDeleted = refs.length;
  } catch (error) {
    console.error(
      "🗑️ [DELETE_ACCOUNT] ❌ Erro ao deletar notificações do evento",
      eventId,
      error
    );
  }

  return totalDeleted;
}

/**
 * Tenta deletar arquivos do Storage associados ao evento.
 * É best-effort: falhas são logadas e não interrompem a deleção de conta.
 * @param {string} eventId ID do evento
 * @param {Record<string, unknown>|null|undefined} eventData dados do evento
 * @return {Promise<void>}
 */
async function deleteEventStorage(
  eventId: string,
  eventData: Record<string, unknown> | null | undefined
): Promise<void> {
  const storage = admin.storage();
  const bucket = storage.bucket();

  const paths = [
    `events/${eventId}`,
    `event_images/${eventId}`,
    `event_media/${eventId}`,
  ];

  for (const path of paths) {
    try {
      await bucket.deleteFiles({
        prefix: path,
      });
      console.log(`🗑️ [DELETE_ACCOUNT] Deleted files at ${path}`);
    } catch (err: unknown) {
      const error = err as Error;
      console.warn(
        `🗑️ [DELETE_ACCOUNT] ⚠️ Could not delete ${path}: ${error.message}`
      );
    }
  }

  const coverPhoto = eventData?.coverPhoto;
  if (typeof coverPhoto === "string" && coverPhoto.includes("firebase")) {
    try {
      const pathMatch = coverPhoto.match(/\/o\/(.+?)\?/);
      if (pathMatch) {
        const filePath = decodeURIComponent(pathMatch[1]);
        await bucket.file(filePath).delete();
        console.log(`🗑️ [DELETE_ACCOUNT] Deleted cover photo: ${filePath}`);
      }
    } catch (err: unknown) {
      const error = err as Error;
      console.warn(
        `🗑️ [DELETE_ACCOUNT] ⚠️ Could not delete cover photo: ${error.message}`
      );
    }
  }

  const photos = eventData?.photos;
  if (Array.isArray(photos)) {
    for (const photoUrl of photos) {
      if (typeof photoUrl === "string" && photoUrl.includes("firebase")) {
        try {
          const pathMatch = photoUrl.match(/\/o\/(.+?)\?/);
          if (pathMatch) {
            const filePath = decodeURIComponent(pathMatch[1]);
            await bucket.file(filePath).delete();
            console.log(
              `🗑️ [DELETE_ACCOUNT] Deleted gallery photo: ${filePath}`
            );
          }
        } catch (err: unknown) {
          const error = err as Error;
          console.warn(
            "🗑️ [DELETE_ACCOUNT] ⚠️ Could not delete gallery photo:",
            error.message
          );
        }
      }
    }
  }
}

/**
 * Deleta um evento do usuário e os dados relacionados (chats, aplicações,
 * conversas e notificações), além de tentar limpar Storage.
 * @param {string} eventId ID do evento
 * @param {string} userId ID do usuário (deve ser o createdBy)
 * @return {Promise<EventDeletionStats>} estatísticas da deleção
 */
async function deleteOwnedEventAndRelatedData(
  eventId: string,
  userId: string
): Promise<EventDeletionStats> {
  const stats: EventDeletionStats = {
    events: 0,
    eventChats: 0,
    eventChatMessages: 0,
    eventApplications: 0,
    eventConversations: 0,
    eventNotifications: 0,
  };

  const firestore = db;

  // 1) Validar evento e autoria
  const eventDoc = await firestore.collection("events").doc(eventId).get();
  if (!eventDoc.exists) {
    return stats;
  }

  const eventData = eventDoc.data();
  const createdBy = eventData?.createdBy;
  if (createdBy !== userId) {
    // Segurança: só deletar eventos do próprio usuário
    return stats;
  }

  // 2) Descobrir participantes (para remover conversas)
  const participantIds = new Set<string>();
  participantIds.add(userId);

  // participants do documento do evento
  const participantsObj = eventData?.participants as
    | {
        participantIds?: unknown;
        pendingApprovalIds?: unknown;
      }
    | undefined;

  const rawParticipantIds = participantsObj?.participantIds;
  if (Array.isArray(rawParticipantIds)) {
    rawParticipantIds.forEach((id) => {
      if (typeof id === "string") participantIds.add(id);
    });
  }

  const rawPendingIds = participantsObj?.pendingApprovalIds;
  if (Array.isArray(rawPendingIds)) {
    rawPendingIds.forEach((id) => {
      if (typeof id === "string") participantIds.add(id);
    });
  }

  // EventChat participants (se existir)
  const eventChatDoc = await firestore
    .collection("EventChats")
    .doc(eventId)
    .get();
  if (eventChatDoc.exists) {
    const rawChatParticipants = (
      eventChatDoc.data() as {participants?: unknown}
    )?.participants;
    if (Array.isArray(rawChatParticipants)) {
      rawChatParticipants.forEach((id) => {
        if (typeof id === "string") participantIds.add(id);
      });
    }
  }

  // EventApplications (participantes por aplicação)
  const applicationsSnapshot = await firestore
    .collection("EventApplications")
    .where("eventId", "==", eventId)
    .get();

  applicationsSnapshot.docs.forEach((doc) => {
    const appUserId = doc.data().userId;
    if (typeof appUserId === "string" && appUserId.length > 0) {
      participantIds.add(appUserId);
    }
  });

  // 3) Deletar mensagens do chat (subcoleção)
  const messagesDeleted = await batchDelete(
    "EventChats.Messages",
    firestore.collection("EventChats").doc(eventId).collection("Messages")
  );
  stats.eventChatMessages += messagesDeleted;

  // 4) Deletar notificações relacionadas ao evento
  stats.eventNotifications += await deleteEventNotifications(eventId);

  // 5) Operações em batch para deletar docs principais e referências
  const batches: FirebaseFirestore.WriteBatch[] = [];
  let currentBatch = firestore.batch();
  let operationCount = 0;
  const MAX_BATCH_SIZE = 500;

  const addToBatch = (
    operation: (batch: FirebaseFirestore.WriteBatch) => void
  ) => {
    if (operationCount >= MAX_BATCH_SIZE) {
      batches.push(currentBatch);
      currentBatch = firestore.batch();
      operationCount = 0;
    }
    operation(currentBatch);
    operationCount++;
  };

  // Deletar evento
  addToBatch((batch) => batch.delete(eventDoc.ref));
  stats.events += 1;

  // Deletar EventChats doc
  addToBatch((batch) =>
    batch.delete(firestore.collection("EventChats").doc(eventId))
  );
  stats.eventChats += 1;

  // Deletar EventApplications docs
  applicationsSnapshot.docs.forEach((doc) => {
    addToBatch((batch) => batch.delete(doc.ref));
    stats.eventApplications += 1;
  });

  // Deletar conversas do evento para todos os participantes
  const eventUserId = `event_${eventId}`;
  for (const participantId of participantIds) {
    const conversationRef = firestore
      .collection("Connections")
      .doc(participantId)
      .collection("Conversations")
      .doc(eventUserId);
    addToBatch((batch) => batch.delete(conversationRef));
    stats.eventConversations += 1;
  }

  if (operationCount > 0) {
    batches.push(currentBatch);
  }

  if (batches.length > 0) {
    await Promise.all(batches.map((batch) => batch.commit()));
  }

  // 6) Storage cleanup (best effort)
  try {
    await deleteEventStorage(
      eventId,
      (eventData ?? null) as Record<string, unknown> | null
    );
  } catch (error) {
    console.warn(
      `🗑️ [DELETE_ACCOUNT] ⚠️ Storage cleanup failed for event ${eventId}:`,
      error
    );
  }

  return stats;
}

/**
 * Remove vínculos do usuário com eventos de terceiros:
 * - deleta EventApplications do usuário
 * - remove conversa event_{eventId}
 * - remove userId de EventChats.participants e ajusta participantCount
 * - remove userId de events.participants
 * - ajusta currentCount quando aplicável
 * @param {string} userId ID do usuário
 * @return {Promise<void>}
 */
async function removeUserFromOtherEvents(userId: string): Promise<void> {
  // Remove o usuário de eventos em que ele tem aplicação.
  // Isso evita sobrar referência do userId em
  // EventApplications/EventChats/events.
  const firestore = db;

  const applicationsSnapshot = await firestore
    .collection("EventApplications")
    .where("userId", "==", userId)
    .get();

  if (applicationsSnapshot.empty) {
    return;
  }

  const eventIds = new Set<string>();
  applicationsSnapshot.docs.forEach((doc) => {
    const eventId = doc.data().eventId;
    if (typeof eventId === "string" && eventId.length > 0) {
      eventIds.add(eventId);
    }
  });

  // 1) Deletar todas as aplicações do usuário
  // (já remove pelo menos o vínculo principal)
  for (let i = 0; i < applicationsSnapshot.docs.length; i += BATCH_SIZE) {
    const batch = firestore.batch();
    const chunk = applicationsSnapshot.docs.slice(i, i + BATCH_SIZE);
    chunk.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }

  // 2) Remover conversa e remover do EventChat + limpar event.participants
  for (const eventId of eventIds) {
    // Conversa
    const eventUserId = `event_${eventId}`;
    await firestore
      .collection("Connections")
      .doc(userId)
      .collection("Conversations")
      .doc(eventUserId)
      .delete()
      .catch(() => undefined);

    // EventChat: remove do array e decrementa participantCount com segurança
    const eventChatRef = firestore.collection("EventChats").doc(eventId);
    const eventChatDoc = await eventChatRef.get();
    if (eventChatDoc.exists) {
      const eventChatData = eventChatDoc.data() as
        | {participants?: unknown; participantCount?: unknown}
        | undefined;
      const participants = Array.isArray(eventChatData?.participants) ?
        (eventChatData?.participants as unknown[]) :
        [];
      const currentCountRaw = eventChatData?.participantCount;
      const currentCount =
        typeof currentCountRaw === "number" ? currentCountRaw : 0;

      if (participants.includes(userId)) {
        await eventChatRef.update({
          participants: admin.firestore.FieldValue.arrayRemove(userId),
          participantCount: Math.max(0, currentCount - 1),
        });
      }
    }

    // Event doc participants: remove e clampa currentCount
    const eventRef = firestore.collection("events").doc(eventId);
    await firestore.runTransaction(async (tx) => {
      const eventDoc = await tx.get(eventRef);
      if (!eventDoc.exists) return;

      const data = eventDoc.data() as
        | {
            participants?: {
              participantIds?: unknown;
              pendingApprovalIds?: unknown;
              currentCount?: unknown;
            };
          }
        | undefined;

      const participants = data?.participants;
      const rawIds = participants?.participantIds;
      const rawPending = participants?.pendingApprovalIds;
      const currentCountRaw = participants?.currentCount;

      const participantIds = Array.isArray(rawIds) ?
        (rawIds as unknown[]) :
        [];
      const pendingIds = Array.isArray(rawPending) ?
        (rawPending as unknown[]) :
        [];
      const currentCount =
        typeof currentCountRaw === "number" ? currentCountRaw : 0;

      const wasParticipant = participantIds.some((id) => id === userId);
      const wasPending = pendingIds.some((id) => id === userId);

      if (!wasParticipant && !wasPending) return;

      const removeUserId = admin.firestore.FieldValue.arrayRemove(userId);

      const updateData = {
        "participants.participantIds": removeUserId,
        "participants.pendingApprovalIds": removeUserId,
      } as FirebaseFirestore.UpdateData<
        FirebaseFirestore.DocumentData
      >;

      if (wasParticipant) {
        updateData["participants.currentCount"] = Math.max(
          0,
          currentCount - 1
        );
      }

      tx.update(eventRef, updateData);
    });
  }
}

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
      usersPreview: 0,
      applications: 0,
      reviews: 0,
      connections: 0,
      chats: 0,
      notifications: 0,
      profileVisits: 0,
      ranking: 0,
      userRanking: 0,
      locationRanking: 0,
      userLocations: 0,
      blockedUsers: 0,
      events: 0,
      eventsCardPreview: 0,
      eventChats: 0,
      eventChatMessages: 0,
      eventApplications: 0,
      eventConversations: 0,
      eventNotifications: 0,
      eventPhotos: 0,
      feedItems: 0,
    };

    try {
      // 0. Deletar eventos criados pelo usuário + dados relacionados
      console.log("🗑️ [0/20] Deletando eventos criados pelo usuário...");
      const ownedEventsSnapshot = await db
        .collection("events")
        .where("createdBy", "==", userId)
        .get();

      console.log(
        `🗑️ [0/20] ${ownedEventsSnapshot.size} ` +
          "evento(s) encontrados para deletar"
      );

      for (const event of ownedEventsSnapshot.docs) {
        const eventId = event.id;
        console.log(`🗑️ [0/20] Deletando evento ${eventId}...`);
        const stats = await deleteOwnedEventAndRelatedData(eventId, userId);
        deletionStats.events += stats.events;
        deletionStats.eventChats += stats.eventChats;
        deletionStats.eventChatMessages += stats.eventChatMessages;
        deletionStats.eventApplications += stats.eventApplications;
        deletionStats.eventConversations += stats.eventConversations;
        deletionStats.eventNotifications += stats.eventNotifications;
      }

      // 0.5 Remover participações do usuário em eventos de terceiros
      console.log(
        "🗑️ [0.5/20] Removendo participações em eventos de terceiros..."
      );
      await removeUserFromOtherEvents(userId);

      // 0.6 Deletar chats 1x1 e mensagens de grupo do usuário
      // (arquitetura atual)
      console.log(
        "🗑️ [0.6/20] Deletando conversas e mensagens (1x1 + grupo)..."
      );
      const userConversationsSnap = await db
        .collection("Connections")
        .doc(userId)
        .collection("Conversations")
        .get();

      for (const convDoc of userConversationsSnap.docs) {
        const conversationId = convDoc.id;
        if (!conversationId) continue;

        // Chat de evento
        if (conversationId.startsWith("event_")) {
          const eventId = conversationId.replace("event_", "");
          if (eventId) {
            try {
              const deleted = await deleteEventChatMessagesBySender(
                eventId,
                userId
              );
              deletionStats.eventChatMessages += deleted;
            } catch (error) {
              console.warn(
                "🗑️ [DELETE_ACCOUNT] ⚠️ Falha ao deletar mensagens " +
                  "do EventChat:",
                eventId,
                error
              );
            }

            // Remover o usuário do EventChats participantIds/participants
            // (best-effort)
            try {
              await db
                .collection("EventChats")
                .doc(eventId)
                .set(
                  {
                    participantIds: admin.firestore.FieldValue.arrayRemove(
                      userId
                    ),
                    participants: admin.firestore.FieldValue.arrayRemove(
                      userId
                    ),
                  },
                  {merge: true}
                );
            } catch (error) {
              console.warn(
                "🗑️ [DELETE_ACCOUNT] ⚠️ Falha ao remover participante " +
                  "do EventChat:",
                eventId,
                error
              );
            }

            // Limpar também Messages/{userId}/event_{eventId}
            // (legacy)
            try {
              const legacyThread = db
                .collection("Messages")
                .doc(userId)
                .collection(`event_${eventId}`);
              deletionStats.chats += await deleteCollectionInBatches(
                `Messages/${userId}/event_${eventId}`,
                legacyThread
              );
            } catch (error) {
              console.warn(
                "🗑️ [DELETE_ACCOUNT] ⚠️ Falha ao limpar thread legacy " +
                  "do evento:",
                eventId,
                error
              );
            }
          }

          // Deletar a conversa do usuário
          try {
            await convDoc.ref.delete();
            deletionStats.eventConversations += 1;
          } catch (error) {
            console.warn(
              "🗑️ [DELETE_ACCOUNT] ⚠️ Falha ao deletar Conversation " +
                "do evento:",
              conversationId,
              error
            );
          }

          continue;
        }

        // Chat 1x1 (conversationId == otherUserId)
        const otherUserId = conversationId;
        const result = await deleteDirectChatPair(userId, otherUserId);
        deletionStats.chats += result.messages;
        deletionStats.connections += result.conversations;
      }

      // Limpar documento raiz (best-effort)
      try {
        await db.collection("Messages").doc(userId).delete();
      } catch (error) {
        console.warn(
          "🗑️ [DELETE_ACCOUNT] ⚠️ Falha ao deletar Messages/{userId}:",
          userId,
          error
        );
      }
      try {
        await db.collection("Connections").doc(userId).delete();
      } catch (error) {
        console.warn(
          "🗑️ [DELETE_ACCOUNT] ⚠️ Falha ao deletar Connections/{userId}:",
          userId,
          error
        );
      }

      // 1. Deletar sub-coleções do documento Users
      console.log("🗑️ [1/20] Deletando sub-coleções de Users...");
      const userRef = db.collection("Users").doc(userId);

      // Deletar applications sub-coleção
      const applicationsDeleted = await deleteSubcollection(
        userRef,
        "applications"
      );
      deletionStats.applications += applicationsDeleted;
      console.log(`✅ Deletadas ${applicationsDeleted} applications`);

      // 2. Deletar documento principal do usuário
      console.log("🗑️ [2/20] Deletando documento Users...");
      await userRef.delete();
      deletionStats.users = 1;
      console.log("✅ Documento Users deletado");

      // 3. Deletar reviews (como reviewer)
      console.log("🗑️ [3/20] Deletando reviews como reviewer...");
      const reviewsAsReviewer = await batchDelete(
        "Reviews",
        db.collection("Reviews").where("reviewer_id", "==", userId)
      );
      deletionStats.reviews += reviewsAsReviewer;
      console.log(`✅ Deletadas ${reviewsAsReviewer} reviews como reviewer`);

      // 4. Deletar reviews (como reviewed)
      console.log("🗑️ [4/20] Deletando reviews como reviewed...");
      const reviewsAsReviewed = await batchDelete(
        "Reviews",
        db.collection("Reviews").where("reviewee_id", "==", userId)
      );
      deletionStats.reviews += reviewsAsReviewed;
      console.log(`✅ Deletadas ${reviewsAsReviewed} reviews como reviewed`);

      // 5 e 6 eram do modelo legado (Connections com memberIds + Chats).
      // A limpeza na arquitetura atual é feita no passo 0.6.

      // 7. Deletar notificações
      console.log("🗑️ [7/20] Deletando Notifications...");
      const notificationsDeleted = await batchDelete(
        "Notifications",
        db.collection("Notifications").where("userId", "==", userId)
      );
      deletionStats.notifications = notificationsDeleted;
      console.log(`✅ Deletadas ${notificationsDeleted} notificações`);

      // 8. Deletar visitas ao perfil (feitas) - ProfileVisits
      console.log("🗑️ [8/20] Deletando ProfileVisits (feitas)...");
      const visitsAsVisitor = await batchDelete(
        "ProfileVisits",
        db.collection("ProfileVisits").where("visitorId", "==", userId)
      );
      deletionStats.profileVisits += visitsAsVisitor;
      console.log(`✅ Deletadas ${visitsAsVisitor} visitas feitas`);

      // 9. Deletar visitas ao perfil (recebidas) - ProfileVisits
      console.log("🗑️ [9/20] Deletando ProfileVisits (recebidas)...");
      const visitsAsVisited = await batchDelete(
        "ProfileVisits",
        db.collection("ProfileVisits").where("visitedUserId", "==", userId)
      );
      deletionStats.profileVisits += visitsAsVisited;
      console.log(`✅ Deletadas ${visitsAsVisited} visitas recebidas`);

      // 9.5. Deletar visualizações para notificações - ProfileViews
      console.log("🗑️ [9.5/20] Deletando ProfileViews (como viewer)...");
      const viewsAsViewer = await batchDelete(
        "ProfileViews",
        db.collection("ProfileViews").where("viewerId", "==", userId)
      );
      console.log(`✅ Deletadas ${viewsAsViewer} views como viewer`);

      console.log("🗑️ [9.6/20] Deletando ProfileViews (recebidas)...");
      const viewsReceived = await batchDelete(
        "ProfileViews",
        db.collection("ProfileViews").where("viewedUserId", "==", userId)
      );
      console.log(`✅ Deletadas ${viewsReceived} views recebidas`);

      // 10. Deletar ranking
      console.log("🗑️ [10/20] Deletando ranking...");
      const rankingDeleted = await batchDelete(
        "ranking",
        db.collection("ranking").where("userId", "==", userId)
      );
      deletionStats.ranking = rankingDeleted;
      console.log(`✅ Deletados ${rankingDeleted} registros de ranking`);

      // 11. Deletar localização do usuário
      console.log("🗑️ [11/20] Deletando UserLocations...");
      const locationRef = db.collection("UserLocations").doc(userId);
      await locationRef.delete();
      deletionStats.userLocations = 1;
      console.log("✅ UserLocation deletada");

      // 12. Deletar bloqueios (como bloqueador)
      console.log("🗑️ [12/20] Deletando blocked_users (como bloqueador)...");
      const blocksAsBlocker = await batchDelete(
        "blocked_users",
        db.collection("blocked_users").where("blockerId", "==", userId)
      );
      deletionStats.blockedUsers += blocksAsBlocker;
      console.log(`✅ Deletados ${blocksAsBlocker} bloqueios feitos`);

      // 13. Deletar bloqueios (como bloqueado)
      console.log("🗑️ [13/20] Deletando blocked_users (como bloqueado)...");
      const blocksAsBlocked = await batchDelete(
        "blocked_users",
        db.collection("blocked_users").where("blockedUserId", "==", userId)
      );
      deletionStats.blockedUsers += blocksAsBlocked;
      console.log(`✅ Deletados ${blocksAsBlocked} bloqueios recebidos`);

      // 14. Deletar users_preview (documento de preview do usuário)
      console.log("🗑️ [14/20] Deletando users_preview...");
      try {
        await db.collection("users_preview").doc(userId).delete();
        deletionStats.usersPreview = 1;
        console.log("✅ users_preview deletado");
      } catch (error) {
        console.warn(
          "🗑️ [DELETE_ACCOUNT] ⚠️ Falha ao deletar users_preview:",
          error
        );
      }

      // 15. Deletar userRanking (ranking de usuário)
      console.log("🗑️ [15/20] Deletando userRanking...");
      const userRankingDeleted = await batchDelete(
        "userRanking",
        db.collection("userRanking").where("userId", "==", userId)
      );
      deletionStats.userRanking = userRankingDeleted;
      console.log(`✅ Deletados ${userRankingDeleted} registros de userRanking`);

      // 16. Deletar locationRanking (ranking por localização)
      console.log("🗑️ [16/20] Deletando locationRanking...");
      const locationRankingDeleted = await batchDelete(
        "locationRanking",
        db.collection("locationRanking").where("userId", "==", userId)
      );
      deletionStats.locationRanking = locationRankingDeleted;
      console.log(
        `✅ Deletados ${locationRankingDeleted} registros de locationRanking`
      );

      // 17. Deletar events_card_preview (previews de eventos criados)
      console.log("🗑️ [17/20] Deletando events_card_preview...");
      const eventsCardPreviewDeleted = await batchDelete(
        "events_card_preview",
        db.collection("events_card_preview").where("createdBy", "==", userId)
      );
      deletionStats.eventsCardPreview = eventsCardPreviewDeleted;
      console.log(
        `✅ Deletados ${eventsCardPreviewDeleted} eventos em events_card_preview`
      );

      // 18. Deletar EventPhotos (fotos de evento postadas pelo usuário)
      console.log("🗑️ [18/20] Deletando EventPhotos...");
      const eventPhotosSnapshot = await db
        .collection("EventPhotos")
        .where("userId", "==", userId)
        .get();

      for (let i = 0; i < eventPhotosSnapshot.docs.length; i += BATCH_SIZE) {
        const batch = db.batch();
        const chunk = eventPhotosSnapshot.docs.slice(i, i + BATCH_SIZE);
        for (const doc of chunk) {
          // Deletar subcoleções (comments e likes)
          await deleteSubcollection(doc.ref, "comments");
          await deleteSubcollection(doc.ref, "likes");
          batch.delete(doc.ref);
        }
        await batch.commit();
        deletionStats.eventPhotos += chunk.length;
      }
      console.log(`✅ Deletadas ${deletionStats.eventPhotos} EventPhotos`);

      // 19. Deletar feeds do usuário (items recebidos por fanout)
      console.log("🗑️ [19/20] Deletando feeds (items recebidos)...");
      const feedItemsDeleted = await deleteSubcollection(
        db.collection("feeds").doc(userId),
        "items"
      );
      deletionStats.feedItems = feedItemsDeleted;
      console.log(`✅ Deletados ${feedItemsDeleted} feed items`);

      // Deletar documento raiz de feeds
      try {
        await db.collection("feeds").doc(userId).delete();
        console.log("✅ Documento feeds/{userId} deletado");
      } catch (error) {
        console.warn(
          "🗑️ [DELETE_ACCOUNT] ⚠️ Falha ao deletar feeds/{userId}:",
          error
        );
      }

      // 20. Limpar fanout de itens do usuário nos feeds de seguidores
      // (removendo EventPhotos e ActivityFeed items criados por este usuário)
      console.log("🗑️ [20/20] Limpando fanout items em feeds de seguidores...");
      try {
        // Buscar todos os seguidores para limpar seus feeds
        const followersSnapshot = await db
          .collection("Users")
          .doc(userId)
          .collection("followers")
          .get();

        let fanoutItemsRemoved = 0;
        for (const followerDoc of followersSnapshot.docs) {
          const followerId = followerDoc.id;
          // Buscar items do feed do seguidor criados por este usuário
          const followerFeedItems = await db
            .collection("feeds")
            .doc(followerId)
            .collection("items")
            .where("authorId", "==", userId)
            .get();

          if (!followerFeedItems.empty) {
            for (
              let i = 0;
              i < followerFeedItems.docs.length;
              i += BATCH_SIZE
            ) {
              const batch = db.batch();
              const chunk = followerFeedItems.docs.slice(i, i + BATCH_SIZE);
              chunk.forEach((doc) => batch.delete(doc.ref));
              await batch.commit();
              fanoutItemsRemoved += chunk.length;
            }
          }
        }
        console.log(
          `✅ Removidos ${fanoutItemsRemoved} fanout items dos feeds de seguidores`
        );
      } catch (error) {
        console.warn(
          "🗑️ [DELETE_ACCOUNT] ⚠️ Falha ao limpar fanout items:",
          error
        );
      }

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
