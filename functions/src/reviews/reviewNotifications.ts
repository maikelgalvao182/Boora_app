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
      const comment = reviewData.comment;

      if (!revieweeId) {
        console.error("❌ [ReviewPush] Review sem reviewee_id");
        return;
      }

      // Montar mensagem
      let body = "";
      if (comment && comment.length > 0) {
        body = `${reviewerName} te avaliou: "${comment}"`;
      } else {
        body = `${reviewerName} te avaliou com ` +
          `${overallRating.toFixed(1)} estrelas!`;
      }

      await sendPush({
        userId: revieweeId,
        type: "global",
        title: "Nova avaliação ⭐️",
        body: body,
        data: {
          sub_type: "new_review",
          reviewId: reviewId,
          reviewerName: reviewerName,
          rating: overallRating.toString(),
        },
      });
    } catch (error) {
      console.error("❌ [ReviewPush] Erro fatal:", error);
    }
  });

