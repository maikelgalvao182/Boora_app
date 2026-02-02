import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * 🔒 Migration: Move latitude/longitude real para subcoleção privada
 *
 * Esta função migra os campos latitude/longitude de Users/{userId}
 * para Users/{userId}/private/location
 *
 * Motivo de segurança:
 * - Localização real é dado sensível (pode revelar onde a pessoa mora)
 * - displayLatitude/displayLongitude (com offset ~1-3km) fica pública
 * - Cloud Functions podem acessar private/location via Admin SDK
 *
 * Execução:
 * - Chamar via HTTP: POST /migrateUserLocationToPrivate
 * - Ou executar script: node -e "require('./lib/users/migrateLocationToPrivate').migrateAll()"
 */

/**
 * HTTP Callable: Migra localizações de todos os usuários
 * POST /migrateUserLocationToPrivate?dryRun=true (para simular)
 * POST /migrateUserLocationToPrivate (para executar)
 */
export const migrateUserLocationToPrivate = functions
  .runWith({
    timeoutSeconds: 540, // 9 minutos
    memory: "512MB",
  })
  .https.onRequest(async (req, res) => {
    // Verificar autenticação básica (ou usar IAM em produção)
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({error: "Unauthorized - Bearer token required"});
      return;
    }

    const dryRun = req.query.dryRun === "true";
    console.log(`🚀 Starting migration (dryRun: ${dryRun})`);

    try {
      const result = await migrateAllLocations(dryRun);
      res.json(result);
    } catch (error) {
      console.error("❌ Migration failed:", error);
      res.status(500).json({error: String(error)});
    }
  });

/**
 * Trigger: Quando um usuário atualiza latitude/longitude no documento principal,
 * automaticamente copia para private/location
 *
 * Isso garante retrocompatibilidade durante a transição
 */
export const onUserLocationUpdateCopyToPrivate = functions.firestore
  .document("Users/{userId}")
  .onUpdate(async (change, context) => {
    const userId = context.params.userId;
    const before = change.before.data();
    const after = change.after.data();

    // Verificar se latitude ou longitude mudou no documento principal
    const latChanged = before.latitude !== after.latitude;
    const lngChanged = before.longitude !== after.longitude;

    if (!latChanged && !lngChanged) {
      return; // Nenhuma mudança em coordenadas
    }

    const latitude = after.latitude;
    const longitude = after.longitude;

    if (latitude === undefined || longitude === undefined) {
      return; // Sem coordenadas para copiar
    }

    console.log(`📍 Copying location to private for user ${userId}`);
    console.log(`   lat: ${latitude}, lng: ${longitude}`);

    try {
      await db
        .collection("Users")
        .doc(userId)
        .collection("private")
        .doc("location")
        .set(
          {
            latitude,
            longitude,
            migratedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
      console.log(`✅ Location copied to private for ${userId}`);
    } catch (error) {
      console.error(`❌ Failed to copy location for ${userId}:`, error);
    }
  });

/**
 * Função de migração em lote
 * @param {boolean} dryRun - Se true, apenas simula sem escrever
 * @return {Promise<object>} Estatísticas da migração
 */
async function migrateAllLocations(dryRun: boolean) {
  const stats = {
    total: 0,
    migrated: 0,
    skipped: 0,
    errors: 0,
    dryRun,
  };

  const batchSize = 500;
  let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;

  while (true) {
    let query = db
      .collection("Users")
      .orderBy("__name__")
      .limit(batchSize);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }

    const batch = db.batch();
    let batchCount = 0;

    for (const doc of snapshot.docs) {
      stats.total++;
      const data = doc.data();

      // Verificar se tem coordenadas
      const latitude = data.latitude;
      const longitude = data.longitude;

      if (latitude === undefined || longitude === undefined) {
        stats.skipped++;
        continue;
      }

      // Verificar se já foi migrado
      const privateLocationRef = doc.ref.collection("private").doc("location");
      const existingPrivate = await privateLocationRef.get();

      if (existingPrivate.exists) {
        const existingData = existingPrivate.data();
        if (
          existingData?.latitude === latitude &&
          existingData?.longitude === longitude
        ) {
          stats.skipped++;
          continue;
        }
      }

      if (!dryRun) {
        batch.set(
          privateLocationRef,
          {
            latitude,
            longitude,
            migratedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
        batchCount++;
      }

      stats.migrated++;
    }

    if (!dryRun && batchCount > 0) {
      await batch.commit();
      console.log(`✅ Batch committed: ${batchCount} locations`);
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    console.log(`📊 Progress: ${stats.total} processed, ${stats.migrated} migrated`);
  }

  console.log("🏁 Migration complete:", stats);
  return stats;
}

/**
 * Função exportada para execução via script
 * @param {boolean} dryRun - Se true, apenas simula sem escrever
 * @return {Promise<object>} Estatísticas da migração
 */
export async function migrateAll(dryRun = false) {
  return migrateAllLocations(dryRun);
}
