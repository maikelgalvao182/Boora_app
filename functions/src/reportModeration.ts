import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Converte um valor desconhecido em string não vazia.
 * @param {unknown} value Valor de entrada.
 * @return {string|null} String normalizada ou null.
 */
function asNonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Trigger: ao criar `reports/{reportId}`, tenta inativar o alvo.
 * - `events/{eventId}.status`: active -> inactive
 * - `Users/{targetUserId}.status`: active -> inactive
 * @return {Promise<void>} Promise.
 */
export const onReportCreated = functions.firestore
  .document("reports/{reportId}")
  .onCreate(async (snap, context): Promise<void> => {
    const reportId = String(context.params.reportId || "");
    const data = (snap.data() || {}) as Record<string, unknown>;

    const eventId = asNonEmptyString(data.eventId);
    const targetUserId = asNonEmptyString(data.targetUserId);

    if (!eventId && !targetUserId) {
      console.log("⏭️ [onReportCreated] sem alvo", {reportId});
      return;
    }

    const db = admin.firestore();
    const batch = db.batch();
    let updatesCount = 0;

    try {
      if (eventId) {
        const eventRef = db.collection("events").doc(eventId);
        const eventSnap = await eventRef.get();
        if (eventSnap.exists) {
          const status = eventSnap.get("status") as unknown;
          if (status === "active") {
            batch.set(eventRef, {status: "inactive"}, {merge: true});
            updatesCount += 1;
          }
        }
      }

      if (targetUserId) {
        const userRef = db.collection("Users").doc(targetUserId);
        const userSnap = await userRef.get();
        if (userSnap.exists) {
          const status = userSnap.get("status") as unknown;
          if (status === "active") {
            batch.set(userRef, {status: "inactive"}, {merge: true});
            updatesCount += 1;
          }
        }
      }

      if (updatesCount === 0) {
        console.log("⏭️ [onReportCreated] nada a fazer", {reportId});
        return;
      }

      await batch.commit();
      console.log("✅ [onReportCreated] inativado", {
        reportId,
        updatesCount,
        eventId,
        targetUserId,
      });
    } catch (error) {
      console.error("❌ [onReportCreated] erro", {reportId, error});
    }
  });
