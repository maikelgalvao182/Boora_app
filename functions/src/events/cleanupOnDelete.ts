import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {deleteEventNotifications} from "./deleteEvent";

/**
 * Trigger que limpa dados relacionados quando um evento é deletado
 * (Seja via Admin SDK, Console ou Cliente)
 *
 * Isso garante que notificações "orphans" sejam removidas mesmo se
 * a deleção for feita via client-side (EventDeletionService.dart)
 */
export const cleanupOnEventDelete = functions.firestore
  .document("events/{eventId}")
  .onDelete(async (snap, context) => {
    const eventId = context.params.eventId;
    console.log(`🗑️ [cleanupOnEventDelete] Event deleted: ${eventId}`);

    try {
      const firestore = admin.firestore();

      // Limpa notificações relacionadas
      const deletedCount = await deleteEventNotifications(eventId, firestore);

      console.log(
        `✅ [cleanupOnEventDelete] Cleaned up ${deletedCount} ` +
        `notifications for event ${eventId}`
      );
    } catch (error) {
      console.error(
        `❌ [cleanupOnEventDelete] Error cleaning up event ${eventId}:`,
        error
      );
    }
  });
