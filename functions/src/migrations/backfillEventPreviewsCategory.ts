import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * Backfill para adicionar campo `category` em events_card_preview
 *
 * Busca category do documento original em `events` e copia
 * para `events_card_preview` para permitir filtros de categoria no mapa.
 *
 * Chamar via:
 * curl -X POST "https://us-central1-partiu-479902.cloudfunctions.net/backfillEventPreviewsCategory" \
 *   -H "Content-Type: application/json" \
 *   -d '{"data":{"limit":500}}'
 */
export const backfillEventPreviewsCategory = functions
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .https.onCall(async (data: {limit?: number; cursor?: string}) => {
    const limit = Math.min(data.limit || 500, 500);
    const cursor = data.cursor || null;

    console.log(`🚀 [backfillCategory] Start limit=${limit} cursor=${cursor}`);

    const stats = {updated: 0, scanned: 0, skipped: 0, errors: 0};

    try {
      let query = db.collection("events_card_preview")
        .orderBy("eventId")
        .limit(limit);

      if (cursor) {
        query = query.startAfter(cursor);
      }

      const snapshot = await query.get();

      if (snapshot.empty) {
        console.log("✅ [backfillCategory] Nenhum documento encontrado");
        return {...stats, nextCursor: null};
      }

      const batch = db.batch();
      let lastDocId: string | null = null;

      for (const doc of snapshot.docs) {
        stats.scanned++;
        lastDocId = doc.id;

        const previewData = doc.data();

        // Se já tem category, pula
        if (previewData.category != null &&
          typeof previewData.category === "string" &&
          previewData.category.trim().length > 0) {
          stats.skipped++;
          continue;
        }

        // Busca category do evento original
        try {
          const eventDoc = await db.collection("events").doc(doc.id).get();
          if (!eventDoc.exists) {
            stats.skipped++;
            continue;
          }

          const eventData = eventDoc.data();
          const category = eventData?.category as string | undefined;

          if (!category || category.trim().length === 0) {
            stats.skipped++;
            continue;
          }

          batch.update(doc.ref, {
            category: category.trim(),
          });

          stats.updated++;
          console.log(`📦 ${doc.id} → category=${category.trim()}`);
        } catch (e) {
          stats.errors++;
          console.error(`❌ ${doc.id}: ${e}`);
        }
      }

      if (stats.updated > 0) {
        await batch.commit();
        console.log(`✅ [backfillCategory] Batch committed: ${stats.updated} docs`);
      }

      const nextCursor = snapshot.size === limit ? lastDocId : null;

      console.log(`📊 [backfillCategory] scanned=${stats.scanned} updated=${stats.updated} ` +
        `skipped=${stats.skipped} errors=${stats.errors} nextCursor=${nextCursor}`);

      return {...stats, nextCursor};
    } catch (error) {
      console.error("💥 [backfillCategory] Fatal:", error);
      throw new functions.https.HttpsError("internal", `Backfill failed: ${error}`);
    }
  });
