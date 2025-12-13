/**
 * 🔒 WEBHOOK REVENUECAT → FIRESTORE
 *
 * Responsabilidade ÚNICA: manter Firestore sincronizado com RevenueCat
 *
 * Campo no Firestore:
 * - vipExpiresAt: Timestamp | null
 *
 * Segurança:
 * - Valida Bearer token do RevenueCat
 * - Atualiza apenas Users/{userId}
 */

import * as functions from "firebase-functions/v2";
import * as admin from "firebase-admin";

interface RevenueCatWebhookEvent {
  type: string;
  app_user_id: string;
  expiration_at_ms?: number;
  product_id?: string;
  entitlement_ids?: string[];
}

/**
 * Webhook do RevenueCat
 *
 * Setup no RevenueCat Dashboard:
 * 1. Project Settings → Integrations → Webhooks
 * 2. URL: https://us-central1-YOUR_PROJECT.cloudfunctions.net/revenueCatWebhook
 * 3. Authorization: Bearer YOUR_SECRET
 * 4. Events: INITIAL_PURCHASE, RENEWAL, EXPIRATION, CANCELLATION
 *
 * Secret no Firebase:
 * firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
 */
export const revenueCatWebhook = functions.https.onRequest(
  {
    region: "us-central1",
    secrets: ["REVENUECAT_WEBHOOK_SECRET"],
  },
  async (req, res) => {
    // 🔒 Validação de segurança
    const authHeader = req.headers.authorization;
    const expectedSecret = process.env.REVENUECAT_WEBHOOK_SECRET;

    if (!authHeader || authHeader !== `Bearer ${expectedSecret}`) {
      console.error("❌ Webhook não autorizado");
      res.status(401).send("Unauthorized");
      return;
    }

    const event = req.body as RevenueCatWebhookEvent;
    const userId = event.app_user_id;

    if (!userId) {
      console.error("❌ Webhook sem app_user_id");
      res.status(400).send("Missing app_user_id");
      return;
    }

    console.log(`📥 RevenueCat: ${event.type} → ${userId}`);

    try {
      const db = admin.firestore();
      const userRef = db.collection("Users").doc(userId);

      // Verifica se usuário existe
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        console.warn(`⚠️ Usuário ${userId} não existe no Firestore`);
        res.status(404).send("User not found");
        return;
      }

      switch (event.type) {
      case "INITIAL_PURCHASE":
      case "RENEWAL":
      case "UNCANCELLATION": {
        // ✅ Ativa VIP com data de expiração
        await userRef.update({
          vipExpiresAt: event.expiration_at_ms ?
            admin.firestore.Timestamp.fromMillis(event.expiration_at_ms) :
            null,
          vipProductId: event.product_id || null,
          vipUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        const expiryDate = new Date(event.expiration_at_ms || 0);
        console.log(`✅ ${userId} → VIP até ${expiryDate}`);
        break;
      }

      case "EXPIRATION":
        // ❌ Remove VIP
        await userRef.update({
          vipExpiresAt: null,
          vipUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`❌ ${userId} → VIP expirado`);
        break;

      case "CANCELLATION":
        // ⚠️ Cancelado, mas ainda tem acesso até expirar
        // Não remove vipExpiresAt
        console.log(`⚠️ ${userId} → VIP cancelado (acesso até expiração)`);
        break;

      default:
        console.log(`ℹ️ Evento ${event.type} ignorado`);
      }

      res.status(200).send("OK");
    } catch (error) {
      console.error("❌ Erro ao processar webhook:", error);
      res.status(500).send("Internal Server Error");
    }
  }
);
