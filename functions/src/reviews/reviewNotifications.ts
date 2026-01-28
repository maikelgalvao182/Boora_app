import * as functions from "firebase-functions/v1";
import {sendPush} from "../services/pushDispatcher";

/**
 * Trigger: Nova Review criada
 * Path: Reviews/{reviewId}
 *
 * Envia push notification para o avaliado (reviewee)
 */
export const onReviewCreated = functions.firestore
  .document("Reviews/{reviewId}")
  .onCreate(async (snap, context) => {
    const reviewId = context.params.reviewId;
    const reviewData = snap.data();

    if (!reviewData) {
      console.error("❌ [ReviewPush] Review sem dados:", reviewId);
      return;
    }

    try {
      const revieweeId = reviewData.reviewee_id;
      const reviewerName = reviewData.reviewer_name || "Alguém";
      const overallRating = reviewData.overall_rating || 0;

      if (!revieweeId) {
        console.error("❌ [ReviewPush] Review sem reviewee_id");
        return;
      }

      // Template: newReviewReceived
      const ratingStr = overallRating.toFixed(1);
      const body = `${reviewerName} te avaliou com ${ratingStr} estrelas!`;

      // DeepLink: abre a review específica ou tela de reviews
      const deepLink = `partiu://reviews/${revieweeId}`;

      await sendPush({
        userId: revieweeId,
        event: "new_review_received",
        origin: "reviewNotifications",
        notification: {
          title: "Nova avaliação ⭐️",
          body: body,
        },
        data: {
          n_type: "new_review_received",
          relatedId: reviewId,
          n_related_id: reviewId,
          reviewId: reviewId,
          reviewerName: reviewerName,
          rating: overallRating.toString(),
          deepLink: deepLink,
        },
      });
    } catch (error) {
      console.error("❌ [ReviewPush] Erro fatal:", error);
    }
  });

