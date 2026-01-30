import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Syncs changes from 'events' collection to 'events_map' lite collection.
 * optimizes payload size for map queries.
 */
export const syncEventToMap = functions.firestore
  .document("events/{eventId}")
  .onWrite(async (change, context) => {
    const eventId = context.params.eventId;
    const db = admin.firestore();

    // Handle deletion
    if (!change.after.exists) {
      console.log(`🗑️ Event deleted, removing from events_map: ${eventId}`);
      await db.collection("events_map").doc(eventId).delete();
      return;
    }

    const data = change.after.data();
    if (!data) return;

    // Filter logic: Only active events should be on the map?
    // MapDiscoveryService filters by 'isActive' == true.
    // If we want to save space/reads,
    // we could ONLY write to events_map if valid.
    // BUT MapDiscoveryService might expect to find them and filter them out?
    // Optimally: Only keep active events in events_map.

    const isActive = data.isActive === true;
    const isCanceled = data.isCanceled === true;
    const status = data.status;
    const isVisible = isActive && !isCanceled &&
      (status === "active" || !status);

    if (!isVisible) {
      // If it exists in map but is no longer visible, remove it.
      // Or we can keep it with a flag if we want soft-deletes,
      // but removal is cleaner for "map inputs".
      // MapDiscoveryService queries `where('isActive', isEqualTo: true)`.
      // So if we just don't put it there, the query works.
      // Let's remove it to keep index size small.
      await db.collection("events_map").doc(eventId).delete();
      return;
    }

    // Prepare lite payload
    // Extract Geopoint
    let lat = 0.0;
    let lng = 0.0;

    if (data.location && typeof data.location.latitude === "number") {
      lat = data.location.latitude;
      lng = data.location.longitude;
    } else if (typeof data.latitude === "number") {
      lat = data.latitude;
      lng = data.longitude;
    }

    // Schedule
    let scheduleDate = null;
    if (data.scheduleDate) {
      scheduleDate = data.scheduleDate;
    } else if (data.schedule && data.schedule.date) {
      scheduleDate = data.schedule.date;
    }

    // Thumbnail
    let photoUrl = null;
    if (data.photoReferences && data.photoReferences.length > 0) {
      photoUrl = data.photoReferences[0];
    } else if (data.image) {
      photoUrl = data.image; // Legacy fallback
    }

    // Creator Avatar (N+1 Denormalization)
    let creatorAvatarUrl = data.creatorAvatarUrl ||
      data.organizerAvatarThumbUrl ||
      data.creatorPhotoUrl ||
      data.authorPhotoUrl ||
      null;

    if (!creatorAvatarUrl && data.createdBy) {
      try {
        const creatorDoc = await db
          .collection("Users")
          .doc(String(data.createdBy))
          .get();
        const creatorData = creatorDoc.data() || {};
        creatorAvatarUrl =
          creatorData.photoUrl ||
          creatorData.profilePhoto ||
          creatorData.avatarUrl ||
          null;
      } catch (error) {
        console.warn(
          "⚠️ [events_map] Falha ao buscar avatar do criador",
          {eventId, error}
        );
      }
    }

    // Participants count
    let participantsCount = 0;
    if (data.participants && Array.isArray(data.participants.approved)) {
      participantsCount = data.participants.approved.length;
    } else if (typeof data.participantsCount === "number") {
      participantsCount = data.participantsCount; // Denormalized count
    }

    // Construct Lite Object
    const mapDoc = {
      // Essential for Query
      location: {latitude: lat, longitude: lng},
      isActive: true, // enforced by visibility check above

      // Marker Display
      emoji: data.emoji || "🎉",
      activityText: data.activityText || data.title || "", // 'title'
      category: data.category,

      // Card Preview
      scheduleDate: scheduleDate,
      photoUrl: photoUrl,
      creatorAvatarUrl: creatorAvatarUrl,
      creatorFullName: data.creatorFullName || data.organizerName,
      participantsCount: participantsCount,

      // Filtering & Logic
      privacyType: data.privacyType || "open",
      minAge: data.minAge,
      maxAge: data.maxAge,
      gender: data.gender,

      // Meta
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: data.createdBy,
      isBoosted: data.isBoosted || false, // Flags
      hasPremium: data.hasPremium || false, // Flags
    };

    await db.collection("events_map").doc(eventId).set(mapDoc);
    console.log(`🗺️ Synced event to events_map: ${eventId}`);
  });
