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
import {sendPush} from "./services/pushDispatcher";

export {deleteChatMessage} from "./chatMessageDeletion";
export {patchAddCountryFlag} from "./patchAddCountryFlag";
export {patchRemoveFormattedAddress} from "./patchRemoveFormattedAddress";
export {onReportCreated} from "./reportModeration";
export {onUserCreatedReferral} from "./referrals";
export {followUser, unfollowUser} from "./users/followSystem";
export {cleanupOldProfileVisits} from "./profileVisitsCleanup";
export {
  onUserAvatarUpdated,
  backfillMissingCreatorAvatarUrl,
} from "./events/creatorAvatarSync";
export {onUserLocationUpdated} from "./events/usersGridSync";
export {onEventWriteUpdateCardPreview} from "./events/eventCardPreviewSync";
export {onUserWriteUpdatePreview} from "./users/usersPreviewSync";
export {resyncUsersPreview} from "./users/resyncUsersPreview";
export {
  migrateUserLocationToPrivate,
} from "./users/migrateLocationToPrivate";
export {syncRankingFilters} from "./ranking/rankingFiltersSync";
export {
  checkDeviceBlacklist,
  registerDevice,
  onUserStatusChange,
} from "./devices/deviceBlacklist";
// Feed Fanout System - distribui posts para feeds dos seguidores
export {
  onEventPhotoWriteFanout,
  onActivityFeedWriteFanout,
  onNewFollowerBackfillFeed,
  onUnfollowCleanupFeed,
} from "./feed/feedFanout";

if (!admin.apps.length) {
  admin.initializeApp();
}

// 🔒 getPeople é exportado via "export * from ./get_people" no final do arquivo.

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
        presence: "Vou", // Criador sempre confirma presença
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
        is_deleted: false,
        sender_id: "system",
        sender_name: "Sistema",
        sender_photo_url: "",
        message: `${creatorName} criou o evento`,
        message_text: `${creatorName} criou o evento`,
        message_type: "system",
        message_img_link: "",
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
  .onWrite(async (change, context) => {
    const applicationId = context.params.applicationId;
    const after = change.after.exists ? change.after.data() : null;
    const before = change.before.exists ? change.before.data() : null;

    console.log(
      `🔔 [onApplicationApproved] Trigger fired for: ${applicationId}`
    );

    if (!after) {
      console.log("⏭️ Ignoring deletion");
      return;
    }

    const beforeStatus = before?.status || "none";
    const afterStatus = after.status || "none";

    console.log(`   Before status: ${beforeStatus}`);
    console.log(`   After status: ${afterStatus}`);

    let wasApproved = false;

    if (!before) {
      // Criação: verificar se já nasceu aprovado
      wasApproved =
        after.status === "approved" || after.status === "autoApproved";
      console.log(`   Created with status: ${afterStatus}`);
    } else {
      // Atualização: verificar mudança de status
      wasApproved =
        (before.status !== "approved" && after.status === "approved") ||
        (before.status !== "autoApproved" && after.status === "autoApproved");
      console.log(`   Status changed: ${beforeStatus} -> ${afterStatus}`);
    }

    if (!wasApproved) {
      console.log(
        `⏭️ Not approved yet (status: ${afterStatus}), skipping...`
      );
      return;
    }

    console.log("✅ Application approved! Processing...");

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
      const userPhotoUrl = userData.profilePhoto || userData.photoUrl || "";
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

      const participantIdsFromQuery = applicationsSnapshot.docs.map(
        (doc) => doc.data().userId
      );

      // Garantir que o novo usuário seja incluído (race condition fix)
      const participantIds = participantIdsFromQuery.includes(userId) ?
        participantIdsFromQuery :
        [...participantIdsFromQuery, userId];

      const participantsCountText =
        `participantIds: ${participantIds.length}` +
        ` (query: ${participantIdsFromQuery.length})`;
      console.log(participantsCountText);

      // Buscar dados completos de todos os participantes
      console.log(
        `Buscando dados de ${participantIds.length} participantes...`
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
            avatar: data.profilePhoto || data.photoUrl || "",
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
        sender_id: userId, // ✅ O usuário que entrou é o sender
        sender_name: userName, // ✅ Nome do usuário que entrou
        sender_photo_url: userPhotoUrl || "", // ✅ Foto do usuário que entrou
        message: systemMessage,
        message_text: systemMessage, // Compatibilidade
        message_type: "event_join", // ✅ Tipo específico para entrada
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
              0 : admin.firestore.FieldValue.increment(1),
            is_event_chat: true,
            participant_ids: participantIds,
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

      // Push notification APENAS para o criador do evento
      // (evita spam para todos os participantes)
      const creatorId = eventData.createdBy || eventData.userId;
      const emoji = eventData.emoji || "🎉";

      // Só envia push se:
      // 1. O evento tem um criador
      // 2. O novo participante NÃO é o próprio criador
      if (creatorId && creatorId !== userId) {
        // DeepLink: abre o evento no mapa
        const deepLink = `partiu://home?event=${eventId}`;

        await sendPush({
          userId: creatorId,
          event: "activity_new_participant",
          origin: "onApplicationApproved",
          // Template: activityNewParticipant
          notification: {
            title: `${activityText} ${emoji}`,
            body: `${userName} entrou na sua atividade!`,
          },
          data: {
            n_type: "activity_new_participant",
            sub_type: "activity_new_participant",
            relatedId: eventId,
            n_related_id: eventId,
            eventId: eventId,
            chatId: `event_${eventId}`,
            n_sender_name: userName,
            userName: userName,
            activityText: activityText,
            eventTitle: activityText,
            emoji: emoji,
            deepLink: deepLink,
          },
        });

        console.log(
          `✅ Push enviado para criador ${creatorId} sobre novo participante`
        );
      } else {
        console.log(
          `⏭️ Push não enviado: criador=${creatorId}, ` +
          `novo=${userId} (mesmo ou sem criador)`
        );
      }
    } catch (error) {
      console.error("❌ Erro ao processar application aprovada:", error);
    }
  });

// ===== EVENT MANAGEMENT FUNCTIONS =====
// Importa e exporta as Cloud Functions de gerenciamento de eventos
export * from "./events";

// ===== RANKING FUNCTIONS =====
// Importa e exporta as Cloud Functions de ranking
export * from "./ranking/updateRanking";

// ===== NOTIFICATION FUNCTIONS =====
// Importa e exporta as Cloud Functions de notificações agregadas
export * from "./profileViewNotifications";

// Limpeza automática de notificações antigas (retenção)
export * from "./notifications/cleanupOldNotifications";
export * from "./notifications/backfillMissingNotificationTimestamps";

// ===== EVENT CHAT NOTIFICATIONS =====
// Importa e exporta as Cloud Functions de notificações de EventChat
// Inclui notificações in-app + push notifications para mensagens de grupo
export * from "./eventChatNotifications";

// ===== CHAT PUSH NOTIFICATIONS =====
// Importa e exporta as Cloud Functions de push notifications de chat 1-1
export * from "./chatPushNotifications";

// ===== ACTIVITY PUSH NOTIFICATIONS =====
// Monitora coleção Notifications e dispara push para 8 tipos de atividades
export * from "./activityPushNotifications";

// ===== MAP SYNC =====
// Sincroniza eventos para coleção lightweight events_map
export * from "./events/mapSync";

// ===== ACTIVITY IN-APP NOTIFICATIONS =====
// Cria notificações in-app na coleção Notifications
// (triggers de eventos que geram notificações)
export * from "./activityNotifications";

// ===== REVIEW FUNCTIONS =====
// Importa e exporta as Cloud Functions de reviews
export * from "./reviews/createPendingReviews";
export * from "./reviews/onPresenceConfirmed";
export * from "./reviews/reviewNotifications";
export * from "./updateUserRating";

// ===== DEBUG FUNCTIONS =====
export * from "./debug";

// ===== MIGRATIONS =====
export * from "./migrations/backfillUserGeohash";

// ===== USER MANAGEMENT =====
// Importa e exporta as Cloud Functions de gerenciamento de usuários
export * from "./users/deleteUserAccount";
export * from "./get_people";

// ===== PROFILE VISITS =====
// Retorna apenas o contador agregado de visitas (sem expor quem visitou)
export * from "./profileVisitsCount";

// ===== WEBHOOKS =====
// Importa e exporta webhooks de integração
export * from "./didit-webhook";
export * from "./webhooks/revenuecat-webhook";
