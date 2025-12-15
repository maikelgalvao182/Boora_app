/**
 * Cloud Functions: Push Notifications para Atividades
 *
 * ARQUITETURA:
 * - Monitora coleção Notifications (in-app)
 * - Dispara push notification via PushDispatcher (gateway único)
 * - NÃO monta mensagem (Flutter formata usando NotificationTemplates)
 * - NÃO faz lógica de targeting (NotificationTargetingService faz isso)
 *
 * RESPONSABILIDADES:
 * 1. Detectar criação de notificação in-app
 * 2. Extrair dados semânticos
 * 3. Chamar pushDispatcher.sendPush()
 *
 * TIPOS SUPORTADOS:
 * - activity_created: Nova atividade no raio
 * - activity_heating_up: Atividade esquentando
 * - activity_join_request: Pedido de entrada
 * - activity_join_approved: Entrada aprovada
 * - activity_join_rejected: Entrada recusada
 * - activity_new_participant: Novo participante
 * - activity_expiring_soon: Atividade expirando
 * - activity_canceled: Atividade cancelada
 *
 * ⚠️ PROTEÇÃO CONTRA LOOP INFINITO:
 * - Verifica n_origin para evitar processar notificações geradas por push
 * - PushDispatcher NUNCA deve escrever em Notifications
 */

import * as functions from "firebase-functions/v1";
import {sendPush, PushEvent} from "./services/pushDispatcher";

/**
 * 🎯 EVENTOS DE ATIVIDADES
 *
 * Lista centralizada para type guard.
 */
const ACTIVITY_EVENTS: PushEvent[] = [
  "activity_created",
  "activity_heating_up",
  "activity_join_request",
  "activity_join_approved",
  "activity_join_rejected",
  "activity_new_participant",
  "activity_expiring_soon",
  "activity_canceled",
];

/**
 * Type guard para validar se evento é de atividade
 * @param {string} event - Tipo do evento
 * @return {boolean} Se é evento de atividade
 */
function isActivityEvent(event: string): event is PushEvent {
  return ACTIVITY_EVENTS.includes(event as PushEvent);
}

export const onActivityNotificationCreated = functions.firestore
  .document("Notifications/{notificationId}")
  .onCreate(async (snap, context) => {
    const notificationId = context.params.notificationId;
    const notificationData = snap.data();

    if (!notificationData) {
      console.error(
        "❌ [ActivityPush] Notificação sem dados:",
        notificationId
      );
      return;
    }

    try {
      // 🔒 PROTEÇÃO CONTRA LOOP INFINITO
      const origin = notificationData.n_origin || notificationData.source;
      if (origin === "push" || origin === "system") {
        console.log(
          "⏭️ [ActivityPush] Notificação de origem " +
          `${origin}, ignorando para evitar loop`
        );
        return;
      }

      const nType = notificationData.n_type || "";
      const receiverId =
        notificationData.n_receiver_id || notificationData.userId;
      const params = notificationData.n_params || {};
      const senderName = notificationData.n_sender_fullname;

      // Filtrar apenas notificações de atividades usando type guard
      if (!isActivityEvent(nType)) {
        console.log(
          `⏭️ [ActivityPush] Tipo ${nType} não é de atividade, ignorando`
        );
        return;
      }

      console.log(`📬 [ActivityPush] Nova notificação: ${nType}`);
      console.log(`   Receiver: ${receiverId}`);

      // Montar dados semânticos para o dispatcher
      const pushData: Record<string, string | number | boolean> = {
        n_type: nType,
        activityId: params.activityId || notificationData.n_related_id || "",
        activityName: params.activityName || params.title || "",
        emoji: params.emoji || "🎉",
      };

      // Adicionar campos específicos por tipo
      switch (nType) {
      case "activity_created":
        pushData.n_sender_name = senderName || "Alguém";
        pushData.creatorName = senderName || "Alguém";
        if (params.commonInterests) {
          pushData.commonInterests = Array.isArray(params.commonInterests) ?
            params.commonInterests.join(",") :
            params.commonInterests;
        }
        break;

      case "activity_heating_up":
        pushData.n_sender_name = senderName || "Alguém";
        pushData.creatorName = senderName || "Alguém";
        pushData.n_participant_count = params.participantCount || 2;
        pushData.participantCount = params.participantCount || 2;
        break;

      case "activity_join_request":
        pushData.n_sender_name = senderName || "Alguém";
        pushData.requesterName = senderName || "Alguém";
        break;

      case "activity_join_approved":
      case "activity_join_rejected":
        // Não precisam de campos extras além dos básicos
        break;

      case "activity_new_participant":
        pushData.n_sender_name = senderName || "Alguém";
        pushData.participantName = senderName || "Alguém";
        break;

      case "activity_expiring_soon":
        pushData.hoursRemaining = params.hoursRemaining || 1;
        break;

      case "activity_canceled":
        // Não precisa de campos extras
        break;
      }

      // Disparar push via gateway único (type guard garante segurança)
      await sendPush({
        userId: receiverId,
        event: nType,
        data: pushData,
        context: {
          groupId: pushData.activityId as string,
        },
      });

      console.log(
        `✅ [ActivityPush] Push disparado: ${nType} → ${receiverId}`
      );
    } catch (error) {
      console.error(
        "❌ [ActivityPush] Erro ao processar notificação:",
        error
      );
      console.error(`   Notification ID: ${notificationId}`);
    }
  });

