import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {buildInterestBuckets} from "../utils/interestBuckets";
import {encodeGeohash} from "../utils/geohash";
import {createExecutionMetrics} from "../utils/executionMetrics";
import {getBooleanFeatureFlag} from "../utils/featureFlags";

const GRID_BUCKET_SIZE_DEG = 0.05;

function gridBucket(value: number, bucketSize: number): number {
  return Math.floor(value / bucketSize);
}

function buildGridId(lat: number, lng: number, bucketSize: number): string {
  const latBucket = gridBucket(lat, bucketSize);
  const lngBucket = gridBucket(lng, bucketSize);
  return `${latBucket}_${lngBucket}`;
}

function resolveLatLng(
  data: FirebaseFirestore.DocumentData | null | undefined
): {lat: number; lng: number} | null {
  if (!data) return null;
  if (data.location &&
      typeof data.location.latitude === "number" &&
      typeof data.location.longitude === "number") {
    return {lat: data.location.latitude, lng: data.location.longitude};
  }
  // displayLatitude/displayLongitude (atual, público com offset)
  if (typeof data.displayLatitude === "number" &&
      typeof data.displayLongitude === "number") {
    return {lat: data.displayLatitude, lng: data.displayLongitude};
  }
  // Fallback: latitude/longitude legado (dados antigos)
  if (typeof data.latitude === "number" && typeof data.longitude === "number") {
    return {lat: data.latitude, lng: data.longitude};
  }
  return null;
}

export const onUserLocationUpdated = functions.firestore
  .document("Users/{userId}")
  .onWrite(async (change, context) => {
    const userId = context.params.userId as string;
    const metrics = createExecutionMetrics({
      executionId: context.eventId,
    });

    const disableLegacySync =
      await getBooleanFeatureFlag("disableLegacyUsersLocationSync", false) ||
      await getBooleanFeatureFlag("disableLegacyUsersPreviewTriggers", false);

    if (disableLegacySync) {
      metrics.done({
        userId,
        skipped: true,
        reason: "legacy_location_sync_disabled_by_flag",
      });
      return;
    }

    const after = change.after.exists ? change.after.data() : null;
    if (!after) {
      metrics.done({userId, skipped: true, reason: "document_deleted"});
      return;
    }

    const before = change.before.exists ? change.before.data() : null;
    const beforeCoords = resolveLatLng(before);
    const afterCoords = resolveLatLng(after);

    const interestBuckets = buildInterestBuckets(after.interests);
    const beforeInterestBuckets = buildInterestBuckets(before?.interests);
    const interestsChanged = interestBuckets.length !== beforeInterestBuckets.length ||
      interestBuckets.some((value) => !beforeInterestBuckets.includes(value));

    let gridId: string | null = null;
    let geohash: string | null = null;
    const shouldUpdateGridId = afterCoords &&
      (!beforeCoords ||
        beforeCoords.lat !== afterCoords.lat ||
        beforeCoords.lng !== afterCoords.lng);
    if (afterCoords && shouldUpdateGridId) {
      gridId = buildGridId(
        afterCoords.lat,
        afterCoords.lng,
        GRID_BUCKET_SIZE_DEG
      );
    }

    if (afterCoords) {
      geohash = encodeGeohash(afterCoords.lat, afterCoords.lng, 7);
    }

    const previousGeohash = typeof before?.geohash === "string" ? before.geohash : "";
    const shouldUpdateGeohash = Boolean(geohash) && geohash != previousGeohash;

    if (!interestsChanged && !shouldUpdateGridId && !shouldUpdateGeohash) {
      metrics.done({userId, skipped: true, reason: "no_relevant_changes"});
      return;
    }

    const updatePayload: Record<string, unknown> = {
      interestBuckets,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Escrever latitude/longitude (do display) no users_preview
    // para manter compatibilidade com queries do getPeople
    if (afterCoords) {
      updatePayload.latitude = afterCoords.lat;
      updatePayload.longitude = afterCoords.lng;
    }

    if (gridId) {
      updatePayload.gridId = gridId;
    }

    if (geohash) {
      updatePayload.geohash = geohash;
    }

    try {
      await admin.firestore()
        .collection("users_preview")
        .doc(userId)
        .set(updatePayload, {merge: true});
      metrics.addWrites(1);
      metrics.done({
        userId,
        interestsChanged,
        gridUpdated: Boolean(gridId),
        geohashUpdated: Boolean(geohash),
      });
    } catch (error) {
      metrics.fail(error, {userId, stage: "update_users_preview"});
      throw error;
    }
  });
