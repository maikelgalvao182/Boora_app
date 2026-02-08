import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

const BATCH_SIZE = 500;
const RETENTION_DAYS = 14;

/**
 * 🧹 Cloud Function scheduled: Remove tombstones antigos da coleção
 * `event_tombstones` para evitar crescimento infinito.
 *
 * Política:
 * - Deleta docs onde `deletedAt` < (agora - 14 dias)
 * - Paginação por `deletedAt` para não estourar memória
 * - Roda diariamente às 04:00 (BRT)
 *
 * Tombstones mais antigos que 14 dias são irrelevantes porque:
 * - O cache local do app tem TTL de 2–10 minutos
 * - Após reiniciar o app, o polling busca apenas os últimos 10 minutos
 * - 14 dias é margem mais do que suficiente
 */
export const cleanupOldTombstones = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 300, memory: "256MB"})
  .pubsub.schedule("0 4 * * *")
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const startMs = Date.now();
    const cutoffDate = new Date(
      Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000
    );
    const cutoff = admin.firestore.Timestamp.fromDate(cutoffDate);

    console.log(
      `🧹 [cleanupOldTombstones] Iniciando limpeza: deletedAt < ${cutoffDate.toISOString()} (retenção ${RETENTION_DAYS}d)`
    );

    let totalDeleted = 0;
    let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;

    // Guard para evitar timeout (margem dentro de 300s)
    const maxRuntimeMs = 4 * 60 * 1000;

    while (Date.now() - startMs < maxRuntimeMs) {
      let query = db
        .collection("event_tombstones")
        .where("deletedAt", "<", cutoff)
        .orderBy("deletedAt")
        .limit(BATCH_SIZE);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();

      totalDeleted += snapshot.docs.length;
      lastDoc = snapshot.docs[snapshot.docs.length - 1];

      console.log(
        `🧹 [cleanupOldTombstones] Lote: ${snapshot.docs.length} docs deletados (total: ${totalDeleted})`
      );

      // Se pegou menos que o batch, acabou
      if (snapshot.docs.length < BATCH_SIZE) break;
    }

    console.log(
      `✅ [cleanupOldTombstones] Finalizado: ${totalDeleted} tombstones removidos em ${Math.round((Date.now() - startMs) / 1000)}s`
    );

    return null;
  });
