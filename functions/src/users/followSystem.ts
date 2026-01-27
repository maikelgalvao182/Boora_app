import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * followUser
 * Input: { targetUid: string }
 * Output: { status: 'followed' | 'already_following', followersCount: number }
 */
export const followUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be logged in to follow."
    );
  }

  const uid = context.auth.uid;
  const targetUid = data.targetUid;

  if (!targetUid || typeof targetUid !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "The function must be called with one argument 'targetUid'."
    );
  }

  if (uid === targetUid) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "You cannot follow yourself."
    );
  }

  const userRef = db.collection("Users").doc(uid);
  const targetUserRef = db.collection("Users").doc(targetUid);

  const followingRef = userRef.collection("following").doc(targetUid);
  const followersRef = targetUserRef.collection("followers").doc(uid);

  try {
    const result = await db.runTransaction(async (transaction) => {
      const followingDoc = await transaction.get(followingRef);

      if (followingDoc.exists) {
        return {status: "already_following"};
      }

      // Create doc in users/{uid}/following/{targetUid}
      transaction.set(followingRef, {
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Create doc in users/{targetUid}/followers/{uid}
      transaction.set(followersRef, {
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Increment followingCount for current user
      transaction.update(userRef, {
        followingCount: admin.firestore.FieldValue.increment(1),
      });

      // Increment followersCount for target user
      transaction.update(targetUserRef, {
        followersCount: admin.firestore.FieldValue.increment(1),
      });

      return {status: "followed"};
    });

    return result;
  } catch (error) {
    console.error("Error following user:", error);
    throw new functions.https.HttpsError("internal", "Unable to follow user.");
  }
});

/**
 * unfollowUser
 * Input: { targetUid: string }
 * Output: { status: 'unfollowed' | 'not_following' }
 */
export const unfollowUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be logged in to unfollow."
    );
  }

  const uid = context.auth.uid;
  const targetUid = data.targetUid;

  if (!targetUid || typeof targetUid !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "The function must be called with one argument 'targetUid'."
    );
  }

  const userRef = db.collection("Users").doc(uid);
  const targetUserRef = db.collection("Users").doc(targetUid);

  const followingRef = userRef.collection("following").doc(targetUid);
  const followersRef = targetUserRef.collection("followers").doc(uid);

  try {
    const result = await db.runTransaction(async (transaction) => {
      const followingDoc = await transaction.get(followingRef);

      if (!followingDoc.exists) {
        return {status: "not_following"};
      }

      // Delete doc in users/{uid}/following/{targetUid}
      transaction.delete(followingRef);

      // Delete doc in users/{targetUid}/followers/{uid}
      transaction.delete(followersRef);

      // Decrement followingCount for current user
      transaction.update(userRef, {
        followingCount: admin.firestore.FieldValue.increment(-1),
      });

      // Decrement followersCount for target user
      transaction.update(targetUserRef, {
        followersCount: admin.firestore.FieldValue.increment(-1),
      });

      return {status: "unfollowed"};
    });

    return result;
  } catch (error) {
    console.error("Error unfollowing user:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Unable to unfollow user."
    );
  }
});
