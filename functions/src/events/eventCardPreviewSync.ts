import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * 🎯 Cloud Function: Sincroniza events → events_card_preview
 *
 * Objetivo: versão leve para EventCard (reduz leitura do doc completo).
 */
export const onEventWriteUpdateCardPreview = functions.firestore
  .document("events/{eventId}")
  .onWrite(async (change, context) => {
    const eventId = context.params.eventId;

    if (!change.after.exists) {
      await db.collection("events_card_preview").doc(eventId).delete();
      return;
    }

    const data = change.after.data() || {};
    const location = (data.location || {}) as Record<string, unknown>;
    const schedule = (data.schedule || {}) as Record<string, unknown>;
    const participants = (data.participants || {}) as Record<string, unknown>;

    const status = (data.status as string | undefined) ?? undefined;
    const isCanceled = (data.isCanceled as boolean | undefined) ?? false;
    const isActive =
      (data.isActive as boolean | undefined) ?? (status == null || status == "active");

    const approvedList =
      (participants["approved"] as unknown[] | undefined) ?? undefined;

    const participantsCount =
      (data.participantsCount as number | undefined) ??
      (approvedList != null ? approvedList.length : undefined);

    const previewData = {
      eventId,
      emoji: (data.emoji as string | undefined) ?? "🎉",
      activityText:
        (data.activityText as string | undefined) ??
        (data.title as string | undefined) ??
        "",
      locationName: location["locationName"] ?? null,
      formattedAddress: location["formattedAddress"] ?? null,
      locality: location["locality"] ?? null,
      state: location["state"] ?? null,
      scheduleDate: schedule["date"] ?? null,
      scheduleFlexible: schedule["flexible"] ?? false,
      privacyType: participants["privacyType"] ?? null,
      minAge: participants["minAge"] ?? null,
      maxAge: participants["maxAge"] ?? null,
      gender: participants["gender"] ?? null,
      createdBy: data.createdBy ?? null,
      participantsCount: participantsCount ?? null,
      isCanceled,
      isActive,
      status: status ?? null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db
      .collection("events_card_preview")
      .doc(eventId)
      .set(previewData, {merge: true});
  });
