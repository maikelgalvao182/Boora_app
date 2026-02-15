import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {createExecutionMetrics} from "../utils/executionMetrics";

const BLACKLIST_COLLECTION = "BlacklistDevices";

export const checkDeviceBlacklist = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    const deviceIdHash = (data?.deviceIdHash ?? "").toString().trim();
    const platform = (data?.platform ?? "").toString().trim();

    if (!deviceIdHash) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "deviceIdHash is required"
      );
    }

    try {
      const doc = await admin
        .firestore()
        .collection(BLACKLIST_COLLECTION)
        .doc(deviceIdHash)
        .get();

      if (!doc.exists) {
        return {blocked: false};
      }

      const data = doc.data() || {};
      const active = data.active === true;

      if (!active) {
        return {blocked: false};
      }

      const reason = typeof data.reason === "string" ? data.reason : undefined;

      return {
        blocked: true,
        reason,
        platform,
      };
    } catch (error) {
      console.error("❌ checkDeviceBlacklist error", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to check device blacklist"
      );
    }
  });

export const registerDevice = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const currentUserId = context.auth.uid;
    const uid = (data?.uid ?? "").toString().trim();

    if (uid && uid !== currentUserId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "uid does not match authenticated user"
      );
    }

    const deviceIdHash = (data?.deviceIdHash ?? "").toString().trim();
    if (!deviceIdHash) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "deviceIdHash is required"
      );
    }

    const platform = (data?.platform ?? "").toString().trim();
    const deviceName = (data?.deviceName ?? "").toString().trim();
    const osName = (data?.osName ?? "").toString().trim();
    const osVersion = (data?.osVersion ?? "").toString().trim();
    const appVersion = (data?.appVersion ?? "").toString().trim();
    const buildCode = (data?.buildCode ?? "").toString().trim();
    const applicationName = (data?.applicationName ?? "").toString().trim();

    const firestore = admin.firestore();
    const clientRef = firestore
      .collection("Users")
      .doc(currentUserId)
      .collection("clients")
      .doc(deviceIdHash);

    try {
      await firestore.runTransaction(async (tx) => {
        const snap = await tx.get(clientRef);
        const now = admin.firestore.FieldValue.serverTimestamp();

        const baseData = {
          deviceIdHash,
          platform,
          deviceName,
          osName,
          osVersion,
          appVersion,
          buildCode,
          applicationName,
          lastSeenAt: now,
          updatedAt: now,
        };

        if (!snap.exists) {
          tx.set(clientRef, {
            ...baseData,
            firstSeenAt: now,
            createdAt: now,
          });
        } else {
          tx.set(clientRef, baseData, {merge: true});
        }
      });

      return {success: true};
    } catch (error) {
      console.error("❌ registerDevice error", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to register device"
      );
    }
  });

export const onUserStatusChange = functions.firestore
  .document("Users/{userId}")
  .onWrite(async (change, context) => {
    const userId = context.params.userId;
    const metrics = createExecutionMetrics({
      executionId: context.eventId,
    });
    console.log(`🔍 [onUserStatusChange] Triggered for user ${userId}`);

    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    if (!after) {
      console.log("ℹ️ [onUserStatusChange] Document deleted, skipping");
      metrics.done({userId, skipped: true, reason: "document_deleted"});
      return;
    }

    const beforeStatus = (before?.status ?? "").toString();
    const afterStatus = (after.status ?? "").toString();

    console.log(`📊 [onUserStatusChange] Status: "${beforeStatus}" → "${afterStatus}"`);

    if (beforeStatus === afterStatus) {
      console.log("ℹ️ [onUserStatusChange] Status unchanged, skipping");
      metrics.done({userId, skipped: true, reason: "status_unchanged"});
      return;
    }

    if (afterStatus !== "inactive") {
      console.log("ℹ️ [onUserStatusChange] Status is not \"inactive\", skipping");
      metrics.done({userId, skipped: true, reason: "status_not_inactive"});
      return;
    }

    console.log(`🚫 [onUserStatusChange] User ${userId} marked as inactive, blacklisting devices...`);
    const firestore = admin.firestore();

    try {
      const clientsSnapshot = await firestore
        .collection("Users")
        .doc(userId)
        .collection("clients")
        .get();
      metrics.addReads(clientsSnapshot.size);

      console.log(`📱 [onUserStatusChange] Found ${clientsSnapshot.size} clients for user ${userId}`);

      if (clientsSnapshot.empty) {
        console.log(
          `⚠️ [onUserStatusChange] No clients for user ${userId} - nothing to blacklist`
        );
        metrics.done({
          userId,
          beforeStatus,
          afterStatus,
          blacklistedCount: 0,
        });
        return;
      }

      const batch = firestore.batch();
      let blacklistedCount = 0;

      clientsSnapshot.docs.forEach((doc) => {
        const clientData = doc.data() || {};
        const deviceIdHash =
          (clientData.deviceIdHash ?? doc.id ?? "").toString().trim();

        console.log(`📱 [onUserStatusChange] Processing client: ${doc.id}, deviceIdHash: ${deviceIdHash}`);

        if (!deviceIdHash) {
          console.log("⚠️ [onUserStatusChange] Skipping client without deviceIdHash");
          return;
        }

        const blacklistRef = firestore
          .collection(BLACKLIST_COLLECTION)
          .doc(deviceIdHash);

        console.log(`🔒 [onUserStatusChange] Adding to blacklist: ${deviceIdHash}`);
        blacklistedCount++;

        batch.set(
          blacklistRef,
          {
            deviceIdHash,
            active: true,
            reason: "Sua conta foi desativada. Entre em contato com o suporte.",
            userId,
            platform: clientData.platform || "",
            deviceName: clientData.deviceName || "",
            osName: clientData.osName || "",
            osVersion: clientData.osVersion || "",
            appVersion: clientData.appVersion || "",
            buildCode: clientData.buildCode || "",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
      });

      await batch.commit();
      metrics.addWrites(blacklistedCount);

      console.log(
        `✅ [onUserStatusChange] Blacklist updated for user ${userId} - ${blacklistedCount} devices blacklisted`
      );
      metrics.done({
        userId,
        beforeStatus,
        afterStatus,
        blacklistedCount,
      });
    } catch (error) {
      console.error("❌ onUserStatusChange error", error);
      metrics.fail(error, {
        userId,
        beforeStatus,
        afterStatus,
      });
    }
  });
