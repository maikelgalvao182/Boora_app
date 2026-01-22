/**
 * Cloud Functions: Notificações de EventChat
 *
 * Trigger que monitora mensagens criadas em EventChats/{eventId}/Messages
 * e:
 * 1. Cria notificações in-app na coleção Notifications
 * 2. Dispara push notification via PushDispatcher
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {sendPush} from "./services/pushDispatcher";

/**
 * Trigger: Quando uma mensagem é criada em EventChats/{eventId}/Messages
 * Cria notificações para todos os participantes (exceto remetente)
 */
export const onEventChatMessageCreated = functions.firestore
  .document("EventChats/{eventId}/Messages/{messageId}")
  .onCreate(async (snap, context) => {
    const eventId = context.params.eventId;
    const messageId = context.params.messageId;
    const messageData = snap.data();

    if (!messageData) {
      console.error("❌ Mensagem sem dados:", messageId);
      return;
    }

    try {
      const senderId = messageData.sender_id || messageData.senderId;
      const messageText =
        messageData.message_text || messageData.message;
      const messageType =
        messageData.message_type || messageData.messageType;
      const senderName =
        messageData.sender_name || messageData.senderName || "Usuário";

      console.log(
        `📬 [EventChatNotification] Nova mensagem no evento ${eventId} (v2)`
      );
      console.log(`   Remetente: ${senderName} (${senderId})`);
      console.log(`   Tipo: ${messageType}`);
      console.log(`   Mensagem: ${messageText}`);

      // Ignorar mensagens do sistema e de entrada (não geram notificações)
      // event_join já é notificado pelo index.ts via activity_new_participant
      const isSystemMessage = messageType === "system" ||
        messageType === "event_join" ||
        senderId === "system";

      if (isSystemMessage) {
        console.log(
          "⏭️ Mensagem do sistema/entrada - não criar notificação"
        );
        return;
      }

      // Buscar dados do evento para obter participantes e título
      const eventChatDoc = await admin
        .firestore()
        .collection("EventChats")
        .doc(eventId)
        .get();

      if (!eventChatDoc.exists) {
        console.error("❌ EventChat não encontrado:", eventId);
        return;
      }

      const eventChatData = eventChatDoc.data();
      const participantIds = eventChatData?.participantIds || [];
      const activityText = eventChatData?.activityText || "Evento";
      const emoji = eventChatData?.emoji || "🎉";

      console.log(`   Participantes: ${participantIds.length}`);

      if (participantIds.length === 0) {
        console.log("⚠️ Nenhum participante no evento");
        return;
      }

      const batch = admin.firestore().batch();
      const timestamp =
        messageData.timestamp ||
        admin.firestore.FieldValue.serverTimestamp();

      // Update all participant conversations (source of truth)
      const participantsCount = participantIds.length;
      console.log(
        `Updating ${participantsCount} conversations...`
      );

      for (const userId of participantIds) {
        const conversationRef = admin
          .firestore()
          .collection("Connections")
          .doc(userId)
          .collection("Conversations")
          .doc(`event_${eventId}`);

        const isSender = userId === senderId;
        const unreadIncrement = isSender ?
          0 :
          admin.firestore.FieldValue.increment(1);

        batch.set(
          conversationRef,
          {
            event_id: eventId,
            activityText: activityText,
            emoji: emoji,
            last_message: messageText || "",
            last_message_type: messageType || "text",
            timestamp: timestamp,
            is_event_chat: true,
            message_read: isSender,
            unread_count: unreadIncrement,
          },
          {merge: true}
        );

        const unreadStatus = isSender ? "0" : "+1";
        console.log(
          `Conversation updated for ${userId} ` +
          `(read: ${isSender}, unread: ${unreadStatus})`
        );
      }

      // Enviar apenas push notifications (sem salvar in-app)
      // NOTA: Chat de evento segue padrão Instagram
      // Apenas push, sem tela de notificações
      console.log(`   SenderId: ${senderId}`);
      console.log(`   Tipo de mensagem: ${messageType}`);

      // DeepLink: abre o chat do evento
      const deepLink = `partiu://event-chat/${eventId}`;

      // Disparar push notifications para cada participante (exceto remetente)
      const pushPromises = participantIds
        .filter((id: string) => senderId !== "system" && id !== senderId)
        .map((participantId: string) =>
          sendPush({
            userId: participantId,
            event: "event_chat_message",
            // ✅ iOS foreground: preferir DATA-ONLY para garantir entrega no onMessage
            // e deixar o Flutter controlar a notificação local + clique.
            dataOnly: true,
            data: {
              n_type: "event_chat_message",
              sub_type: "event_chat_message",
              eventId: eventId,
              senderId: senderId,
              n_sender_name: senderName,
              senderName: senderName,
              eventTitle: activityText,
              eventName: activityText,
              activityText: activityText,
              emoji: emoji,
              eventEmoji: emoji,
              n_message: messageText?.substring(0, 100) || "",
              messagePreview: messageText?.substring(0, 100) || "",
              deepLink: deepLink,
            },
            context: {
              groupId: eventId,
            },
          })
        );

      if (pushPromises.length > 0) {
        await Promise.all(pushPromises);
        console.log(
          `✅ ${pushPromises.length} push notifications enviadas ` +
          `para evento ${eventId}`
        );
      } else {
        console.log("⏭️ Nenhum push enviado (remetente ou sistema)");
      }
    } catch (error) {
      console.error("❌ Erro ao criar notificações de EventChat:", error);
    }
  });
