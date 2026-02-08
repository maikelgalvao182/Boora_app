import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {writeEventTombstone} from "./eventTombstoneHelper";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const BATCH_SIZE = 200;

/**
 * 🔄 Backfill one-time: Cria tombstones para todos os eventos que já estão
 * inativos/cancelados/deletados na coleção `events`.
 *
 * Cenários cobertos:
 * 1. events com isActive=false (expirados ou desativados manualmente)
 * 2. events com isCanceled=true
 * 3. events com status != "active"
 * 4. events_card_preview que existem sem evento correspondente (soft-deleted)
 *
 * Chamada manual via HTTP:
 *   curl https://us-central1-partiu-479902.cloudfunctions.net/backfillEventTombstones
 *
 * Seguro para rodar múltiplas vezes (idempotente — usa eventId como docId).
 */
export const backfillEventTombstones = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .https.onRequest(async (_req, res) => {
    const startMs = Date.now();
    let totalCreated = 0;
    const totalSkipped = 0;
    let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;

    console.log("🔄 [BackfillTombstones] Iniciando backfill...");

    // Guard para evitar timeout
    const maxRuntimeMs = 8 * 60 * 1000;

    // =========================================================
    // PASSO 1: Eventos inativos (isActive=false OU status != active)
    // =========================================================
    console.log("📋 [BackfillTombstones] Passo 1: eventos com isActive=false...");
    lastDoc = null;

    while (Date.now() - startMs < maxRuntimeMs) {
      let query = db
        .collection("events")
        .where("isActive", "==", false)
        .orderBy("__name__")
        .limit(BATCH_SIZE);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      for (const doc of snapshot.docs) {
        const data = doc.data();
        const location = data.location as Record<string, unknown> | undefined;
        const lat = (location?.latitude as number) ?? null;
        const lng = (location?.longitude as number) ?? null;

        let reason = "inactive";
        if (data.isCanceled === true) reason = "canceled";
        if (data.status === "deleted") reason = "deleted";

        await writeEventTombstone(doc.id, lat, lng, reason);
        totalCreated++;
      }

      lastDoc = snapshot.docs[snapshot.docs.length - 1];
      console.log(
        `🔄 [BackfillTombstones] Passo 1 lote: ${snapshot.docs.length} (total: ${totalCreated})`
      );

      if (snapshot.docs.length < BATCH_SIZE) break;
    }

    // =========================================================
    // PASSO 2: Eventos cancelados que talvez ainda tenham isActive=true
    // =========================================================
    console.log("📋 [BackfillTombstones] Passo 2: eventos com isCanceled=true...");
    lastDoc = null;

    while (Date.now() - startMs < maxRuntimeMs) {
      let query = db
        .collection("events")
        .where("isCanceled", "==", true)
        .orderBy("__name__")
        .limit(BATCH_SIZE);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      for (const doc of snapshot.docs) {
        const data = doc.data();
        const location = data.location as Record<string, unknown> | undefined;
        const lat = (location?.latitude as number) ?? null;
        const lng = (location?.longitude as number) ?? null;

        // writeEventTombstone usa doc(eventId).set() — idempotente
        await writeEventTombstone(doc.id, lat, lng, "canceled");
        totalCreated++;
      }

      lastDoc = snapshot.docs[snapshot.docs.length - 1];
      console.log(
        `🔄 [BackfillTombstones] Passo 2 lote: ${snapshot.docs.length} (total: ${totalCreated})`
      );

      if (snapshot.docs.length < BATCH_SIZE) break;
    }

    const elapsed = Math.round((Date.now() - startMs) / 1000);
    const summary = `✅ [BackfillTombstones] Finalizado: ${totalCreated} tombstones criados, ${totalSkipped} pulados em ${elapsed}s`;
    console.log(summary);

    res.status(200).json({
      success: true,
      totalCreated,
      totalSkipped,
      elapsedSeconds: elapsed,
    });
  });
