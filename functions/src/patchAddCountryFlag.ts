/**
 * Cloud Function: Patch para adicionar campos 'from' e 'flag' em usuários
 *
 * Esta função pode ser chamada via Firebase Console ou CLI
 * para adicionar os campos de país e bandeira em todos os usuários
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

/**
 * Função HTTP callable para executar o patch
 *
 * Uso via curl:
 * curl -X POST https://REGION-PROJECT.cloudfunctions.net/patchAddCountryFlag \
 *   -H "Content-Type: application/json" \
 *   -d '{"adminKey": "YOUR_SECRET_KEY"}'
 */
export const patchAddCountryFlag = functions.https.onRequest(
  async (req, res) => {
    // Validação básica de segurança (opcional)
    const adminKey = req.body?.adminKey || req.query?.adminKey;
    const expectedKey = functions.config().admin?.key || "patch-2025";

    if (adminKey !== expectedKey) {
      res.status(403).json({error: "Unauthorized"});
      return;
    }

    try {
      console.log("🚀 Iniciando patch: Adicionando campos from e flag...");

      const db = admin.firestore();
      const BATCH_SIZE = 500;
      const DEFAULT_COUNTRY = "Brasil";
      const DEFAULT_FLAG = "🇧🇷";

      let totalUpdated = 0;

      const allDocs = await db.collection("Users").listDocuments();
      console.log(`📦 Total de documentos encontrados: ${allDocs.length}`);

      for (let i = 0; i < allDocs.length; i += BATCH_SIZE) {
        const chunk = allDocs.slice(i, i + BATCH_SIZE);
        const batch = db.batch();

        for (const docRef of chunk) {
          batch.update(docRef, {
            from: DEFAULT_COUNTRY,
            flag: DEFAULT_FLAG,
          });
        }

        await batch.commit();
        totalUpdated += chunk.length;
        console.log(`✅ Batch commitado: ${chunk.length} usuários`);
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
