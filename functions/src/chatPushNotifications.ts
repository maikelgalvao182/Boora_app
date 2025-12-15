/**
 * Cloud Functions: Push Notifications para Chat 1-1
 *
 * IMPORTANTE: Esta função envia APENAS notificações push (FCM).
 * NÃO salva na coleção Notifications (in-app).
 *
 * Monitora:
 * - Messages/{userId}/{partnerId}/{messageId} (chat 1-1)
 *
 * NOTA: Para mensagens de EventChat (grupo), veja eventChatNotifications.ts
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {sendPush} from "./services/pushDispatcher";

/**
 * Trigger: Mensagens 1-1
 * Path: Messages/{senderId}/{receiverId}/{messageId}
 *
 * Envia push notification para o receiverId quando uma nova mensagem é criada
 */
export const onPrivateMessageCreated = functions.firestore
  .document("Messages/{ownerId}/{partnerId}/{messageId}")
  .onCreate(async (snap, context) => {
    // ownerId: Dono da caixa de mensagens (quem recebe a cópia)
    // partnerId: A outra pessoa na conversa
    const ownerId = context.params.ownerId;
    const partnerId = context.params.partnerId;
    const messageId = context.params.messageId;
    const messageData = snap.data();

    console.log("🔍 [ChatPush] TRIGGER DISPARADO");
    console.log(
      "   Path: Messages/" + ownerId + "/" + partnerId + "/" + messageId
    );
    console.log("   Owner: " + ownerId + ", Partner: " + partnerId);

    if (!messageData) {
      console.error("❌ [ChatPush] Mensagem sem dados:", messageId);
      return;
    }

    try {
      const msgSenderId = messageData.sender_id;
      const msgReceiverId = messageData.receiver_id;

      console.log("🔍 [ChatPush] Dados da mensagem:");
      console.log("   sender_id: " + msgSenderId);
      console.log("   receiver_id: " + msgReceiverId);
      console.log("   ownerId: " + ownerId);
      console.log(
        "   Comparação: msgSenderId === ownerId? " +
        (msgSenderId === ownerId)
      );

      // 1. Verificar se é mensagem de saída (enviada pelo dono da caixa)
      // Se ownerId == msgSenderId, significa que o usuário enviou a mensagem.
      // Não devemos notificar o próprio remetente.
      if (msgSenderId === ownerId) {
        console.log(
          "🚫 [ChatPush] Mensagem de saída (Owner: " + ownerId + "). Ignorando."
        );
        return;
      }

      console.log(
        "✅ [ChatPush] Mensagem de entrada. " +
        "Enviando push para " + ownerId + "..."
      );

      // 2. É mensagem de entrada (enviada pelo partnerId para o ownerId)
      // Devemos notificar o ownerId.

      // Extrair dados da mensagem
      const messageText =
        messageData.message_text || messageData.message || "";
      const messageType =
        messageData.message_type || messageData.messageType || "text";

      // 3. Buscar nome do remetente
      // (FIX: Frontend não envia user_fullname na msg recebida)
      let senderName =
        messageData.user_fullname ||
        messageData.userFullname ||
        messageData.sender_name;

      if (!senderName || senderName === "Alguém") {
        try {
          const userDoc = await admin
            .firestore()
            .collection("Users")
            .doc(msgSenderId)
            .get();
          if (userDoc.exists) {
            senderName = userDoc.data()?.fullName;
          }
        } catch (e) {
          console.error("⚠️ [ChatPush] Erro ao buscar nome do sender:", e);
        }
      }

      senderName = senderName || "Alguém";

      const timestamp =
        messageData.timestamp || admin.firestore.FieldValue.serverTimestamp();

      // Preparar preview da mensagem
      let messagePreview = "";
      if (messageType === "image") {
        messagePreview = "📷 Imagem";
      } else {
        messagePreview = messageText.substring(0, 100);
      }

      await sendPush({
        userId: ownerId, // Notifica o dono da caixa (Destinatário)
        event: "chat_message",
        notification: {
          title: senderName,
          body: messagePreview,
        },
        data: {
          n_type: "chat_message",
          sub_type: "chat_message",
          senderId: msgSenderId,
          n_sender_name: senderName,
          senderName: senderName,
          n_message: messagePreview,
          messagePreview: messagePreview,
          messageType: messageType,
          timestamp: timestamp.toString(),
        },
      });

      console.log("✅ [ChatPush] Push enviado com sucesso para " + ownerId);
    } catch (error) {
      console.error("❌ [ChatPush] Erro ao enviar push:", error);
    }
  });

