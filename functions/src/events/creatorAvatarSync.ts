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

    await db.collection("users_preview").doc(userId).set(
      {
        photoUrl: afterUrl,
        fullName: afterData.fullName || beforeData.fullName || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
  });
