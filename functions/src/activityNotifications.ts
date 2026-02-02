/**
 * ACTIVITY NOTIFICATIONS - Cloud Functions para criar notificações in-app
 *
 * ARQUITETURA:
 * ```
 * Evento Firestore (onCreate/onUpdate)
 *       ↓
 * Cloud Function (este arquivo)
 *       ↓
 * Cria documento em "Notifications"
 *       ↓
 * activityPushNotifications.ts (trigger existente)
 *       ↓
 * Push notification via FCM
 * ```
 *
 * RESPONSABILIDADES:
 * 1. Detectar eventos relevantes (criação de evento, heating up, etc.)
 * 2. Calcular usuários alvo (geo + regras de negócio)
 * 3. Criar notificações in-app na collection "Notifications"
 *
 * TIPOS IMPLEMENTADOS:
 * - activity_created: Nova atividade no raio (30km)
 * - activity_heating_up: Atividade esquentando (3, 5, 10 participantes)
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {findUsersForEventNotification, getEventParticipants} from "./services/geoService";

// Thresholds para "heating up" - deve estar sincronizado com Flutter
const HEATING_UP_THRESHOLDS = [3, 5, 10];

/**
 * Cria notificação in-app para um usuário
 * @param {object} params - Parâmetros da notificação
 * @return {Promise<void>}
 */
async function createActivityNotification(params: {
  receiverId: string;
  type: string;
  title: string;
  body: string;
  preview: string;
  activityId: string;
  activityName: string;
  emoji: string;
  senderId?: string;
  senderName?: string;
  senderPhotoUrl?: string;
  extra?: Record<string, unknown>;
}): Promise<void> {
  const now = admin.firestore.FieldValue.serverTimestamp();

  await admin.firestore().collection("Notifications").add({
    // Campos padronizados (n_ prefix)
    n_receiver_id: params.receiverId,
    n_type: params.type,
    n_origin: "cloud_function",
    n_created_at: now,
    // Campo padrão usado pelo app para ordenação/exibição
    timestamp: now,
    n_read: false,
    n_related_id: params.activityId,

    // Dados do sender (criador da atividade)
    n_sender_id: params.senderId || null,
    n_sender_fullname: params.senderName || null,
    n_sender_photo_url: params.senderPhotoUrl || null,

    // Parâmetros para template
    n_params: {
      title: params.title,
      body: params.body,
      preview: params.preview,
      activityId: params.activityId,
      activityName: params.activityName,
      emoji: params.emoji,
      ...params.extra,
    },

    // Campos legados para compatibilidade
    userId: params.receiverId,
    type: params.type,
    createdAt: now,
    read: false,
  });
}

/**
 * 🎯 TRIGGER 1: Nova atividade criada
 *
 * Dispara quando um evento é criado em "events".
 * Notifica todos os usuários dentro de 30km (exceto o criador).
 */
export const onActivityCreatedNotification = functions.firestore
  .document("events/{eventId}")
  .onCreate(async (snap, context) => {
    const eventId = context.params.eventId;
    const eventData = snap.data();

    if (!eventData) {
      console.error("❌ [ActivityNotif] Evento sem dados:", eventId);
      return;
    }

    const creatorId = eventData.createdBy;
    const latitude = eventData.latitude || eventData.location?.latitude;
    const longitude = eventData.longitude || eventData.location?.longitude;

    if (!creatorId || !latitude || !longitude) {
      console.error(
        "❌ [ActivityNotif] Dados incompletos:",
        {creatorId, latitude, longitude}
      );
      return;
    }

    console.log("\n🎯 [ActivityNotif] ACTIVITY_CREATED");
    console.log(`   Evento: ${eventId}`);
    console.log(`   Criador: ${creatorId}`);

    try {
      // 1. Buscar dados do criador
      const creatorDoc = await admin
        .firestore()
        .collection("Users")
        .doc(creatorId)
        .get();

      const creatorData = creatorDoc.data() || {};
      const creatorName = creatorData.fullName || "Alguém";
      let creatorPhoto = creatorData.profilePhoto || creatorData.photoUrl || "";

      // Ignorar URLs do Google OAuth
      if (
        creatorPhoto.includes("googleusercontent.com") ||
        creatorPhoto.includes("lh3.google")
      ) {
        creatorPhoto = "";
      }

      // 2. Buscar usuários elegíveis (respeitando raio personalizado de cada um)
      const usersInRadius = await findUsersForEventNotification({
        eventLatitude: latitude,
        eventLongitude: longitude,
        excludeUserIds: [creatorId],
        limit: 500,
      });

      if (usersInRadius.length === 0) {
        console.log("⚠️ [ActivityNotif] Nenhum usuário no raio");
        return;
      }

      console.log(
        "📬 [ActivityNotif] Criando notificações " +
        `para ${usersInRadius.length} usuários`
      );

      // 3. Dados da atividade
      const activityName = eventData.activityText || eventData.name || "Evento";
      const emoji = eventData.emoji || "🎉";

      // 4. Criar notificações em batch (máximo 500 por batch)
      const batches: admin.firestore.WriteBatch[] = [];
      let currentBatch = admin.firestore().batch();
      let operationCount = 0;

      for (const userId of usersInRadius) {
        const notifRef = admin.firestore().collection("Notifications").doc();
        const now = admin.firestore.FieldValue.serverTimestamp();

        currentBatch.set(notifRef, {
          // Campos padronizados
          n_receiver_id: userId,
          n_type: "activity_created",
          n_origin: "cloud_function",
          n_created_at: now,
          timestamp: now,
          n_read: false,
          n_related_id: eventId,
          n_sender_id: creatorId,
          n_sender_fullname: creatorName,
          n_sender_photo_url: creatorPhoto,
          n_params: {
            title: `${activityName} ${emoji}`,
            body: `${creatorName} quer ${activityName.toLowerCase()}, bora?`,
            preview: `${creatorName} criou uma atividade perto de você`,
            activityId: eventId,
            activityName: activityName,
            emoji: emoji,
          },
          // Campos legados
          userId: userId,
          type: "activity_created",
          createdAt: now,
          read: false,
        });

        operationCount++;

        // Firestore batch limit é 500
        if (operationCount >= 500) {
          batches.push(currentBatch);
          currentBatch = admin.firestore().batch();
          operationCount = 0;
        }
      }

      // Push batch final se houver operações pendentes
      if (operationCount > 0) {
        batches.push(currentBatch);
      }

      // Commit all batches
      await Promise.all(batches.map((batch) => batch.commit()));

      console.log(
        `✅ [ActivityNotif] ${usersInRadius.length} notificações criadas`
      );
    } catch (error) {
      console.error("❌ [ActivityNotif] Erro:", error);
    }
  });

/**
 * 🔥 TRIGGER 2: Atividade "Heating Up"
 *
 * Dispara quando uma EventApplication é aprovada.
 * Verifica se atingiu threshold (3, 5, 10) e notifica usuários no raio.
 */
export const onActivityHeatingUp = functions.firestore
  .document("EventApplications/{applicationId}")
  .onWrite(async (change) => {
    const after = change.after.exists ? change.after.data() : null;
    const before = change.before.exists ? change.before.data() : null;

    if (!after) {
      return; // Deletion, ignore
    }

    // Só processa se foi aprovação
    const beforeStatus = before?.status || "none";
    const afterStatus = after.status || "none";

    const wasApproved =
      (beforeStatus !== "approved" && afterStatus === "approved") ||
      (beforeStatus !== "autoApproved" && afterStatus === "autoApproved");

    if (!wasApproved) {
      return;
    }

    const eventId = after.eventId;
    if (!eventId) {
      return;
    }

    console.log(`\n🔥 [HeatingUp] Checking event: ${eventId}`);

    try {
      // 1. Contar participantes atuais
      const participants = await getEventParticipants(eventId);
      const currentCount = participants.length;

      console.log(`   Participantes: ${currentCount}`);

      // 2. Verificar se atingiu threshold
      if (!HEATING_UP_THRESHOLDS.includes(currentCount)) {
        console.log("   Não é threshold, ignorando");
        return;
      }

      console.log(`   🎯 THRESHOLD ATINGIDO: ${currentCount}`);

      // 3. Buscar dados do evento
      const eventDoc = await admin
        .firestore()
        .collection("events")
        .doc(eventId)
        .get();

      const eventData = eventDoc.data();
      if (!eventData) {
        console.error("❌ [HeatingUp] Evento não encontrado");
        return;
      }

      const creatorId = eventData.createdBy;
      const latitude = eventData.latitude || eventData.location?.latitude;
      const longitude = eventData.longitude || eventData.location?.longitude;

      if (!latitude || !longitude) {
        console.error("❌ [HeatingUp] Localização não encontrada");
        return;
      }

      // 4. Buscar dados do criador
      const creatorDoc = await admin
        .firestore()
        .collection("Users")
        .doc(creatorId)
        .get();

      const creatorData = creatorDoc.data() || {};
      const creatorName = creatorData.fullName || "Alguém";
      let creatorPhoto = creatorData.profilePhoto || creatorData.photoUrl || "";

      if (
        creatorPhoto.includes("googleusercontent.com") ||
        creatorPhoto.includes("lh3.google")
      ) {
        creatorPhoto = "";
      }

      // 5. Buscar usuários elegíveis (respeitando raio personalizado de cada um)
      const excludeIds = [...participants, creatorId];
      const usersInRadius = await findUsersForEventNotification({
        eventLatitude: latitude,
        eventLongitude: longitude,
        excludeUserIds: excludeIds,
        limit: 500,
      });

      if (usersInRadius.length === 0) {
        console.log(
          "⚠️ [HeatingUp] Nenhum usuário no raio (fora participantes)"
        );
        return;
      }

      console.log(
        "📬 [HeatingUp] Criando notificações " +
        `para ${usersInRadius.length} usuários`
      );

      // 6. Dados da atividade
      const activityName = eventData.activityText || eventData.name || "Evento";
      const emoji = eventData.emoji || "🎉";

      // 7. Criar notificações em batch
      const batches: admin.firestore.WriteBatch[] = [];
      let currentBatch = admin.firestore().batch();
      let operationCount = 0;

      for (const userId of usersInRadius) {
        const notifRef = admin.firestore().collection("Notifications").doc();
        const now = admin.firestore.FieldValue.serverTimestamp();

        currentBatch.set(notifRef, {
          // Campos padronizados
          n_receiver_id: userId,
          n_type: "activity_heating_up",
          n_origin: "cloud_function",
          n_created_at: now,
          timestamp: now,
          n_read: false,
          n_related_id: eventId,
          n_sender_id: creatorId,
          n_sender_fullname: creatorName,
          n_sender_photo_url: creatorPhoto,
          n_params: {
            title: "Atividade bombando!🔥",
            body: "As pessoas estão entrando na atividade " +
              `de ${creatorName}! Não fique de fora!`,
            preview: `${currentCount} pessoas já entraram`,
            activityId: eventId,
            activityName: activityName,
            emoji: emoji,
            participantCount: currentCount,
          },
          // Campos legados
          userId: userId,
          type: "activity_heating_up",
          createdAt: now,
          read: false,
        });

        operationCount++;

        if (operationCount >= 500) {
          batches.push(currentBatch);
          currentBatch = admin.firestore().batch();
          operationCount = 0;
        }
      }

      if (operationCount > 0) {
        batches.push(currentBatch);
      }

      await Promise.all(batches.map((batch) => batch.commit()));

      const total = usersInRadius.length;
      console.log(
        `✅ [HeatingUp] ${total} notificações (count=${currentCount})`
      );
    } catch (error) {
      console.error("❌ [HeatingUp] Erro:", error);
    }
  });

/**
 * 📨 TRIGGER 3: Join Request (pedido de entrada em atividade privada)
 *
 * Dispara quando uma EventApplication é criada com status "pending".
 * Notifica apenas o criador do evento.
 */
export const onJoinRequestNotification = functions.firestore
  .document("EventApplications/{applicationId}")
  .onCreate(async (snap) => {
    const applicationData = snap.data();

    if (!applicationData || applicationData.status !== "pending") {
      return; // Só notifica para pedidos pendentes
    }

    const eventId = applicationData.eventId;
    const requesterId = applicationData.userId;

    if (!eventId || !requesterId) {
      return;
    }

    console.log(`\n📨 [JoinRequest] Novo pedido para evento: ${eventId}`);

    try {
      // 1. Buscar dados do evento
      const eventDoc = await admin
        .firestore()
        .collection("events")
        .doc(eventId)
        .get();

      const eventData = eventDoc.data();
      if (!eventData) {
        console.error("❌ [JoinRequest] Evento não encontrado");
        return;
      }

      const creatorId = eventData.createdBy;
      if (!creatorId || creatorId === requesterId) {
        return;
      }

      // 🔒 DEDUPLICAÇÃO: Evitar disparos duplos (Client + Server)
      // Verifica se já existe notificação deste tipo nos últimos 2 minutos
      const existingSnap = await admin.firestore().collection("Notifications")
        .where("userId", "==", creatorId)
        .where("n_related_id", "==", eventId)
        .get();

      const isDuplicate = existingSnap.docs.some((doc) => {
        const d = doc.data();
        if (d.n_type !== "activity_join_request") return false;
        if (d.n_sender_id !== requesterId) return false;

        // Se foi criada há menos de 2 min, é duplicidade
        const ts = d.timestamp || d.n_created_at;
        if (ts && ts.toMillis) {
          return (Date.now() - ts.toMillis()) < 2 * 60 * 1000;
        }
        return true; // Sem timestamp ou formato inválido, considera duplicata
      });

      if (isDuplicate) {
        console.log(
          `⏭️ [JoinRequest] Duplicata detectada para ${requesterId}, ignorando`
        );
        return;
      }

      // 2. Buscar dados do solicitante
      const requesterDoc = await admin
        .firestore()
        .collection("Users")
        .doc(requesterId)
        .get();

      const requesterData = requesterDoc.data() || {};
      const requesterName = requesterData.fullName || "Alguém";
      let requesterPhoto =
        requesterData.profilePhoto || requesterData.photoUrl || "";

      if (
        requesterPhoto.includes("googleusercontent.com") ||
        requesterPhoto.includes("lh3.google")
      ) {
        requesterPhoto = "";
      }

      // 3. Dados da atividade
      const activityName = eventData.activityText || eventData.name || "Evento";
      const emoji = eventData.emoji || "🎉";

      // 4. Criar notificação para o criador
      await createActivityNotification({
        receiverId: creatorId,
        type: "activity_join_request",
        title: `${activityName} ${emoji}`,
        body: `${requesterName} pediu para entrar na sua atividade`,
        preview: `Pedido de entrada de ${requesterName}`,
        activityId: eventId,
        activityName: activityName,
        emoji: emoji,
        senderId: requesterId,
        senderName: requesterName,
        senderPhotoUrl: requesterPhoto,
      });

      console.log(`✅ [JoinRequest] Notificação criada para ${creatorId}`);
    } catch (error) {
      console.error("❌ [JoinRequest] Erro:", error);
    }
  });

/**
 * ✅ TRIGGER 4: Join Approved/Rejected
 *
 * Dispara quando uma EventApplication muda de "pending" para
 * "approved" ou "rejected".
 * Notifica o usuário que fez o pedido.
 */
export const onJoinDecisionNotification = functions.firestore
  .document("EventApplications/{applicationId}")
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after = change.after.data();

    if (!before || !after) {
      return;
    }

    const beforeStatus = before.status;
    const afterStatus = after.status;

    // Só processa mudanças de pending para approved/rejected
    if (beforeStatus !== "pending") {
      return;
    }

    const isApproved = afterStatus === "approved";
    const isRejected = afterStatus === "rejected";

    if (!isApproved && !isRejected) {
      return;
    }

    const eventId = after.eventId;
    const userId = after.userId;

    console.log(
      `\n${isApproved ? "✅" : "🚫"} [JoinDecision] ` +
      `${afterStatus} para evento: ${eventId}`
    );

    try {
      // 1. Buscar dados do evento
      const eventDoc = await admin
        .firestore()
        .collection("events")
        .doc(eventId)
        .get();

      const eventData = eventDoc.data();
      if (!eventData) {
        console.error("❌ [JoinDecision] Evento não encontrado:", eventId);
        return;
      }

      // 2. Buscar dados do criador (sender da notificação)
      const creatorId = eventData.createdBy;
      let senderName: string | undefined;
      let senderPhotoUrl: string | undefined;

      if (creatorId) {
        const creatorDoc = await admin
          .firestore()
          .collection("Users")
          .doc(creatorId)
          .get();

        const creatorData = creatorDoc.data();
        if (creatorData) {
          senderName = creatorData.fullName || "Organizador";
          senderPhotoUrl = creatorData.profilePhoto || creatorData.photoUrl;

          // Ignorar URLs do Google OAuth
          if (senderPhotoUrl && (
            senderPhotoUrl.includes("googleusercontent.com") ||
            senderPhotoUrl.includes("lh3.google")
          )) {
            senderPhotoUrl = undefined;
          }
        }
      }

      // 3. Dados da atividade
      const activityName = eventData.activityText || eventData.name || "Evento";
      const emoji = eventData.emoji || "🎉";

      // 4. Criar notificação
      const type = isApproved ?
        "activity_join_approved" :
        "activity_join_rejected";
      const body = isApproved ?
        "Você foi aprovado para participar!" :
        "Seu pedido para entrar foi recusado";

      await createActivityNotification({
        receiverId: userId,
        type: type,
        title: `${activityName} ${emoji}`,
        body: body,
        preview: body,
        activityId: eventId,
        activityName: activityName,
        emoji: emoji,
        senderId: creatorId,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
      });

      console.log(`✅ [JoinDecision] Notificação ${type} criada para ${userId}`);
    } catch (error) {
      console.error("❌ [JoinDecision] Erro:", error);
    }
  });

/**
 * ❌ TRIGGER 5: Activity Canceled
 *
 * Dispara quando um evento é marcado como inativo/cancelado.
 * Notifica todos os participantes.
 */
export const onActivityCanceledNotification = functions.firestore
  .document("events/{eventId}")
  .onUpdate(async (change, context) => {
    const eventId = context.params.eventId;
    const before = change.before.data();
    const after = change.after.data();

    if (!before || !after) {
      return;
    }

    // Detectar cancelamento (isActive: true → false)
    const wasActive = before.isActive !== false;
    const isNowInactive = after.isActive === false;

    if (!wasActive || !isNowInactive) {
      return;
    }

    console.log(`\n❌ [ActivityCanceled] Evento cancelado: ${eventId}`);

    try {
      // 1. Buscar participantes
      const participants = await getEventParticipants(eventId);
      const creatorId = after.createdBy;

      // Excluir criador das notificações (ele sabe que cancelou)
      const notifyUsers = participants.filter((id) => id !== creatorId);

      if (notifyUsers.length === 0) {
        console.log("⚠️ [ActivityCanceled] Nenhum participante para notificar");
        return;
      }

      // 2. Dados da atividade
      const activityName = after.activityText || after.name || "Evento";
      const emoji = after.emoji || "🎉";

      // 3. Criar notificações em batch
      const batch = admin.firestore().batch();

      for (const userId of notifyUsers) {
        const notifRef = admin.firestore().collection("Notifications").doc();
        const now = admin.firestore.FieldValue.serverTimestamp();

        batch.set(notifRef, {
          n_receiver_id: userId,
          n_type: "activity_canceled",
          n_origin: "cloud_function",
          n_created_at: now,
          timestamp: now,
          n_read: false,
          n_related_id: eventId,
          n_params: {
            title: `${activityName} ${emoji}`,
            body: "Esta atividade foi cancelada",
            preview: "Atividade cancelada",
            activityId: eventId,
            activityName: activityName,
            emoji: emoji,
          },
          userId: userId,
          type: "activity_canceled",
          createdAt: now,
          read: false,
        });
      }

      await batch.commit();

      console.log(
        `✅ [ActivityCanceled] ${notifyUsers.length} notificações criadas`
      );
    } catch (error) {
      console.error("❌ [ActivityCanceled] Erro:", error);
    }
  });
