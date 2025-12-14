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
      const senderPhotoUrl =
        messageData.sender_photo_url || messageData.senderPhotoUrl || "";

      console.log(
        `📬 [EventChatNotification] Nova mensagem no evento ${eventId} (v2)`
      );
      console.log(`   Remetente: ${senderName} (${senderId})`);
      console.log(`   Tipo: ${messageType}`);
      console.log(`   Mensagem: ${messageText}`);

      // Ignorar mensagens do sistema (não geram notificações)
      if (messageType === "system" || senderId === "system") {
        console.log("⏭️ Mensagem do sistema - não criar notificação");
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

      // Criar notificações para todos os participantes exceto o remetente
      let notificationCount = 0;

      console.log(`   SenderId: ${senderId}`);
      console.log(`   Tipo de mensagem: ${messageType}`);

      for (const participantId of participantIds) {
        console.log(`   Processando participante: ${participantId}`);

        // Evita notificar o remetente REAL, mas permite mensagens do sistema
        if (senderId !== "system" && participantId === senderId) {
          console.log("   ⏭️ Pulando - remetente real");
          continue;
        }

        // Criar notificação no formato esperado pelo app
        const notificationRef = admin
          .firestore()
          .collection("Notifications")
          .doc();

        batch.set(notificationRef, {
          n_receiver_id: participantId, // Campo padrão para queries
          userId: participantId, // Campo duplicado para compatibilidade
          n_type: "event_chat_message",
          n_params: {
            eventId: eventId,
            eventTitle: activityText,
            emoji: emoji,
            senderName: senderName,
            messagePreview: messageText?.substring(0, 100) || "",
          },
          n_related_id: eventId,
          n_read: false,
          n_sender_id: senderId,
          n_sender_fullname: senderName,
          n_sender_photo_link: senderPhotoUrl,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        notificationCount++;
      }

      if (notificationCount > 0) {
        await batch.commit();
        console.log(
          `✅ ${notificationCount} notificações in-app criadas ` +
          `para evento ${eventId}`
        );

        // Disparar push notifications para cada participante
        const pushPromises = participantIds
          .filter((id: string) => senderId !== "system" && id !== senderId)
          .map((participantId: string) =>
            sendPush({
              userId: participantId,
              type: "chat_event",
              title: `${activityText} ${emoji}`,
              body: `${senderName}: ${messageText?.substring(0, 100) || ""}`,
              data: {
                sub_type: "event_chat_message",
                eventId: eventId,
                senderId: senderId,
                senderName: senderName,
                eventTitle: activityText,
                eventEmoji: emoji,
                messagePreview: messageText?.substring(0, 100) || "",
              },
            })
          );

        await Promise.all(pushPromises);
        console.log(
          `✅ ${pushPromises.length} push notifications enviadas ` +
          `para evento ${eventId}`
        );
      } else {
        console.log("⏭️ Nenhuma notificação criada (remetente ou sistema)");
      }
    } catch (error) {
      console.error("❌ Erro ao criar notificações de EventChat:", error);
    }
  });
