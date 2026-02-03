import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const BATCH_SIZE = 500;

/**
 * Deleta notificações relacionadas a um evento.
 * Busca por `eventId` no campo direto e também em
 * `n_params.eventId` e `n_related_id`.
 * @param {string} eventId ID do evento
 * @param {FirebaseFirestore.Firestore} firestore Instância do Firestore
 * @return {Promise<number>} quantidade de notificações deletadas
 */
export async function deleteEventNotifications(
  eventId: string,
  firestore: FirebaseFirestore.Firestore
): Promise<number> {
  let totalDeleted = 0;

  console.log("🔔 [deleteEventNotifications] Starting for eventId: " + eventId);

  try {
    // Buscar por múltiplos campos que podem referenciar o evento
    console.log("🔍 [deleteEventNotifications] Querying Notifications...");

    const [directQuery, paramsQuery, relatedQuery] = await Promise.all([
      firestore
        .collection("Notifications")
        .where("eventId", "==", eventId)
        .get(),
      firestore
        .collection("Notifications")
        .where("n_params.activityId", "==", eventId)
        .get(),
      firestore
        .collection("Notifications")
        .where("n_related_id", "==", eventId)
        .get(),
    ]);

    console.log(
      "📊 [deleteEventNotifications] Query results: " +
      "directQuery=" + directQuery.size + ", " +
      "paramsQuery=" + paramsQuery.size + ", " +
      "relatedQuery=" + relatedQuery.size
    );

    // Combinar resultados únicos (evitar duplicatas)
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

    relatedQuery.docs.forEach((doc) => {
      docsToDelete.set(doc.id, doc.ref);
    });

    console.log(
      `📋 [deleteEventNotifications] Unique docs to delete: ${docsToDelete.size}`
    );

    if (docsToDelete.size === 0) {
      console.log(`📭 No notifications found for event ${eventId}`);
      return 0;
    }

    // Deletar em batch (máximo 500 por batch)
    const refs = Array.from(docsToDelete.values());

    for (let i = 0; i < refs.length; i += BATCH_SIZE) {
      const batchRefs = refs.slice(i, i + BATCH_SIZE);
      const batch = firestore.batch();
      batchRefs.forEach((ref) => batch.delete(ref));
      await batch.commit();
      console.log(
        `✅ [deleteEventNotifications] Batch deleted: ${batchRefs.length} docs`
      );
    }

    totalDeleted = refs.length;
    console.log(
      `🗑️ Deleted ${totalDeleted} notifications for event ${eventId}`
    );
  } catch (error) {
    console.error(
      `❌ Error deleting notifications for event ${eventId}:`,
      error
    );
  }

  return totalDeleted;
}

/**
 * Cloud Function para deletar um evento e todos os seus dados relacionados
 *
 * Operações realizadas:
 * 1. Valida que o usuário é o criador do evento
 * 2. Remove documento em 'events'
 * 3. Remove chat em 'EventChats' e todas as mensagens
 * 4. Remove todas as aplicações em 'EventApplications'
 * 5. Remove conversas relacionadas de todos os participantes
 * 6. Remove arquivos do Storage
 * 7. Remove todas as notificações relacionadas ao evento
 *
 * @param eventId - ID do evento a ser deletado
 * @returns {success: boolean, message: string}
 */
export const deleteEvent = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    console.log("🚀 [deleteEvent] Function started");
    console.log("📥 [deleteEvent] Data received:", JSON.stringify(data));

    // Verifica autenticação
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated to delete an event"
      );
    }

    const {eventId} = data;
    const userId = context.auth.uid;

    console.log(`📋 [deleteEvent] eventId: ${eventId}, userId: ${userId}`);

    if (!eventId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "eventId is required"
      );
    }

    const firestore = admin.firestore();
    const storage = admin.storage();

    try {
      // 1. Verifica se o evento existe e se o usuário é o criador
      const eventDoc = await firestore.collection("events").doc(eventId).get();

      if (!eventDoc.exists) {
        throw new functions.https.HttpsError(
          "not-found",
          "Event not found"
        );
      }

      const eventData = eventDoc.data();
      const createdBy = eventData?.createdBy;

      if (createdBy !== userId) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Only the event creator can delete this event"
        );
      }

      console.log(
        `🗑️ Starting deletion for event ${eventId} by user ${userId}`
      );

      // 2. Busca todas as aplicações para saber quais conversas ocultar
      const applicationsSnapshot = await firestore
        .collection("EventApplications")
        .where("eventId", "==", eventId)
        .get();

      const participantIds = new Set<string>();
      participantIds.add(userId);

      applicationsSnapshot.docs.forEach((doc) => {
        const appUserId = doc.data().userId;
        if (appUserId) {
          participantIds.add(appUserId);
        }
      });

      console.log(`👥 Found ${participantIds.size} participants to hide`);

      // 3. Soft-delete no evento e chat principal
      const now = admin.firestore.FieldValue.serverTimestamp();
      await firestore.collection("events").doc(eventId).set(
        {
          isActive: false,
          isDeleted: true,
          deletedAt: now,
          deletedBy: userId,
        },
        {merge: true}
      );

      await firestore.collection("EventChats").doc(eventId).set(
        {
          isDeleted: true,
          deletedAt: now,
        },
        {merge: true}
      );

      // 4. Oculta conversas dos participantes (soft-delete local)
      const eventUserId = `event_${eventId}`;
      const batches: FirebaseFirestore.WriteBatch[] = [];
      let currentBatch = firestore.batch();
      let operationCount = 0;
      const MAX_BATCH_SIZE = 450;

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

      for (const participantId of participantIds) {
        const conversationRef = firestore
          .collection("Connections")
          .doc(participantId)
          .collection("Conversations")
          .doc(eventUserId);

        addToBatch((batch) =>
          batch.set(
            conversationRef,
            {
              hidden: true,
              eventDeleted: true,
              deletedAt: now,
            },
            {merge: true}
          )
        );
      }

      if (operationCount > 0) {
        batches.push(currentBatch);
      }

      console.log(`📦 Executing ${batches.length} batch(es) to hide chats...`);
      await Promise.all(batches.map((batch) => batch.commit()));

      // 5. Enfileira cleanup assíncrono
      await enqueueEventDeletionJob(eventId, userId, firestore);

      // 6. Remove arquivos do Storage (async, não aguarda conclusão)
      deleteEventStorage(eventId, eventData, storage)
        .then(() =>
          console.log(`🗑️ Storage cleanup completed for event ${eventId}`)
        )
        .catch((err) =>
          console.error(`⚠️ Storage cleanup failed: ${err.message}`)
        );

      console.log(`✅ Event ${eventId} marked as deleted and queued for cleanup`);

      return {
        success: true,
        message: "Event deletion scheduled",
      };
    } catch (error: unknown) {
      const err = error as Error;
      console.error(`❌ Error deleting event ${eventId}:`, err);

      // Se for um HttpsError, propaga
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }

      // Caso contrário, encapsula em um HttpsError
      throw new functions.https.HttpsError(
        "internal",
        `Failed to delete event: ${err.message}`
      );
    }
  });

async function enqueueEventDeletionJob(
  eventId: string,
  userId: string,
  firestore: admin.firestore.Firestore
): Promise<void> {
  const jobRef = firestore.collection("eventdeletions").doc(eventId);
  const now = admin.firestore.FieldValue.serverTimestamp();

  await firestore.runTransaction(async (transaction) => {
    const jobSnap = await transaction.get(jobRef);

    if (!jobSnap.exists) {
      transaction.set(jobRef, {
        eventId,
        createdBy: userId,
        status: "pending",
        phase: "messages",
        createdAt: now,
        updatedAt: now,
        messageCursor: null,
        applicationCursor: null,
        notificationPhase: "eventId",
        notificationCursor: null,
        feedCursor: null,
        stats: {
          messages: 0,
          applications: 0,
          conversations: 0,
          notifications: 0,
          feedItems: 0,
        },
      });
      return;
    }

    const currentData = jobSnap.data() || {};
    const currentStatus = String(currentData.status || "");
    if (currentStatus === "completed") {
      return;
    }

    transaction.update(jobRef, {
      status: "pending",
      updatedAt: now,
    });
  });
}

/**
 * Remove arquivos do Storage relacionados ao evento
 * @param {string} eventId - ID do evento
 * @param {Record<string, unknown>} eventData - Dados do evento
 * @param {admin.storage.Storage} storage - Firebase Storage instance
 * @return {Promise<void>}
 */
async function deleteEventStorage(
  eventId: string,
  eventData: Record<string, unknown> | null | undefined,
  storage: admin.storage.Storage
): Promise<void> {
  const bucket = storage.bucket();

  try {
    // Lista de possíveis caminhos
    const paths = [
      `events/${eventId}`,
      `event_images/${eventId}`,
      `event_media/${eventId}`,
    ];

    // Deleta cada caminho
    for (const path of paths) {
      try {
        await bucket.deleteFiles({
          prefix: path,
        });
        console.log(`🗑️ Deleted files at ${path}`);
      } catch (err: unknown) {
        const error = err as Error;
        console.warn(`⚠️ Could not delete ${path}: ${error.message}`);
      }
    }

    // Deleta cover photo se existir
    if (eventData?.coverPhoto && typeof eventData.coverPhoto === "string") {
      try {
        const url = eventData.coverPhoto;
        if (url.includes("firebase")) {
          // Extrai o caminho do arquivo da URL
          const pathMatch = url.match(/\/o\/(.+?)\?/);
          if (pathMatch) {
            const filePath = decodeURIComponent(pathMatch[1]);
            await bucket.file(filePath).delete();
            console.log(`🗑️ Deleted cover photo: ${filePath}`);
          }
        }
      } catch (err: unknown) {
        const error = err as Error;
        console.warn(`⚠️ Could not delete cover photo: ${error.message}`);
      }
    }

    // Deleta fotos da galeria se existirem
    if (eventData && Array.isArray(eventData.photos)) {
      for (const photoUrl of eventData.photos) {
        if (typeof photoUrl === "string" && photoUrl.includes("firebase")) {
          try {
            const pathMatch = photoUrl.match(/\/o\/(.+?)\?/);
            if (pathMatch) {
              const filePath = decodeURIComponent(pathMatch[1]);
              await bucket.file(filePath).delete();
              console.log(`🗑️ Deleted gallery photo: ${filePath}`);
            }
          } catch (err: unknown) {
            const error = err as Error;
            console.warn(`⚠️ Could not delete gallery photo: ${error.message}`);
          }
        }
      }
    }

    console.log("✅ Storage cleanup completed");
  } catch (error: unknown) {
    const err = error as Error;
    console.error("❌ Storage cleanup error:", err.message);
    throw error;
  }
}
