import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Cloud Function que roda todo dia às 6h da manhã verificando eventos
 * que terminaram há 24 horas para criar PendingReviews
 */
export const checkEventsForReview = functions.pubsub
  .schedule("0 6 * * *")
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    console.log("🔍 [checkEventsForReview] Starting...");

    const now = admin.firestore.Timestamp.now();
    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

    try {
      // Busca eventos que terminaram há 24h e ainda não criaram reviews
      const eventsSnapshot = await admin
        .firestore()
        .collection("Events")
        .where("schedule.date", "<=", twentyFourHoursAgo)
        .where("reviewsCreated", "==", false)
        .limit(50)
        .get();

      const foundMsg = `Found ${eventsSnapshot.size} events to process`;
      console.log(`📊 [checkEventsForReview] ${foundMsg}`);

      if (eventsSnapshot.empty) {
        console.log("✅ [checkEventsForReview] No events to process");
        return null;
      }

      // Processa cada evento
      let successCount = 0;
      let errorCount = 0;

      for (const eventDoc of eventsSnapshot.docs) {
        try {
          await createPendingReviewsForEvent(eventDoc);

          // Marca evento como processado
          await eventDoc.ref.update({
            reviewsCreated: true,
            reviewsCreatedAt: now,
          });

          successCount++;
          console.log(
            `✅ [checkEventsForReview] Reviews created for event ${eventDoc.id}`
          );
        } catch (error) {
          errorCount++;
          console.error(
            `❌ [checkEventsForReview] Error processing event ${eventDoc.id}:`,
            error
          );
        }
      }

      const completeMsg =
        `Completed - Success: ${successCount}, Errors: ${errorCount}`;
      console.log(`🎯 [checkEventsForReview] ${completeMsg}`);

      return null;
    } catch (error) {
      console.error("❌ [checkEventsForReview] Fatal error:", error);
      throw error;
    }
  });

/**
 * Cria PendingReviews para um evento
 * Owner avalia cada participante E cada participante avalia o owner
 * @param {admin.firestore.DocumentSnapshot} eventDoc - Event document
 */
async function createPendingReviewsForEvent(
  eventDoc: admin.firestore.DocumentSnapshot
): Promise<void> {
  const eventData = eventDoc.data();
  if (!eventData) {
    console.log(`⚠️ [createPendingReviews] Event ${eventDoc.id} has no data`);
    return;
  }

  const eventId = eventDoc.id;
  const ownerId = eventData.createdBy;
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 dias

  console.log(`📝 [createPendingReviews] Processing event: ${eventId}`);
  console.log(`   Owner: ${ownerId}`);
  console.log(`   Title: ${eventData.activityText || eventData.title}`);

  // Busca participantes aprovados
  const applicationsSnapshot = await admin
    .firestore()
    .collection("EventApplications")
    .where("eventId", "==", eventId)
    .where("status", "in", ["approved", "autoApproved"])
    .get();

  const totalApps = applicationsSnapshot.size;
  console.log(`   Total applications: ${totalApps}`);

  // Filtra apenas quem confirmou presença ("Eu vou" ou "Vou")
  const confirmedParticipants = applicationsSnapshot.docs.filter((doc) => {
    const presence = doc.data().presence;
    return presence === "Eu vou" || presence === "Vou";
  });

  const confirmed = confirmedParticipants.length;
  console.log(`   Confirmed participants: ${confirmed}`);

  if (confirmedParticipants.length === 0) {
    const msg = `No confirmed participants for event ${eventId}`;
    console.log(`⚠️ [createPendingReviews] ${msg}`);
    return;
  }

  // Busca dados do owner
  const ownerDoc = await admin
    .firestore()
    .collection("Users")
    .doc(ownerId)
    .get();
  const ownerData = ownerDoc.data();

  // Prepara batch para criação em lote
  const batch = admin.firestore().batch();
  let batchCount = 0;
  const batches: admin.firestore.WriteBatch[] = [batch];

  // Para cada participante confirmado
  for (const participantApp of confirmedParticipants) {
    const participantId = participantApp.data().userId;

    // Busca dados do participante
    const participantDoc = await admin
      .firestore()
      .collection("Users")
      .doc(participantId)
      .get();
    const participantData = participantDoc.data();

    // 1. Owner avalia Participante
    const ownerReviewRef = admin.firestore().collection("PendingReviews").doc();

    batches[batches.length - 1].set(ownerReviewRef, {
      pending_review_id: ownerReviewRef.id,
      event_id: eventId,
      application_id: participantApp.id,
      reviewer_id: ownerId,
      reviewee_id: participantId,
      reviewer_role: "owner",
      event_title: eventData.activityText || eventData.title || "Evento",
      event_emoji: eventData.emoji || "🎉",
      event_location:
        eventData.locationName ||
        eventData.location?.locationName ||
        null,
      event_date: eventData.schedule?.date || eventData.scheduleDate || null,
      created_at: admin.firestore.Timestamp.now(),
      expires_at: admin.firestore.Timestamp.fromDate(expiresAt),
      dismissed: false,
      reviewee_name: participantData?.user_fullname || "Usuário",
      reviewee_photo_url: participantData?.user_photo_link || null,
    });

    batchCount++;

    // 2. Participante avalia Owner
    const participantReviewRef = admin
      .firestore()
      .collection("PendingReviews")
      .doc();

    batches[batches.length - 1].set(participantReviewRef, {
      pending_review_id: participantReviewRef.id,
      event_id: eventId,
      application_id: participantApp.id,
      reviewer_id: participantId,
      reviewee_id: ownerId,
      reviewer_role: "participant",
      event_title: eventData.activityText || eventData.title || "Evento",
      event_emoji: eventData.emoji || "🎉",
      event_location:
        eventData.locationName ||
        eventData.location?.locationName ||
        null,
      event_date: eventData.schedule?.date || eventData.scheduleDate || null,
      created_at: admin.firestore.Timestamp.now(),
      expires_at: admin.firestore.Timestamp.fromDate(expiresAt),
      dismissed: false,
      reviewee_name: ownerData?.user_fullname || "Usuário",
      reviewee_photo_url: ownerData?.user_photo_link || null,
    });

    batchCount++;

    // Firestore batch limit é 500 operações
    if (batchCount >= 450) {
      batches.push(admin.firestore().batch());
      batchCount = 0;
    }
  }

  // Commit todos os batches
  console.log(`   Committing ${batches.length} batch(es)...`);
  for (const b of batches) {
    await b.commit();
  }

  const totalReviews = confirmedParticipants.length * 2;
  const successMsg = `Created ${totalReviews} pending reviews`;
  console.log(`✅ [createPendingReviews] ${successMsg} for event ${eventId}`);

  // Envia notificações (não bloqueia)
  sendReviewNotifications(ownerId, confirmedParticipants, eventData).catch(
    (err) => {
      console.error(
        "⚠️ [createPendingReviews] Error sending notifications:",
        err
      );
    }
  );
}

/**
 * Envia notificações para owner e participantes
 * @param {string} ownerId - Owner user ID
 * @param {admin.firestore.QueryDocumentSnapshot[]} participants - Participants
 * @param {admin.firestore.DocumentData} eventData - Event data
 */
async function sendReviewNotifications(
  ownerId: string,
  participants: admin.firestore.QueryDocumentSnapshot[],
  eventData: admin.firestore.DocumentData
): Promise<void> {
  console.log("📬 [sendNotifications] Sending notifications...");

  const batch = admin.firestore().batch();

  // Notificação para owner
  const ownerNotifRef = admin.firestore().collection("Notifications").doc();
  batch.set(ownerNotifRef, {
    userId: ownerId,
    type: "review_request",
    title: "⭐ Hora de avaliar!",
    message: `Avalie os participantes do evento "${
      eventData.activityText || eventData.title
    }"`,
    data: {
      eventId: eventData.id,
      actionType: "open_pending_reviews",
    },
    createdAt: admin.firestore.Timestamp.now(),
    read: false,
  });

  // Notificações para participantes
  for (const participantApp of participants) {
    const participantId = participantApp.data().userId;
    const participantNotifRef = admin
      .firestore()
      .collection("Notifications")
      .doc();

    batch.set(participantNotifRef, {
      userId: participantId,
      type: "review_request",
      title: "⭐ Avalie o evento!",
      message: `Como foi o evento "${
        eventData.activityText || eventData.title
      }"? Deixe sua avaliação!`,
      data: {
        eventId: eventData.id,
        actionType: "open_pending_reviews",
      },
      createdAt: admin.firestore.Timestamp.now(),
      read: false,
    });
  }

  await batch.commit();
  console.log("✅ [sendNotifications] Notifications sent successfully");
}
