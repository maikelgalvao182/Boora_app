import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Cria PendingReview para participant quando owner confirma presença
 *
 * Trigger: onUpdate em PendingReviews (apenas owner reviews)
 * Detecta mudança de presence_confirmed: false → true
 * Cria PendingReview individual para participant avaliar owner
 *
 * Garante idempotência verificando se já existe
 */
export const onPresenceConfirmed = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .firestore
  .document("PendingReviews/{reviewId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const reviewId = context.params.reviewId;

    // 1. Validar que é uma owner review
    if (after.reviewer_role !== "owner") {
      console.log(
        `⏭️ [onPresenceConfirmed] ${reviewId}: Não é owner review, pulando`
      );
      return null;
    }

    // 2. Extrair dados necessários
    const eventId = after.event_id;
    const ownerId = after.reviewer_id;
    const eventTitle = after.event_title;
    const eventEmoji = after.event_emoji;
    const eventLocation = after.event_location;
    const eventDate = after.event_date;
    const expiresAt = after.expires_at;

    if (!eventId || !ownerId) {
      console.error(
        `❌ [onPresenceConfirmed] ${reviewId}: Dados incompletos`
      );
      return null;
    }

    // 3. Comparar participant_profiles antes/depois
    const beforeProfiles = before.participant_profiles || {};
    const afterProfiles = after.participant_profiles || {};

    const participantsToProcess: string[] = [];

    for (const participantId of Object.keys(afterProfiles)) {
      const wasFalse =
        beforeProfiles[participantId]?.presence_confirmed === false;
      const isNowTrue =
        afterProfiles[participantId]?.presence_confirmed === true;

      if (wasFalse && isNowTrue) {
        participantsToProcess.push(participantId);
        console.log(
          `✅ [onPresenceConfirmed] ${reviewId}: ` +
          `Participante ${participantId} confirmado`
        );
      }
    }

    if (participantsToProcess.length === 0) {
      console.log(
        `⏭️ [onPresenceConfirmed] ${reviewId}: Nenhuma confirmação nova`
      );
      return null;
    }

    console.log(
      `🎯 [onPresenceConfirmed] ${reviewId}: ` +
      `Processando ${participantsToProcess.length} confirmação(ões)`
    );

    // 4. Buscar dados do owner para exibição
    let ownerName = "Organizador";
    let ownerPhoto = null;
    try {
      const ownerDoc = await admin.firestore()
        .collection("Users")
        .doc(ownerId)
        .get();
      if (ownerDoc.exists) {
        const ownerData = ownerDoc.data();
        ownerName = ownerData?.fullName || "Organizador";
        ownerPhoto = ownerData?.photoUrl || null;
      }
    } catch (e) {
      console.warn(
        `⚠️ [onPresenceConfirmed] Erro ao buscar owner ${ownerId}:`,
        e
      );
    }

    // 5. Criar PendingReview para cada participant confirmado
    const batch = admin.firestore().batch();
    let createdCount = 0;
    let skippedCount = 0;

    for (const participantId of participantsToProcess) {
      const participantReviewId = `${eventId}_participant_${participantId}`;
      const participantReviewRef = admin.firestore()
        .collection("PendingReviews")
        .doc(participantReviewId);

      // 5.1. Verificar idempotência - se já existe, pular
      const existingDoc = await participantReviewRef.get();
      if (existingDoc.exists) {
        console.log(
          "⏭️ [onPresenceConfirmed] PendingReview já existe: " +
          `${participantReviewId}`
        );
        skippedCount++;
        continue;
      }

      // 5.2. Criar novo PendingReview
      batch.set(participantReviewRef, {
        pending_review_id: participantReviewId,
        event_id: eventId,
        reviewer_id: participantId,
        reviewer_role: "participant",
        reviewee_id: ownerId,

        reviewee_name: ownerName,
        reviewee_photo_url: ownerPhoto,

        // Dados do Owner para exibição
        owner_name: ownerName,
        owner_photo_url: ownerPhoto,
        allowed_to_review_owner: true, // Confirmado = pode avaliar

        event_title: eventTitle,
        event_emoji: eventEmoji,
        event_location: eventLocation,
        event_date: eventDate,

        created_at: admin.firestore.FieldValue.serverTimestamp(),
        expires_at: expiresAt,
        dismissed: false,
        status: "pending",
      });

      createdCount++;
      console.log(
        `✅ [onPresenceConfirmed] Criado PendingReview: ${participantReviewId}`
      );
    }

    // 6. Commit do batch
    if (createdCount > 0) {
      try {
        await batch.commit();
        console.log(
          `✅ [onPresenceConfirmed] ${reviewId}: ` +
          `${createdCount} review(s) criado(s), ${skippedCount} pulado(s)`
        );
      } catch (error) {
        console.error(
          "❌ [onPresenceConfirmed] Erro ao commitar batch:",
          error
        );
        throw error;
      }
    } else {
      console.log(
        `⏭️ [onPresenceConfirmed] ${reviewId}: Nada para criar`
      );
    }

    return null;
  });
