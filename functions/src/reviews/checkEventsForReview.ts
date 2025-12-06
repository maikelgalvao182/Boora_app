import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Cloud Function que roda a cada 5 minutos verificando eventos
 * que terminaram há 24 horas para criar PendingReviews
 *
 * CORREÇÃO: Query simplificada para evitar problemas de índice
 */
export const checkEventsForReview = functions.pubsub
  .schedule("*/5 * * * *")
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    console.log("🔍 [checkEventsForReview] Starting...");
    const currentTime = new Date().toISOString();
    console.log(`🔍 [checkEventsForReview] Current time: ${currentTime}`);

    const now = admin.firestore.Timestamp.now();
    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

    const beforeTime = twentyFourHoursAgo.toISOString();
    console.log(
      `🔍 [checkEventsForReview] Looking for events before: ${beforeTime}`
    );

    try {
      // Busca TODOS os eventos recentes
      // (sem filtrar por reviewsCreated na query)
      // Isso evita problemas com índice composto
      console.log(
        "🔍 [checkEventsForReview] Querying Events collection..."
      );

      // TESTE 1: Verifica se a coleção existe
      const collectionRef = admin.firestore().collection("events");
      console.log(
        "🔍 [checkEventsForReview] Collection path:",
        collectionRef.path
      );

      // TESTE 2: Tenta buscar SEM orderBy primeiro
      const testSnapshot = await collectionRef.limit(5).get();
      const testMsg =
        `Test query (no orderBy): ${testSnapshot.size} docs found`;
      console.log(`🔍 [checkEventsForReview] ${testMsg}`);

      if (!testSnapshot.empty) {
        console.log("🔍 [checkEventsForReview] Sample event structure:");
        const sampleDoc = testSnapshot.docs[0];
        const sampleData = sampleDoc.data();
        console.log(`   - id: ${sampleDoc.id}`);
        console.log(`   - has schedule: ${!!sampleData.schedule}`);
        const dateType = typeof sampleData.schedule?.date;
        console.log(`   - schedule.date type: ${dateType}`);
        console.log(`   - schedule.date value: ${sampleData.schedule?.date}`);
        const fields = Object.keys(sampleData).join(", ");
        console.log(`   - all fields: ${fields}`);
      }

      // TESTE 3: Agora tenta com orderBy
      console.log(
        "🔍 [checkEventsForReview] Trying query with orderBy..."
      );
      const eventsSnapshot = await admin
        .firestore()
        .collection("events")
        .orderBy("schedule.date", "desc")
        .limit(200)
        .get();

      console.log(
        `📊 [checkEventsForReview] Total events: ${eventsSnapshot.size}`
      );

      if (eventsSnapshot.empty) {
        console.log(
          "⚠️ [checkEventsForReview] No events found in collection"
        );
        console.log(
          "⚠️ [checkEventsForReview] Checking if Events collection exists..."
        );

        // Tenta buscar pelo menos 1 documento
        const testSnapshot2 = await admin
          .firestore()
          .collection("events")
          .limit(1)
          .get();

        if (testSnapshot2.empty) {
          const emptyMsg =
            "Events collection is empty or doesn't exist";
          console.log(`❌ [checkEventsForReview] ${emptyMsg}`);
        } else {
          const existMsg = "Events exist but none match the query";
          console.log(`⚠️ [checkEventsForReview] ${existMsg}`);
        }
        return null;
      }

      const firstDate =
        eventsSnapshot.docs[0]?.data()?.schedule?.date?.toDate?.()
          ?.toISOString() || "N/A";
      console.log(
        `🔍 [checkEventsForReview] First event date: ${firstDate}`
      );

      const lastIndex = eventsSnapshot.size - 1;
      const lastDate =
        eventsSnapshot.docs[lastIndex]?.data()?.schedule?.date?.toDate?.()
          ?.toISOString() || "N/A";
      console.log(`🔍 [checkEventsForReview] Last event date: ${lastDate}`);

      // Filtra eventos que:
      // 1. Terminaram há mais de 24 horas
      // 2. Ainda não criaram reviews
      console.log("🔍 [checkEventsForReview] Filtering events...");
      const eventsToProcess = eventsSnapshot.docs.filter((doc) => {
        const data = doc.data();

        // Debug: Mostra dados de cada evento
        console.log(`📄 [checkEventsForReview] Event ${doc.id}:`);
        console.log(`   - reviewsCreated: ${data.reviewsCreated}`);
        const scheduleDate =
          data.schedule?.date?.toDate?.()?.toISOString() || "N/A";
        console.log(`   - schedule.date: ${scheduleDate}`);

        // Verifica se já criou reviews
        if (data.reviewsCreated === true) {
          console.log("   ⏭️ Skipping - reviews already created");
          return false;
        }

        // Verifica se o evento terminou há mais de 24h
        const scheduleTimestamp = data.schedule?.date;
        if (!scheduleTimestamp) {
          console.log(
            `⚠️ [checkEventsForReview] Event ${doc.id} has no date`
          );
          return false;
        }

        // Converte Timestamp para Date
        const eventDate = scheduleTimestamp.toDate ?
          scheduleTimestamp.toDate() :
          new Date(scheduleTimestamp);
        const isOldEnough = eventDate <= twentyFourHoursAgo;

        if (isOldEnough) {
          const hoursAgo = Math.round(
            (Date.now() - eventDate.getTime()) / (1000 * 60 * 60)
          );
          console.log(
            `✅ Event ${doc.id} qualifies - ended ${hoursAgo}h ago`
          );
        } else {
          const hoursUntilReview = Math.round(
            (eventDate.getTime() - twentyFourHoursAgo.getTime()) /
            (1000 * 60 * 60)
          );
          const skipMsg =
            `too recent (needs ${hoursUntilReview}h more)`;
          console.log(`   ⏭️ Skipping - ${skipMsg}`);
        }

        return isOldEnough;
      });

      const foundMsg = `Found ${eventsToProcess.length} events ` +
        `(from ${eventsSnapshot.size} total)`;
      console.log(`📊 [checkEventsForReview] ${foundMsg}`);

      if (eventsToProcess.length === 0) {
        console.log(
          "✅ [checkEventsForReview] No events need review creation"
        );
        return null;
      }

      // Processa cada evento
      let successCount = 0;
      let errorCount = 0;

      for (const eventDoc of eventsToProcess) {
        try {
          console.log(
            `\n🎯 [checkEventsForReview] Processing event: ${eventDoc.id}`
          );

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
    console.log(
      "⚠️ [createPendingReviews] No confirmed participants " +
      `for event ${eventId}`
    );
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
      reviewee_name: participantData?.fullname || "Usuário",
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
      reviewee_name: ownerData?.fullname || "Usuário",
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
  console.log("📬 [sendNotifications] Sending notifications... (v2)");

  const batch = admin.firestore().batch();

  // Notificação para owner
  const ownerNotifRef = admin.firestore().collection("Notifications").doc();
  batch.set(ownerNotifRef, {
    userId: ownerId,
    n_type: "review_request",
    n_params: {
      eventId: eventData.id,
      actionType: "open_pending_reviews",
      title: "⭐ Hora de avaliar!",
      message: `Avalie os participantes do evento "${
        eventData.activityText || eventData.title
      }"`,
    },
    n_related_id: eventData.id,
    n_read: false,
    n_sender_id: "system",
    n_sender_fullname: "Sistema",
    n_sender_photo_link: "",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
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
      n_type: "review_request",
      n_params: {
        eventId: eventData.id,
        actionType: "open_pending_reviews",
        title: "⭐ Avalie o evento!",
        message: `Como foi o evento "${
          eventData.activityText || eventData.title
        }"? Deixe sua avaliação!`,
      },
      n_related_id: eventData.id,
      n_read: false,
      n_sender_id: "system",
      n_sender_fullname: "Sistema",
      n_sender_photo_link: "",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  await batch.commit();
  console.log("✅ [sendNotifications] Notifications sent successfully");
}
