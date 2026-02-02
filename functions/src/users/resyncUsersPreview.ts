import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * 🔄 Cloud Function: Resincroniza todos os Users → users_preview
 *
 * Uso único para corrigir dados existentes após mudanças na lógica de sync.
 * Pode ser chamada via HTTP: POST /resyncUsersPreview
 *
 * ⚠️ ATENÇÃO: Executar apenas quando necessário (custo de leitura/escrita)
 */
export const resyncUsersPreview = functions
  .runWith({
    timeoutSeconds: 540, // 9 minutos (máximo para HTTP functions)
    memory: "512MB",
  })
  .https.onRequest(async (req, res) => {
    // Apenas POST para evitar execução acidental
    if (req.method !== "POST") {
      res.status(405).send("Method not allowed. Use POST.");
      return;
    }

    console.log("🔄 Iniciando resync de Users → users_preview...");

    const stats = {
      total: 0,
      updated: 0,
      errors: 0,
      skipped: 0,
    };

    try {
      // Buscar todos os usuários em batches de 500
      const batchSize = 500;
      let lastDoc: admin.firestore.DocumentSnapshot | null = null;
      let hasMore = true;

      while (hasMore) {
        let query = db.collection("Users").limit(batchSize);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const snapshot = await query.get();

        if (snapshot.empty) {
          hasMore = false;
          break;
        }

        // Processar batch
        const batch = db.batch();
        let batchCount = 0;

        for (const doc of snapshot.docs) {
          stats.total++;
          const userData = doc.data();
          const userId = doc.id;

          if (!userData) {
            stats.skipped++;
            continue;
          }

          try {
            const fullName = userData.fullName || userData.displayName || null;
            const username = userData.username || userData.userName || null;
            const photoUrl = userData.photoUrl || userData.profilePhoto || null;
            const avatarThumbUrl =
              userData.avatarThumbUrl || userData.photoThumbUrl || null;

            // ✅ CORREÇÃO: Incluir user_is_verified
            const isVerified = Boolean(
              userData.user_is_verified ||
              userData.isVerified ||
              userData.verified
            );
            const isVip = Boolean(
              userData.user_is_vip ||
              userData.isVip ||
              userData.vip
            );

            const previewData = {
              userId,
              fullName,
              displayName: fullName,
              username,
              photoUrl,
              avatarThumbUrl,
              isVerified,
              isVip,
              locality: userData.locality || null,
              state: userData.state || null,
              country: userData.country || null,
              flag: userData.flag || null,
              overallRating: userData.overallRating || 0,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };

            const previewRef = db.collection("users_preview").doc(userId);
            batch.set(previewRef, previewData, {merge: true});
            batchCount++;
            stats.updated++;

            // Log para usuários verificados
            if (isVerified) {
              console.log(`✅ Verified user synced: ${userId}`);
            }
          } catch (error) {
            console.error(`❌ Error processing user ${userId}:`, error);
            stats.errors++;
          }
        }

        // Commit batch
        if (batchCount > 0) {
          await batch.commit();
          console.log(`📦 Batch committed: ${batchCount} users`);
        }

        // Preparar próximo batch
        lastDoc = snapshot.docs[snapshot.docs.length - 1];
        hasMore = snapshot.docs.length === batchSize;

        // Pequeno delay para evitar rate limiting
        await new Promise((resolve) => setTimeout(resolve, 100));
      }

      const message = `✅ Resync completo! Total: ${stats.total}, Updated: ${stats.updated}, Errors: ${stats.errors}, Skipped: ${stats.skipped}`;
      console.log(message);
      res.status(200).json({
        success: true,
        message,
        stats,
      });
    } catch (error) {
      console.error("❌ Erro fatal no resync:", error);
      res.status(500).json({
        success: false,
        error: String(error),
        stats,
      });
    }
  });
