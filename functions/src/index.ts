/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

admin.initializeApp();

/**
 * Quando um evento é criado, automaticamente:
 * 1. Cria application para o criador com status autoApproved
 * 2. Cria conversação de chat do evento no formato padrão (Connections)
 * 3. Adiciona criador como primeiro membro do chat
 */
export const onEventCreated = functions.firestore
  .document("events/{eventId}")
  .onCreate(async (snap, context) => {
    const eventId = context.params.eventId;
    const eventData = snap.data();
    const creatorId = eventData.createdBy;

    if (!creatorId) {
      console.error("❌ Evento sem createdBy:", eventId);
      return;
    }

    try {
      // Buscar dados do criador primeiro
      const creatorDoc = await admin
        .firestore()
        .collection("Users")
        .doc(creatorId)
        .get();

      const creatorData = creatorDoc.data() || {};
      const creatorName = creatorData.fullName || "Criador";
      const activityText = eventData.activityText || "Evento";
      const schedule = eventData.schedule || {}; // [NEW] Get schedule

      const batch = admin.firestore().batch();

      // 1. Criar application do criador automaticamente
      const applicationRef = admin
        .firestore()
        .collection("EventApplications")
        .doc();

      batch.set(applicationRef, {
        eventId: eventId,
        userId: creatorId,
        status: "autoApproved",
        appliedAt: admin.firestore.FieldValue.serverTimestamp(),
        decisionAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(
        `✅ Application auto-criada: ${creatorId} no evento ${eventId}`
      );

      // 2. Criar EventChat (arquitetura de grupo correta)
      const eventChatRef = admin
        .firestore()
        .collection("EventChats")
        .doc(eventId);

      batch.set(eventChatRef, {
        eventId: eventId,
        createdBy: creatorId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessage: `${creatorName} criou o evento`,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessageSenderId: "system",
        lastMessageType: "system",
        participantIds: [creatorId],
        participantCount: 1,
        activityText: activityText,
        emoji: eventData.emoji || "🎉",
        schedule: schedule,
      });

      console.log(`✅ EventChat criado: EventChats/${eventId}`);

      // 3. Adicionar mensagem inicial no EventChat
      const initialMessageRef = admin
        .firestore()
        .collection("EventChats")
        .doc(eventId)
        .collection("Messages")
        .doc();

      batch.set(initialMessageRef, {
        senderId: "system",
        senderName: "Sistema",
        senderPhotoUrl: "",
        message: `${creatorName} criou o evento`,
        messageType: "system",
        imgLink: "",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        readBy: [creatorId],
      });

      console.log("✅ Mensagem inicial criada no EventChat");

      // 4. Criar conversação do criador (para lista de conversas)
      const conversationRef = admin
        .firestore()
        .collection("Connections")
        .doc(creatorId)
        .collection("Conversations")
        .doc(`event_${eventId}`);

      batch.set(conversationRef, {
        event_id: eventId,
        activityText: activityText,
        emoji: eventData.emoji || "🎉",
        last_message: `${creatorName} criou o evento`,
        last_message_type: "system",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        message_read: true,
        unread_count: 0,
        is_event_chat: true,
        participant_ids: [creatorId],
        schedule: schedule,
      });

      console.log(`✅ Conversation criada para criador: ${creatorId}`);

      await batch.commit();

      console.log(
        `✅ Evento criado completo: application + chat para ${creatorId}`
      );
    } catch (error) {
      console.error("❌ Erro ao criar evento:", error);
    }
  });

/**
 * Quando uma application é aprovada:
 * 1. Adiciona usuário ao chat do evento (Connections)
 * 2. Cria/atualiza conversação para o usuário
 * 3. Envia mensagem de sistema no Messages
 * 4. Atualiza conversações de todos os participantes
 */
export const onApplicationApproved = functions.firestore
  .document("EventApplications/{applicationId}")
  .onWrite(async (change) => {
    const after = change.after.exists ? change.after.data() : null;
    const before = change.before.exists ? change.before.data() : null;

    if (!after) return; // Ignorar deleções

    let wasApproved = false;

    if (!before) {
      // Criação: verificar se já nasceu aprovado
      wasApproved =
        after.status === "approved" || after.status === "autoApproved";
    } else {
      // Atualização: verificar mudança de status
      wasApproved =
        (before.status !== "approved" && after.status === "approved") ||
        (before.status !== "autoApproved" && after.status === "autoApproved");
    }

    if (!wasApproved) return;

    const eventId = after.eventId;
    const userId = after.userId;

    try {
      // Buscar dados do evento e usuário em paralelo
      const [eventDoc, userDoc] = await Promise.all([
        admin.firestore().collection("events").doc(eventId).get(),
        admin.firestore().collection("Users").doc(userId).get(),
      ]);

      const eventData = eventDoc.data() || {};
      const userData = userDoc.data() || {};
      const userName = userData.fullName || "Alguém";
      const activityText = eventData.activityText || "Evento";
      const schedule = eventData.schedule || {}; // [NEW] Get schedule

      console.log(
        `🔍 DEBUG - activityText buscado do evento: "${activityText}"`
      );

      // Buscar participantes atuais do evento
      const applicationsSnapshot = await admin
        .firestore()
        .collection("EventApplications")
        .where("eventId", "==", eventId)
        .where("status", "in", ["approved", "autoApproved"])
        .get();

      const participantIds = applicationsSnapshot.docs.map(
        (doc) => doc.data().userId
      );

      // 🆕 Buscar dados completos de todos os participantes
      console.log(
        `🔍 Buscando dados de ${participantIds.length} participantes...`
      );
      const participantDocs = await Promise.all(
        participantIds.map((id) =>
          admin.firestore().collection("Users").doc(id).get()
        )
      );

      // Criar array de participantes com dados completos
      const participants = participantDocs
        .filter((doc) => doc.exists)
        .map((doc) => {
          const data = doc.data() || {};
          return {
            uid: doc.id,
            name: data.fullName || data.userFullname || "Usuário",
            avatar: data.profilePhoto || data.userProfilePhoto || "",
            role: doc.id === eventData.userId ? "organizador" : "participante",
          };
        });

      console.log(`✅ Dados de ${participants.length} participantes carregados`);

      const batch = admin.firestore().batch();

      // Mensagem de sistema
      const systemMessage = `${userName} entrou no grupo! 🎉`;

      // 1. Atualizar EventChat metadata
      const eventChatRef = admin
        .firestore()
        .collection("EventChats")
        .doc(eventId);

      batch.set(
        eventChatRef,
        {
          lastMessage: systemMessage,
          lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
          lastMessageSenderId: "system",
          lastMessageType: "system",
          participantIds: participantIds,
          participantCount: participantIds.length,
        },
        {merge: true}
      );

      console.log(
        `✅ EventChat atualizado com ${participantIds.length} participantes`
      );

      // 2. Adicionar mensagem no EventChat (UMA única mensagem no grupo)
      const messageRef = admin
        .firestore()
        .collection("EventChats")
        .doc(eventId)
        .collection("Messages")
        .doc();

      batch.set(messageRef, {
        sender_id: "system",
        sender_name: "Sistema", // 🆕 Nome do remetente
        sender_photo_url: "", // 🆕 Avatar do remetente
        message: systemMessage,
        message_text: systemMessage, // Compatibilidade
        message_type: "system",
        message_img_link: "",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        readBy: [userId], // Apenas novo participante marca como lido
      });

      console.log("✅ Mensagem adicionada ao EventChat");

      // 3. Para cada participante, criar/atualizar conversação (lista de chats)
      for (const participantId of participantIds) {
        const conversationRef = admin
          .firestore()
          .collection("Connections")
          .doc(participantId)
          .collection("Conversations")
          .doc(`event_${eventId}`);

        batch.set(
          conversationRef,
          {
            event_id: eventId,
            activityText: activityText,
            emoji: eventData.emoji || "🎉",
            last_message: systemMessage,
            last_message_type: "system",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            message_read: participantId === userId,
            unread_count: participantId === userId ?
              0 :
              admin.firestore.FieldValue.increment(1),
            is_event_chat: true,
            participant_ids: participantIds,
            // 🆕 Array completo com dados dos participantes
            participants: participants,
            schedule: schedule,
          },
          {merge: true}
        );

        console.log(
          `✅ Conversation atualizada para ${participantId} ` +
          `com activityText: "${activityText}" e ` +
          `${participants.length} participantes`
        );
      }

      await batch.commit();

      console.log(
        `✅ Participante ${userName} adicionado ao chat do evento ${eventId}`
      );

      // Push notification para participantes existentes (exceto novo)
      const existingParticipants = participantIds.filter((id) => id !== userId);

      if (existingParticipants.length > 0) {
        const userDocs = await Promise.all(
          existingParticipants.map((id) =>
            admin.firestore().collection("Users").doc(id).get()
          )
        );

        const tokens = userDocs
          .map((doc) => doc.data()?.fcmToken)
          .filter((token) => token);

        if (tokens.length > 0) {
          await admin.messaging().sendMulticast({
            tokens: tokens,
            notification: {
              title: activityText,
              body: systemMessage,
            },
            data: {
              type: "event_chat",
              eventId: eventId,
              chatId: `event_${eventId}`,
            },
          });

          console.log(
            `✅ Notificação enviada para ${tokens.length} participantes`
          );
        }
      }
    } catch (error) {
      console.error("❌ Erro ao processar application aprovada:", error);
    }
  });
