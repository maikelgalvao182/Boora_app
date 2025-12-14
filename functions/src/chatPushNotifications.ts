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
  .document("Messages/{senderId}/{receiverId}/{messageId}")
  .onCreate(async (snap, context) => {
    const senderId = context.params.senderId;
    const receiverId = context.params.receiverId;
    const messageId = context.params.messageId;
    const messageData = snap.data();

    if (!messageData) {
      console.error("❌ [ChatPush] Mensagem sem dados:", messageId);
      return;
    }

    try {
      // Extrair dados da mensagem
      const messageText =
        messageData.message_text || messageData.message || "";
      const messageType =
        messageData.message_type || messageData.messageType || "text";
      const senderName =
        messageData.user_fullname || messageData.userFullname || "Alguém";
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
        userId: receiverId,
        type: "chat_event",
        title: "Nova mensagem",
        body: `${senderName}: ${messagePreview}`,
        data: {
          sub_type: "chat_message",
          senderId: senderId,
          senderName: senderName,
          messagePreview: messagePreview,
          messageType: messageType,
          timestamp: timestamp.toString(),
        },
      });
    } catch (error) {
      console.error("❌ [ChatPush] Erro ao enviar push:", error);
    }
  });

