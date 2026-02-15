import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

const BATCH_SIZE = 500;

/**
 * Cloud Function: Gera filtros agregados de ranking (estados/cidades)
 *
 * Saída:
 * - ranking_filters/current
 *   - states: string[]
 *   - cities: string[]
 *   - citiesByState: { [state]: string[] }
 *   - updatedAt: timestamp
 *   - ttlSeconds: number
 */
export const syncRankingFilters = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .pubsub.schedule("every day 03:00") // Reduzido de "every 30 minutes" — dados de ranking mudam pouco
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const startMs = Date.now();

    const statesSet = new Set<string>();
    const citiesSet = new Set<string>();
    const citiesByState = new Map<string, Set<string>>();

    let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;
    let totalProcessed = 0;

    while (true) {
      let query = db
        .collection("users_preview")
        .orderBy(admin.firestore.FieldPath.documentId())
        .select("state", "locality")
        .limit(BATCH_SIZE);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      lastDoc = snapshot.docs[snapshot.docs.length - 1];
      totalProcessed += snapshot.size;

      for (const doc of snapshot.docs) {
        const data = doc.data();
        const state = (data.state as string | undefined)?.trim();
        const city = (data.locality as string | undefined)?.trim();

        if (state && state.length > 0) {
          statesSet.add(state);
          if (!citiesByState.has(state)) {
            citiesByState.set(state, new Set());
          }
        }

        if (city && city.length > 0) {
          citiesSet.add(city);
          if (state && state.length > 0) {
            citiesByState.get(state)?.add(city);
          }
        }
      }

      if (snapshot.size < BATCH_SIZE) break;
    }

    const states = Array.from(statesSet).sort();
    const cities = Array.from(citiesSet).sort();

    const citiesByStateObj: Record<string, string[]> = {};
    for (const [state, citiesSetForState] of citiesByState.entries()) {
      citiesByStateObj[state] = Array.from(citiesSetForState).sort();
    }

    await db
      .collection("ranking_filters")
      .doc("current")
      .set(
        {
          states,
          cities,
          citiesByState: citiesByStateObj,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          ttlSeconds: 1800,
        },
        {merge: true}
      );

    const durationMs = Date.now() - startMs;
    console.log(
      `✅ [syncRankingFilters] Processed ${totalProcessed} users in ${Math.round(
        durationMs / 1000
      )}s (states: ${states.length}, cities: ${cities.length})`
    );

    return {
      success: true,
      processed: totalProcessed,
      states: states.length,
      cities: cities.length,
      durationMs,
    };
  });
