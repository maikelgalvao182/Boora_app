/**
 * Cloud Functions: Notificações de EventChat
 *
 * Trigger que monitora mensagens criadas em EventChats/{eventId}/Messages
 * e cria notificações na coleção Users/{userId}/Notifications para
 * cada participante (exceto o remetente).
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

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

      // Criar notificações para todos os participantes exceto o remetente
      const batch = admin.firestore().batch();
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
          userId: participantId,
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
          `✅ ${notificationCount} notificações criadas ` +
          `para evento ${eventId}`
        );
      } else {
        console.log("⏭️ Nenhuma notificação criada (remetente ou sistema)");
      }
    } catch (error) {
      console.error("❌ Erro ao criar notificações de EventChat:", error);
    }
  });
