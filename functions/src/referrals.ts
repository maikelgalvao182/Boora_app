import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const REFERRAL_REWARD_THRESHOLD = 10;
const REFERRAL_REWARD_MONTHS = 3;
const REFERRAL_REWARD_DAYS = REFERRAL_REWARD_MONTHS * 30;

export const onUserCreatedReferral = functions.firestore
  .document("Users/{userId}")
  .onCreate(async (snap, context) => {
    const userId = context.params.userId as string;
    const data = snap.data() || {};

    const referrerId =
      data.referrerId || data.invitedBy || data.referredBy || null;

    if (!referrerId || typeof referrerId !== "string") {
      return;
    }

    if (referrerId === userId) {
      console.warn("[Referral] Ignorando auto-indicação", {userId});
      return;
    }

    const db = admin.firestore();
    const referrerRef = db.collection("Users").doc(referrerId);
    const referralInstallRef = db.collection("ReferralInstalls").doc(userId);

    await db.runTransaction(async (tx) => {
      const referrerDoc = await tx.get(referrerRef);
      if (!referrerDoc.exists) {
        console.warn("[Referral] Referrer não encontrado", {referrerId});
        return;
      }

      const referralInstallDoc = await tx.get(referralInstallRef);
      if (referralInstallDoc.exists) {
        return;
      }

      const referrerData = referrerDoc.data() || {};
      const currentCount = Number(referrerData.referralInstallCount || 0);
      const rewardedCount = Number(referrerData.referralRewardedCount || 0);

      const newCount = currentCount + 1;
      const newRewardedCount = Math.floor(newCount / REFERRAL_REWARD_THRESHOLD);
      const rewardDelta = newRewardedCount - rewardedCount;

      const updates: Record<string, unknown> = {
        referralInstallCount: newCount,
        referralUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (rewardDelta > 0) {
        const now = new Date();
        const existingVip = referrerData.vipExpiresAt;
        const existingDate =
          existingVip instanceof admin.firestore.Timestamp
            ? existingVip.toDate()
            : null;

        const baseDate = existingDate && existingDate > now ? existingDate : now;
        const addMs = REFERRAL_REWARD_DAYS * 24 * 60 * 60 * 1000 * rewardDelta;
        const newVipExpiresAt = new Date(baseDate.getTime() + addMs);

        updates.user_is_vip = true;
        updates.user_level = "vip";
        updates.vip_priority = 1;
        updates.vipExpiresAt = admin.firestore.Timestamp.fromDate(newVipExpiresAt);
        updates.vipUpdatedAt = admin.firestore.FieldValue.serverTimestamp();
        updates.vipProductId = "referral_bonus_3m";
        updates.referralRewardedCount = newRewardedCount;
        updates.referralRewardedAt = admin.firestore.FieldValue.serverTimestamp();
      }

      tx.set(
        referralInstallRef,
        {
          userId,
          referrerId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          source: data.referralSource || "appsflyer",
          deepLinkValue: data.referralDeepLinkValue || null,
        },
        {merge: true}
      );

      tx.update(referrerRef, updates);
    });
  });
