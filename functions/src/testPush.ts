import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
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
        event: "system_alert",
        origin: "testPushNotification",
        data: {
          n_type: "system_alert",
          relatedId: "test",
          n_related_id: "test",
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

/**
 * Função HTTP para testar push notification com tokens específicos
 *
 * Uso com tokens hardcoded:
 * curl "https://us-central1-partiu-479902.cloudfunctions.net/testPushWithToken?useHardcoded=true"
 *
 * Uso com token customizado:
 * curl -X POST "https://us-central1-partiu-479902.cloudfunctions.net/testPushWithToken" \
 *   -H "Content-Type: application/json" \
 *   -d '{"token": "seu-token-aqui", "title": "Test", "body": "Test message"}'
 */
export const testPushWithToken = functions.https.onRequest(
  async (req, res) => {
    // Tokens hardcoded para teste
    const HARDCODED_TOKENS = [
      "fPWZo72uRUKZlq605N09RJ:APA91bG8SlCyegaKPsbuNcPTmF5rqMaQmn" +
      "9pH_xvQhVnWcVg4A3_iUfXOPn1R36U4262jVMQchRiBmoSN-RAwLwu5_" +
      "soAIjYP46buD0cOzJfuFu43JWZvfs",
      "cLJhgrIscUsWqdes_VMLbH:APA91bFpetgPwwNE_baB8oZWDP5dre7GrS" +
      "WyRUerd2GZqhpvtfdpvn6cfZ8UoogSVskeDoXls--5hsEayBUZJUQOiqc" +
      "lwY0AaYCkEX9hfrVIooRp_wpPv88",
    ];

    try {
      const useHardcoded = req.query.useHardcoded === "true" ||
                          req.query.useHardcoded === "1";

      let tokens: string[] = [];
      let title = "🧪 Teste de Push";
      let body = "Se você recebeu isso, o sistema FCM está funcionando!";

      if (useHardcoded) {
        console.log("🔧 [TestPushWithToken] Usando tokens hardcoded");
        tokens = HARDCODED_TOKENS;
      } else {
        // Tentar pegar do body ou query
        const bodyData = req.body || {};
        const token = bodyData.token || req.query.token as string;

        if (!token) {
          res.status(400).json({
            error: "Missing token parameter",
            usage: {
              hardcoded: "?useHardcoded=true",
              custom: "POST with JSON body: {\"token\": \"...\", " +
                "\"title\": \"...\", \"body\": \"...\"}",
            },
          });
          return;
        }

        tokens = [token];
        title = bodyData.title || title;
        body = bodyData.body || body;
      }

      console.log(`🧪 [TestPushWithToken] Testando ${tokens.length} token(s)`);
      console.log(`📝 [TestPushWithToken] Title: ${title}`);
      console.log(`📝 [TestPushWithToken] Body: ${body}`);

      // Preparar payload FCM
      const payload = {
        notification: {
          title,
          body,
        },
        data: {
          "type": "test",
          "timestamp": new Date().toISOString(),
          "click_action": "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high" as const,
          notification: {
            sound: "default",
            priority: "high" as const,
            channelId: "partiu_high_importance",
          },
        },
        apns: {
          payload: {
            aps: {
              "alert": {
                title,
                body,
              },
              "sound": "default",
              // badge: NÃO ENVIAR - Flutter controla via BadgeService
              "content-available": 1,
            },
          },
        },
      };

      console.log("🚀 [TestPushWithToken] Enviando via FCM...");

      const response = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        ...payload,
      });

      console.log("✅ [TestPushWithToken] Resposta do FCM:");
      console.log(`   - Success count: ${response.successCount}`);
      console.log(`   - Failure count: ${response.failureCount}`);

      // Analisar resultados individuais
      const results = response.responses.map((resp, idx) => {
        const token = tokens[idx];
        const tokenLen = token.length;
        const tokenPreview =
          `${token.substring(0, 20)}...${token.substring(tokenLen - 10)}`;

        if (resp.success) {
          console.log(`   ✅ Token ${idx + 1}: SUCCESS`);
          console.log(`      - Token: ${tokenPreview}`);
          console.log(`      - Message ID: ${resp.messageId}`);
          return {
            index: idx + 1,
            token: tokenPreview,
            success: true,
            messageId: resp.messageId,
          };
        } else {
          const error = resp.error;
          console.log(`   ❌ Token ${idx + 1}: FAILED`);
          console.log(`      - Token: ${tokenPreview}`);
          console.log(`      - Error code: ${error?.code}`);
          console.log(`      - Error message: ${error?.message}`);

          return {
            index: idx + 1,
            token: tokenPreview,
            success: false,
            error: {
              code: error?.code,
              message: error?.message,
            },
          };
        }
      });

      res.status(200).json({
        success: true,
        summary: {
          totalTokens: tokens.length,
          successCount: response.successCount,
          failureCount: response.failureCount,
        },
        results: results,
        payload: {
          title,
          body,
          data: payload.data,
        },
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      console.error("❌ [TestPushWithToken] Erro:", error);
      res.status(500).json({
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
        stack: error instanceof Error ? error.stack : undefined,
      });
    }
  }
);
