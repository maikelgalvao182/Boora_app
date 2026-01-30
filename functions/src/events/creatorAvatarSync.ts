import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

function resolveUserAvatarUrl(data: FirebaseFirestore.DocumentData | undefined): string {
  if (!data) return "";
  return (
    data.photoUrl ||
    data.profilePhoto ||
    data.avatarUrl ||
    data.organizerAvatarThumbUrl ||
    ""
  );
}

function resolvePreviewAvatarUrl(
  data: FirebaseFirestore.DocumentData | undefined
): string {
  if (!data) return "";
  return data.photoUrl || "";
}

const MAX_EVENTS_PER_SYNC = 200;

async function updateEventsMapAvatar(userId: string, avatarUrl: string) {
  const db = admin.firestore();
  let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;

  while (true) {
    let query = db
      .collection("events_map")
      .where("isActive", "==", true)
      .where("createdBy", "==", userId)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(MAX_EVENTS_PER_SYNC);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }

    const batches: FirebaseFirestore.WriteBatch[] = [];
    let batch = db.batch();
    let opCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      if (data.creatorAvatarUrl === avatarUrl) {
        continue;
      }

      batch.update(doc.ref, {
        creatorAvatarUrl: avatarUrl,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      opCount++;

      if (opCount >= 450) {
        batches.push(batch);
        batch = db.batch();
        opCount = 0;
      }
    }

    if (opCount > 0) {
      batches.push(batch);
    }

    for (const b of batches) {
      await b.commit();
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < MAX_EVENTS_PER_SYNC) {
      break;
    }
  }
}

export const onUserAvatarUpdated = functions.firestore
  .document("Users/{userId}")
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};

    const beforeUrl = resolveUserAvatarUrl(beforeData);
    const afterUrl = resolveUserAvatarUrl(afterData);

    if (beforeUrl === afterUrl) {
      return;
    }

    const userId = context.params.userId as string;
    const db = admin.firestore();

    await Promise.all([
      db.collection("users_preview").doc(userId).set(
        {
          photoUrl: afterUrl,
          fullName: afterData.fullName || beforeData.fullName || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      ),
      updateEventsMapAvatar(userId, afterUrl),
    ]);
  });

export const backfillMissingCreatorAvatarUrl = functions.pubsub
  .schedule("every 6 hours")
  .onRun(async () => {
    const db = admin.firestore();
    const userCache = new Map<string, string>();
    const previewCache = new Map<string, string>();

    const queries = [
      db.collection("events_map")
        .where("isActive", "==", true)
        .where("creatorAvatarUrl", "==", null)
        .limit(300),
      db.collection("events_map")
        .where("isActive", "==", true)
        .where("creatorAvatarUrl", "==", "")
        .limit(300),
    ];

    for (const query of queries) {
      const snapshot = await query.get();
      if (snapshot.empty) continue;

      const batch = db.batch();
      let updates = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data() || {};
        const createdBy = String(data.createdBy || "");
        if (!createdBy) continue;

        let avatarUrl = previewCache.get(createdBy);
        if (!avatarUrl) {
          const previewDoc = await db
            .collection("users_preview")
            .doc(createdBy)
            .get();
          avatarUrl = resolvePreviewAvatarUrl(previewDoc.data()) || "";
          previewCache.set(createdBy, avatarUrl);
        }

        if (!avatarUrl) {
          avatarUrl = userCache.get(createdBy) ?? "";
        }

        if (!avatarUrl) {
          const userDoc = await db.collection("Users").doc(createdBy).get();
          avatarUrl = resolveUserAvatarUrl(userDoc.data()) || "";
          userCache.set(createdBy, avatarUrl);
        }

        if (!avatarUrl) continue;

        if (data.creatorAvatarUrl === avatarUrl) {
          continue;
        }

        batch.update(doc.ref, {
          creatorAvatarUrl: avatarUrl,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        updates++;
      }

      if (updates > 0) {
        await batch.commit();
      }
    }
  });
