import * as admin from "firebase-admin";

export type PushType = "global" | "chat_event";

interface SendPushParams {
  userId: string;
  type: PushType;
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * Sends a push notification to a user
 * @param {SendPushParams} params - The push notification parameters
 */
export async function sendPush({
  userId,
  type,
  title,
  body,
  data,
}: SendPushParams): Promise<void> {
  try {
    console.log("🔥 [PushDispatcher] sendPush CALLED");
    console.log(`   - userId: ${userId}`);
    console.log(`   - type: ${type}`);
    console.log(`   - title: ${title}`);
    console.log(`   - body: ${body}`);

    // 1. Buscar usuário para verificar preferências
    const userDoc = await admin
      .firestore()
      .collection("Users")
      .doc(userId)
      .get();

    if (!userDoc.exists) {
      console.warn(`⚠️ [PushDispatcher] Usuário não encontrado: ${userId}`);
      return;
    }

    const userData = userDoc.data();

    // 2. Verificar preferências
    // Caminho: advancedSettings.push_preferences.{type}
    // Default: true (se não existir)
    const preferences = userData?.advancedSettings?.push_preferences;
    const isEnabled = preferences?.[type] ?? true;

    if (isEnabled === false) {
      console.log(
        "🔕 [PushDispatcher] Push bloqueado por preferência " +
        `do usuário. Type: ${type}, UserId: ${userId}`
      );
      return;
    }

    // 3. Buscar tokens FCM
    console.log(
      `🔍 [PushDispatcher] Buscando tokens para userId: ${userId}`
    );
    console.log("📍 [PushDispatcher] Collection: DeviceTokens");
    console.log(
      `🔎 [PushDispatcher] Query: where("userId", "==", "${userId}")`
    );

    const tokensSnapshot = await admin
      .firestore()
      .collection("DeviceTokens")
      .where("userId", "==", userId)
      .get();

    console.log(
      `📊 [PushDispatcher] Tokens encontrados: ${tokensSnapshot.size}`
    );

    if (tokensSnapshot.empty) {
      console.log(`ℹ️ [PushDispatcher] Usuário sem tokens FCM: ${userId}`);

      // DEBUG: Listar TODOS os documentos da coleção para diagnóstico
      const allTokens = await admin
        .firestore()
        .collection("DeviceTokens")
        .limit(5)
        .get();

      console.log(
        `🔍 [PushDispatcher] DEBUG - Total na coleção: ${allTokens.size}`
      );
      allTokens.docs.forEach((doc) => {
        const data = doc.data();
        console.log(`  📄 Token doc: ${doc.id}`);
        console.log(`     - userId: ${data.userId}`);
        console.log(`     - token: ${data.token?.substring(0, 20)}...`);
      });

      return;
    }

    const fcmTokens: string[] = [];
    const tokenDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];

    tokensSnapshot.docs.forEach((doc) => {
      const token = doc.data().token;
      if (token && token.length > 0) {
        fcmTokens.push(token);
        tokenDocs.push(doc);
      }
    });

    if (fcmTokens.length === 0) {
      console.log(`ℹ️ [PushDispatcher] Usuário sem tokens válidos: ${userId}`);
      return;
    }

    console.log(
      `🚀 [PushDispatcher] Enviando push (${type}) para ` +
      `${fcmTokens.length} dispositivo(s). User: ${userId}`
    );

    // 4. Enviar push
    const payload = {
      notification: {
        title,
        body,
      },
      data: {
        type,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        ...data,
      },
      android: {
        priority: "high" as const,
        notification: {
          sound: "default",
          priority: "high" as const,
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
            "badge": 1,
            "content-available": 1,
          },
        },
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
      },
    };

    console.log("📦 [PushDispatcher] Payload APNS:");
    console.log(JSON.stringify(payload.apns, null, 2));

    const response = await admin.messaging().sendEachForMulticast({
      tokens: fcmTokens,
      notification: payload.notification,
      data: payload.data,
      android: payload.android,
      apns: payload.apns,
    });

    console.log(
      `✅ [PushDispatcher] Resultado: ${response.successCount} ` +
      `sucessos, ${response.failureCount} falhas`
    );

    // 5. Limpar tokens inválidos
    if (response.failureCount > 0) {
      const batch = admin.firestore().batch();
      let deletedCount = 0;

      response.responses.forEach((result, index) => {
        if (!result.success && result.error) {
          const errorCode = result.error.code;
          if (
            errorCode === "messaging/invalid-registration-token" ||
            errorCode === "messaging/registration-token-not-registered"
          ) {
            const tokenDoc = tokenDocs[index];
            batch.delete(tokenDoc.ref);
            deletedCount++;
          }
        }
      });

      if (deletedCount > 0) {
        console.warn(
          `⚠️ [PushDispatcher] Removendo ${deletedCount} ` +
          "tokens inválidos"
        );
        await batch.commit();
      }
    }

    // 6. Salvar histórico (opcional, conforme sugestão)
    // await admin.firestore().collection("PushHistory").add({
    //   userId,
    //   type,
    //   title,
    //   body,
    //   data,
    //   createdAt: admin.firestore.FieldValue.serverTimestamp(),
    //   successCount: response.successCount,
    // });
  } catch (error) {
    console.error("❌ [PushDispatcher] Erro fatal:", error);
  }
}
