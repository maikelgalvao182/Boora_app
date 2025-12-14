import * as functions from "firebase-functions";
import {sendPush} from "./services/pushDispatcher";

/**
 * Função HTTP para testar push notifications diretamente
 *
 * Uso:
 * ```bash
 * curl "https://us-central1-partiu-479902.cloudfunctions.net/testPushNotification?userId=USER_ID"
 * ```
 */
export const testPushNotification = functions.https.onRequest(
  async (req, res) => {
    const userId = req.query.userId as string;

    if (!userId) {
      res.status(400).json({
        error: "Missing userId query parameter",
        usage: "?userId=USER_ID",
      });
      return;
    }

    try {
      console.log(`🧪 [TestPush] Enviando push de teste para: ${userId}`);

      await sendPush({
        userId: userId,
        type: "global",
        title: "🧪 Teste de Push",
        body: "Se você recebeu isso, o sistema está funcionando!",
        data: {
          test: "true",
          timestamp: new Date().toISOString(),
        },
      });

      res.status(200).json({
        success: true,
        message: `Push notification enviado para ${userId}`,
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      console.error("❌ [TestPush] Erro:", error);
      res.status(500).json({
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
      });
    }
  }
);
