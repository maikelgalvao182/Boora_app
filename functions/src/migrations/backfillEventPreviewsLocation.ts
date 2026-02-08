import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * Backfill para adicionar coordenadas de localização em events_card_preview
 *
 * Busca os dados de location do documento original em `events` e copia
 * para `events_card_preview` para permitir queries de bounding box.
 *
 * Chamar via:
 * curl -X POST "https://us-central1-PROJECT.cloudfunctions.net/backfillEventPreviewsLocation" \
 *   -H "Content-Type: application/json" \
 *   -d '{"data":{"limit":500}}'
 */
export const backfillEventPreviewsLocation = functions
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .https.onCall(async (data: {limit?: number; cursor?: string}) => {
    const limit = Math.min(data.limit || 500, 500);
    const cursor = data.cursor || null;

    console.log(`🚀 [backfillEventPreviewsLocation] Start limit=${limit} cursor=${cursor}`);

    const stats = {updated: 0, scanned: 0, skipped: 0, errors: 0};

    try {
      // Query events_card_preview que não têm location.latitude
      let query = db.collection("events_card_preview")
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(limit);

      if (cursor) {
        query = query.startAfter(cursor);
      }

      const snapshot = await query.get();

      if (snapshot.empty) {
        console.log("✅ [backfillEventPreviewsLocation] Nenhum documento encontrado");
        return {...stats, nextCursor: null};
      }

      const batch = db.batch();
      let lastDocId: string | null = null;

      for (const doc of snapshot.docs) {
        stats.scanned++;
        lastDocId = doc.id;

        const previewData = doc.data() || {};

        // Já tem location com latitude? Pular
        const existingLocation = previewData.location;
        if (existingLocation && typeof existingLocation === "object" &&
            existingLocation.latitude != null && existingLocation.longitude != null) {
          stats.skipped++;
          continue;
        }

        // Buscar dados de location do evento original
        try {
          const eventDoc = await db.collection("events").doc(doc.id).get();
          if (!eventDoc.exists) {
            stats.skipped++;
            continue;
          }

          const eventData = eventDoc.data() || {};
          const location = eventData.location as Record<string, unknown> | undefined;

          if (!location) {
            stats.skipped++;
            continue;
          }

          const lat = location.latitude as number | undefined;
          const lng = location.longitude as number | undefined;

          if (lat == null || lng == null) {
            stats.skipped++;
            continue;
          }

          batch.update(doc.ref, {
            location: {
              latitude: lat,
              longitude: lng,
            },
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          stats.updated++;
        } catch (error) {
          console.error(`❌ Erro ao processar ${doc.id}:`, error);
          stats.errors++;
        }
      }

      if (stats.updated > 0) {
        await batch.commit();
        console.log(`✅ [backfillEventPreviewsLocation] Batch committed: ${stats.updated} updates`);
      }

      return {
        ...stats,
        nextCursor: lastDocId,
      };
    } catch (error) {
      console.error("❌ [backfillEventPreviewsLocation] Error:", error);
      throw new functions.https.HttpsError("internal", String(error));
    }
  });
