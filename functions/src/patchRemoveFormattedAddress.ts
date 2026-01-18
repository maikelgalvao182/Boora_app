/**
 * Cloud Function: Patch para remover campo 'formattedAddress' em usuários
 *
 * Esta função pode ser chamada via Firebase Console ou CLI
 * para deletar o campo formattedAddress de todos os usuários.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

/**
 * Função HTTP callable para executar o patch
 *
 * Uso via curl:
 * curl -X POST https://REGION-PROJECT.cloudfunctions.net/patchRemoveFormattedAddress \
 *   -H "Content-Type: application/json" \
 *   -d '{"adminKey": "YOUR_SECRET_KEY"}'
 */
export const patchRemoveFormattedAddress = functions.https.onRequest(
  async (req, res) => {
    const adminKey = req.body?.adminKey || req.query?.adminKey;
    const expectedKey = functions.config().admin?.key || "patch-2025";

    if (adminKey !== expectedKey) {
      res.status(403).json({error: "Unauthorized"});
      return;
    }

    try {
      console.log("🧹 Iniciando patch: Removendo formattedAddress...");

      const db = admin.firestore();
      const BATCH_SIZE = 500;

      let totalUpdated = 0;
      let lastDoc: admin.firestore.QueryDocumentSnapshot | null = null;
      let hasMore = true;

      while (hasMore) {
        let query = db
          .collection("Users")
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(BATCH_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const snapshot = await query.get();

        if (snapshot.empty) {
          hasMore = false;
          break;
        }

        const batch = db.batch();
        let batchUpdateCount = 0;

        for (const userDoc of snapshot.docs) {
          const userData = userDoc.data();
          const hasField = Object.prototype.hasOwnProperty.call(
            userData,
            "formattedAddress",
          );

          if (hasField) {
            batch.update(userDoc.ref, {
              formattedAddress: admin.firestore.FieldValue.delete(),
            });
            batchUpdateCount++;
          }
        }

        if (batchUpdateCount > 0) {
          await batch.commit();
          totalUpdated += batchUpdateCount;
          console.log(`✅ Batch commitado: ${batchUpdateCount} usuários`);
        }

        lastDoc = snapshot.docs[snapshot.docs.length - 1];
        hasMore = snapshot.size === BATCH_SIZE;
      }

      const result = {
        success: true,
        totalUpdated: totalUpdated,
        message: `Patch concluído! ${totalUpdated} usuários atualizados.`,
      };

      console.log("✅", result.message);
      res.status(200).json(result);
    } catch (error) {
      console.error("❌ Erro ao executar patch:", error);
      res.status(500).json({
        success: false,
        error: String(error),
      });
    }
  }
);
