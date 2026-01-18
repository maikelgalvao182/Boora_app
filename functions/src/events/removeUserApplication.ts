import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * FIRESTORE COLLECTION NAMING CONVENTION
 *
 * This project currently uses a mix of casing styles:
 * - camelCase: 'events'
 * - PascalCase: 'EventChats', 'EventApplications', 'Connections',
 *   'Conversations'
 *
 * Please maintain this consistency when adding new references until a full
 * migration is performed.
 */

const BATCH_SIZE = 500;

/**
 * Deleta mensagens de um usuário específico no chat do evento
 *
 * @param {admin.firestore.Firestore} firestore - Firestore instance
 * @param {string} eventId - ID do evento
 * @param {string} userId - ID do usuário cujas mensagens serão deletadas
 * @return {Promise<number>} Quantidade de mensagens deletadas
 */
async function deleteUserMessagesFromEventChat(
  firestore: admin.firestore.Firestore,
  eventId: string,
  userId: string
): Promise<number> {
  const messagesRef = firestore
    .collection("EventChats")
    .doc(eventId)
    .collection("Messages")
    .where("sender_id", "==", userId);

  let totalDeleted = 0;
  let snapshot = await messagesRef.limit(BATCH_SIZE).get();

  while (!snapshot.empty) {
    const batch = firestore.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    totalDeleted += snapshot.docs.length;

    // Busca próximo lote
    snapshot = await messagesRef.limit(BATCH_SIZE).get();
  }

  if (totalDeleted > 0) {
    console.log(
      `🗑️ Deleted ${totalDeleted} messages from user ` +
      `${userId} in event ${eventId}`
    );
  }

  return totalDeleted;
}

/**
 * Helper function to execute the batch removal logic.
 * Handles:
 * 1. Application deletion (if doc provided)
 * 2. EventChat update (safe decrement)
 * 3. Conversation deletion
 * 4. User messages deletion from event chat
 *
 * @param {admin.firestore.Firestore} firestore - Firestore instance
 * @param {string} eventId - ID of the event
 * @param {string} userId - ID of the user
 * @param {admin.firestore.QueryDocumentSnapshot} [applicationDoc] - Optional
 * application document to delete
 */
async function executeRemovalBatch(
  firestore: admin.firestore.Firestore,
  eventId: string,
  userId: string,
  applicationDoc?: admin.firestore.QueryDocumentSnapshot
) {
  const batch = firestore.batch();

  // 1. Remove application if it exists
  if (applicationDoc) {
    batch.delete(applicationDoc.ref);
  }

  // 2. Update EventChat
  const eventChatRef = firestore.collection("EventChats").doc(eventId);

  // Fetch EventChat to ensure safe decrement
  const eventChatDoc = await eventChatRef.get();

  if (!eventChatDoc.exists) {
    console.warn(
      `⚠️ EventChat not found for event ${eventId}, skipping chat cleanup`
    );
  } else {
    const eventChatData = eventChatDoc.data();
    const participants = eventChatData?.participants || [];
    const currentCount = eventChatData?.participantCount || 0;

    if (participants.includes(userId)) {
      const newCount = Math.max(0, currentCount - 1);
      batch.update(eventChatRef, {
        participants: admin.firestore.FieldValue.arrayRemove(userId),
        participantCount: newCount,
      });
    } else {
      console.log(
        "⚠️ User not in participants list, skipping EventChat update."
      );
    }
  }

  // 3. Remove conversation
  const eventUserId = `event_${eventId}`;
  const conversationRef = firestore
    .collection("Connections")
    .doc(userId)
    .collection("Conversations")
    .doc(eventUserId);
  batch.delete(conversationRef);

  await batch.commit();

  // 4. Delete all user messages from event chat (outside batch for large sets)
  await deleteUserMessagesFromEventChat(firestore, eventId, userId);
}

/**
 * Cloud Function para remover a aplicação de um usuário em um evento
 *
 * Operações realizadas:
 * 1. Valida que existe uma aplicação do usuário para o evento
 * 2. Remove registro em 'EventApplications'
 * 3. Remove usuário do array 'participants' em 'EventChats'
 * 4. Decrementa 'participantCount' no chat
 * 5. Remove conversa do evento do usuário
 *
 * @param eventId - ID do evento
 * @param userId - ID do usuário (opcional, se não fornecido usa o auth.uid)
 * @returns {success: boolean, message: string}
 */
export const removeUserApplication = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    // Verifica autenticação
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const {eventId, userId: targetUserId} = data;
    const currentUserId = context.auth.uid;

    // Se userId não for fornecido, usa o próprio usuário
    const userId = targetUserId || currentUserId;

    if (!eventId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "eventId is required"
      );
    }

    const firestore = admin.firestore();

    try {
      // Se estiver removendo outro usuário, verifica se é o criador do evento
      if (userId !== currentUserId) {
        const eventDoc = await firestore
          .collection("events")
          .doc(eventId)
          .get();

        if (!eventDoc.exists) {
          throw new functions.https.HttpsError(
            "not-found",
            "Event not found"
          );
        }

        const createdBy = eventDoc.data()?.createdBy;

        if (createdBy !== currentUserId) {
          throw new functions.https.HttpsError(
            "permission-denied",
            "Only the event creator can remove other participants"
          );
        }
      }

      console.log(`🚪 Removing application: event=${eventId}, user=${userId}`);

      // Busca a aplicação do usuário
      const applicationSnapshot = await firestore
        .collection("EventApplications")
        .where("eventId", "==", eventId)
        .where("userId", "==", userId)
        .limit(1)
        .get();

      if (applicationSnapshot.empty) {
        // Se não encontrou aplicação, verifica se o usuário está no chat
        // Isso permite corrigir inconsistências onde o usuário está no chat
        // mas sem aplicação
        const eventChatDoc = await firestore
          .collection("EventChats")
          .doc(eventId)
          .get();
        const participants = eventChatDoc.data()?.participants || [];

        if (participants.includes(userId)) {
          console.log(
            "⚠️ Application not found, but user is in EventChat. " +
            "Removing from chat only."
          );

          await executeRemovalBatch(firestore, eventId, userId);

          return {
            success: true,
            message: "User removed from chat (application was missing)",
          };
        }

        throw new functions.https.HttpsError(
          "not-found",
          "Application not found"
        );
      }

      const applicationDoc = applicationSnapshot.docs[0];

      await executeRemovalBatch(firestore, eventId, userId, applicationDoc);

      console.log(`✅ Application removed: event=${eventId}, user=${userId}`);

      return {
        success: true,
        message: "Application removed successfully",
      };
    } catch (error: unknown) {
      console.error("❌ Error removing application:", error);

      if (error instanceof functions.https.HttpsError) {
        throw error;
      }

      const err = error as Error;
      throw new functions.https.HttpsError(
        "internal",
        `Failed to remove application: ${err.message}`
      );
    }
  });

/**
 * Cloud Function para remover um participante específico (apenas criador)
 *
 * Esta é uma versão alternativa que permite ao criador remover
 * qualquer participante
 */
export const removeParticipant = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    // Verifica autenticação
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const {eventId, userId} = data;
    const currentUserId = context.auth.uid;

    if (!eventId || !userId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "eventId and userId are required"
      );
    }

    const firestore = admin.firestore();

    try {
      // Verifica se é o criador do evento
      const eventDoc = await firestore.collection("events").doc(eventId).get();

      if (!eventDoc.exists) {
        throw new functions.https.HttpsError(
          "not-found",
          "Event not found"
        );
      }

      const createdBy = eventDoc.data()?.createdBy;

      if (createdBy !== currentUserId) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Only the event creator can remove participants"
        );
      }

      // Não permite remover o próprio criador
      if (userId === currentUserId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Event creator cannot remove themselves"
        );
      }

      console.log(
        "👤 Removing participant: " +
          `event=${eventId}, user=${userId}, by=${currentUserId}`
      );

      // Busca a aplicação do usuário
      const applicationSnapshot = await firestore
        .collection("EventApplications")
        .where("eventId", "==", eventId)
        .where("userId", "==", userId)
        .limit(1)
        .get();

      if (applicationSnapshot.empty) {
        throw new functions.https.HttpsError(
          "not-found",
          "Participant application not found"
        );
      }

      const applicationDoc = applicationSnapshot.docs[0];

      await executeRemovalBatch(firestore, eventId, userId, applicationDoc);

      console.log(`✅ Participant removed: event=${eventId}, user=${userId}`);

      return {
        success: true,
        message: "Participant removed successfully",
      };
    } catch (error: unknown) {
      console.error("❌ Error removing participant:", error);

      if (error instanceof functions.https.HttpsError) {
        throw error;
      }

      const err = error as Error;
      throw new functions.https.HttpsError(
        "internal",
        `Failed to remove participant: ${err.message}`
      );
    }
  });
