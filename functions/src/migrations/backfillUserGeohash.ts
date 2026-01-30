import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {encodeGeohash} from "../utils/geohash";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

export const backfillUserGeohash = functions
  .runWith({
    timeoutSeconds: 540,
    memory: "1GB",
  })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed. Use POST.");
      return;
    }

    const limit = Math.min(Number(req.body?.limit ?? 500), 1000);
    const startAfter = String(req.body?.startAfter ?? "").trim();

    try {
      let query = db.collection("Users")
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(limit);

      if (startAfter) {
        query = query.startAfter(startAfter);
      }

      const snapshot = await query.get();
      if (snapshot.empty) {
        res.status(200).json({
          updated: 0,
          scanned: 0,
          nextCursor: null,
        });
        return;
      }

      const batch = db.batch();
      let updates = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data() || {};
        const lat = data.latitude;
        const lng = data.longitude;
        const currentGeohash = typeof data.geohash === "string" ? data.geohash : "";

        if (typeof lat !== "number" || typeof lng !== "number") {
          continue;
        }

        const nextGeohash = encodeGeohash(lat, lng, 7);
        if (!nextGeohash || nextGeohash == currentGeohash) {
          continue;
        }

        batch.update(doc.ref, {geohash: nextGeohash});
        batch.set(
          db.collection("users_preview").doc(doc.id),
          {geohash: nextGeohash},
          {merge: true}
        );
        updates++;
      }

      if (updates > 0) {
        await batch.commit();
      }

      const lastDoc = snapshot.docs[snapshot.docs.length - 1];
      res.status(200).json({
        updated: updates,
        scanned: snapshot.size,
        nextCursor: lastDoc.id,
      });
    } catch (error) {
      console.error("❌ [backfillUserGeohash] Error:", error);
      res.status(500).send("Internal error");
    }
  });
