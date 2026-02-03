import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const BATCH_LIMIT = 450;
const APPLICATION_BATCH_LIMIT = 200;
const LOCK_MINUTES = 9;

if (!admin.apps.length) {
  admin.initializeApp();
}

export const processEventDeletions = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async () => {
    const firestore = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    const jobSnapshot = await firestore
      .collection("eventdeletions")
      .where("status", "in", ["pending", "running"])
      .orderBy("updatedAt", "asc")
      .limit(1)
      .get();

    if (jobSnapshot.empty) {
      console.log("🧹 [processEventDeletions] No jobs found");
      return null;
    }

    const jobDoc = jobSnapshot.docs[0];
    const jobRef = jobDoc.ref;
    const jobData = jobDoc.data() || {};
    const eventId = String(jobData.eventId || jobDoc.id);
    const status = String(jobData.status || "pending");
    const phase = String(jobData.phase || "messages");
    const lockedUntil = jobData.lockedUntil as admin.firestore.Timestamp | null;

    if (status === "running" && lockedUntil && lockedUntil.toMillis() > now.toMillis()) {
      console.log("⏳ [processEventDeletions] Job locked, skipping", eventId);
      return null;
    }

    const newLock = admin.firestore.Timestamp.fromMillis(
      now.toMillis() + LOCK_MINUTES * 60 * 1000
    );

    await jobRef.update({
      status: "running",
      lockedUntil: newLock,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      if (phase === "messages") {
        await processMessagesPhase(eventId, jobRef, jobData);
        return null;
      }

      if (phase === "applications") {
        await processApplicationsPhase(eventId, jobRef, jobData);
        return null;
      }

      if (phase === "notifications") {
        await processNotificationsPhase(eventId, jobRef, jobData);
        return null;
      }

      if (phase === "feedItems") {
        await processFeedItemsPhase(eventId, jobRef, jobData);
        return null;
      }

      if (phase === "finalize") {
        await finalizeDeletion(eventId, jobRef);
        return null;
      }

      await jobRef.update({
        phase: "messages",
        status: "pending",
        lockedUntil: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return null;
    } catch (error) {
      console.error("❌ [processEventDeletions] Error:", error);
      await jobRef.update({
        status: "pending",
        lockedUntil: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastError: String(error),
      });
      return null;
    }
  });

async function processMessagesPhase(
  eventId: string,
  jobRef: FirebaseFirestore.DocumentReference,
  jobData: FirebaseFirestore.DocumentData
): Promise<void> {
  const firestore = admin.firestore();
  const cursor = jobData.messageCursor as string | null;

  const query = firestore
    .collection("EventChats")
    .doc(eventId)
    .collection("Messages");

  const {deleted, nextCursor} = await deleteCollectionPage(query, cursor, BATCH_LIMIT);

  if (deleted === 0) {
    await jobRef.update({
      phase: "applications",
      messageCursor: null,
      status: "pending",
      lockedUntil: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  await jobRef.update({
    messageCursor: nextCursor,
    status: "pending",
    lockedUntil: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ["stats.messages"]: admin.firestore.FieldValue.increment(deleted),
  });
}

async function processApplicationsPhase(
  eventId: string,
  jobRef: FirebaseFirestore.DocumentReference,
  jobData: FirebaseFirestore.DocumentData
): Promise<void> {
  const firestore = admin.firestore();
  const cursor = jobData.applicationCursor as string | null;
  const eventUserId = `event_${eventId}`;

  let query = firestore
    .collection("EventApplications")
    .where("eventId", "==", eventId)
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(APPLICATION_BATCH_LIMIT);

  if (cursor) {
    query = query.startAfter(cursor);
  }

  const snapshot = await query.get();
  if (snapshot.empty) {
    await jobRef.update({
      phase: "notifications",
      applicationCursor: null,
      status: "pending",
      lockedUntil: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  const batch = firestore.batch();
  let conversationDeletes = 0;

  snapshot.docs.forEach((doc) => {
    const data = doc.data() || {};
    const userId = typeof data.userId === "string" ? data.userId : null;

    batch.delete(doc.ref);

    if (userId) {
      const conversationRef = firestore
        .collection("Connections")
        .doc(userId)
        .collection("Conversations")
        .doc(eventUserId);
      batch.delete(conversationRef);
      conversationDeletes += 1;
    }
  });

  await batch.commit();

  const lastDoc = snapshot.docs[snapshot.docs.length - 1];
  await jobRef.update({
    applicationCursor: lastDoc.id,
    status: "pending",
    lockedUntil: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ["stats.applications"]: admin.firestore.FieldValue.increment(snapshot.size),
    ["stats.conversations"]: admin.firestore.FieldValue.increment(conversationDeletes),
  });
}

async function processNotificationsPhase(
  eventId: string,
  jobRef: FirebaseFirestore.DocumentReference,
  jobData: FirebaseFirestore.DocumentData
): Promise<void> {
  const firestore = admin.firestore();
  const currentPhase = String(jobData.notificationPhase || "eventId");
  const cursor = jobData.notificationCursor as string | null;

  const {field, nextPhase} = resolveNotificationPhase(currentPhase);

  let query = firestore
    .collection("Notifications")
    .where(field, "==", eventId)
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(BATCH_LIMIT);

  if (cursor) {
    query = query.startAfter(cursor);
  }

  const snapshot = await query.get();
  if (snapshot.empty) {
    if (nextPhase) {
      await jobRef.update({
        notificationPhase: nextPhase,
        notificationCursor: null,
        status: "pending",
        lockedUntil: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    await jobRef.update({
      phase: "feedItems",
      notificationPhase: "eventId",
      notificationCursor: null,
      status: "pending",
      lockedUntil: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  const batch = firestore.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();

  const lastDoc = snapshot.docs[snapshot.docs.length - 1];
  await jobRef.update({
    notificationCursor: lastDoc.id,
    status: "pending",
    lockedUntil: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ["stats.notifications"]: admin.firestore.FieldValue.increment(snapshot.size),
  });
}

async function processFeedItemsPhase(
  eventId: string,
  jobRef: FirebaseFirestore.DocumentReference,
  jobData: FirebaseFirestore.DocumentData
): Promise<void> {
  const firestore = admin.firestore();
  const cursor = jobData.feedCursor as string | null;

  let query = firestore
    .collection("ActivityFeed")
    .where("eventId", "==", eventId)
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(BATCH_LIMIT);

  if (cursor) {
    query = query.startAfter(cursor);
  }

  const snapshot = await query.get();
  if (snapshot.empty) {
    await jobRef.update({
      phase: "finalize",
      feedCursor: null,
      status: "pending",
      lockedUntil: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  const batch = firestore.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();

  const lastDoc = snapshot.docs[snapshot.docs.length - 1];
  await jobRef.update({
    feedCursor: lastDoc.id,
    status: "pending",
    lockedUntil: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ["stats.feedItems"]: admin.firestore.FieldValue.increment(snapshot.size),
  });
}

async function finalizeDeletion(
  eventId: string,
  jobRef: FirebaseFirestore.DocumentReference
): Promise<void> {
  const firestore = admin.firestore();
  const batch = firestore.batch();

  batch.delete(firestore.collection("EventChats").doc(eventId));
  batch.delete(firestore.collection("events").doc(eventId));

  await batch.commit();

  await jobRef.update({
    status: "completed",
    phase: "completed",
    lockedUntil: null,
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function deleteCollectionPage(
  collectionRef: FirebaseFirestore.CollectionReference,
  cursor: string | null,
  limit: number
): Promise<{deleted: number; nextCursor: string | null}> {
  let query = collectionRef
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(limit);

  if (cursor) {
    query = query.startAfter(cursor);
  }

  const snapshot = await query.get();
  if (snapshot.empty) {
    return {deleted: 0, nextCursor: null};
  }

  const batch = admin.firestore().batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();

  const lastDoc = snapshot.docs[snapshot.docs.length - 1];
  return {deleted: snapshot.size, nextCursor: lastDoc.id};
}

function resolveNotificationPhase(phase: string): {
  field: string;
  nextPhase: string | null;
} {
  if (phase === "eventId") {
    return {field: "eventId", nextPhase: "activityId"};
  }

  if (phase === "activityId") {
    return {field: "n_params.activityId", nextPhase: "relatedId"};
  }

  return {field: "n_related_id", nextPhase: null};
}
