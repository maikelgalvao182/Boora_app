import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {buildInterestBuckets} from "../utils/interestBuckets";
import {encodeGeohash} from "../utils/geohash";

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
  if (typeof data.latitude === "number" && typeof data.longitude === "number") {
    return {lat: data.latitude, lng: data.longitude};
  }
  return null;
}

export const onUserLocationUpdated = functions.firestore
  .document("Users/{userId}")
  .onWrite(async (change, context) => {
    const after = change.after.exists ? change.after.data() : null;
    if (!after) return;

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
      return;
    }

    const userId = context.params.userId as string;
    const updatePayload: Record<string, unknown> = {
      interestBuckets,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (gridId) {
      updatePayload.gridId = gridId;
    }

    if (geohash) {
      updatePayload.geohash = geohash;
    }

    await admin.firestore()
      .collection("users_preview")
      .doc(userId)
      .set(updatePayload, {merge: true});
  });
