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
import {createHash} from "crypto";
import {
  sendPush,
  PushEvent,
  PushDispatchMetrics,
} from "./services/pushDispatcher";
import {createExecutionMetrics} from "./utils/executionMetrics";

/**
 * 🎯 EVENTOS DE ATIVIDADES
 *
 * Lista centralizada para type guard.
 *
 * ⚠️ NOTA: `activity_new_participant` foi REMOVIDO desta lista porque
 * o push já é disparado diretamente pela Cloud Function `onApplicationApproved`
 * no index.ts quando uma EventApplication é aprovada.
 * Manter aqui causaria PUSH DUPLICADO.
 */
const ACTIVITY_EVENTS: PushEvent[] = [
  "activity_created",
  "activity_heating_up",
  "activity_join_request",
  "activity_join_approved",
  "activity_join_rejected",
  // "activity_new_participant", // ❌ REMOVIDO - push via onApplicationApproved
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

const DEDUPE_WINDOW_MS = 5 * 60 * 1000;
const DEDUPE_CACHE_MAX_ENTRIES = 2000;

// In-memory dedupe cache (evita 2 Firestore ops por invocação)
// Trade-off: perde dedupe em cold start, mas push_sent guard no doc já protege
const dedupeMemoryCache = new Map<string, number>();

function buildPushDedupeKey(
  receiverId: string,
  nType: string,
  relatedId: string
): string {
  const bucket = Math.floor(Date.now() / DEDUPE_WINDOW_MS);
  const raw = `${receiverId}|${nType}|${relatedId}|${bucket}`;
  return createHash("sha1").update(raw).digest("hex");
}

function isDedupeHitInMemory(key: string): boolean {
  const expiresAt = dedupeMemoryCache.get(key);
  if (expiresAt && Date.now() < expiresAt) {
    return true;
  }
  dedupeMemoryCache.delete(key);
  return false;
}

function setDedupeInMemory(key: string): void {
  dedupeMemoryCache.set(key, Date.now() + DEDUPE_WINDOW_MS);
  // Evict oldest entries if cache is too large
  if (dedupeMemoryCache.size > DEDUPE_CACHE_MAX_ENTRIES) {
    const firstKey = dedupeMemoryCache.keys().next().value;
    if (firstKey) dedupeMemoryCache.delete(firstKey);
  }
}

export const onActivityNotificationCreated = functions.firestore
  .document("Notifications/{notificationId}")
  .onCreate(async (snap, context) => {
    const notificationId = context.params.notificationId;
    const metrics = createExecutionMetrics({
      executionId: context.eventId,
    });
    const notificationData = snap.data();
    const dispatch: { metrics: PushDispatchMetrics | null } = {metrics: null};

    if (!notificationData) {
      console.error(
        "❌ [ActivityPush] Notificação sem dados:",
        notificationId
      );
      metrics.done({
        notificationId,
        skipped: true,
        reason: "missing_notification_data",
      });
      return;
    }

    try {
      // 🔒 PROTEÇÃO CONTRA DUPLICAÇÃO (retry do Firebase)
      // Se já enviou push para esta notificação, ignora
      if (notificationData.push_sent === true) {
        console.log(
          `⏭️ [ActivityPush] Push já enviado para ${notificationId}, ignorando`
        );
        metrics.done({
          notificationId,
          skipped: true,
          reason: "push_already_sent",
        });
        return;
      }

      // 🔒 PROTEÇÃO CONTRA LOOP INFINITO
      const origin = notificationData.n_origin || notificationData.source;
      if (origin === "push" || origin === "system") {
        console.log(
          "⏭️ [ActivityPush] Notificação de origem " +
          `${origin}, ignorando para evitar loop`
        );
        metrics.done({
          notificationId,
          skipped: true,
          reason: "origin_loop_prevention",
          origin,
        });
        return;
      }

      const nType = notificationData.n_type || "";
      const receiverId =
        notificationData.n_receiver_id || notificationData.userId;
      const relatedId =
        notificationData.n_related_id ||
        notificationData.n_params?.activityId ||
        "";
      const params = notificationData.n_params || {};
      const senderName = notificationData.n_sender_fullname;

      // Filtrar apenas notificações de atividades usando type guard
      if (!isActivityEvent(nType)) {
        console.log(
          `⏭️ [ActivityPush] Tipo ${nType} não é de atividade, ignorando`
        );
        metrics.done({
          notificationId,
          skipped: true,
          reason: "event_not_activity",
          nType,
        });
        return;
      }

      if (!receiverId) {
        metrics.done({
          notificationId,
          skipped: true,
          reason: "missing_receiver_id",
          nType,
        });
        return;
      }

      const dedupeKey = buildPushDedupeKey(receiverId, nType, String(relatedId));

      // In-memory dedupe (economia de 2 Firestore ops: 1 read + 1 write)
      // push_sent guard no doc original protege contra duplicação em cold start
      if (isDedupeHitInMemory(dedupeKey)) {
        metrics.done({
          notificationId,
          receiverId,
          nType,
          skipped: true,
          reason: "dedupe_window_memory",
          dedupeKey,
        });
        return;
      }

      setDedupeInMemory(dedupeKey);

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

      // Montar notification baseado no template NotificationTemplates.dart
      const activityName = pushData.activityName as string || "Atividade";
      const emoji = pushData.emoji as string || "🎉";
      const creatorName = (pushData.creatorName as string) ||
        (pushData.n_sender_name as string) || "Alguém";

      let notificationTitle = `${activityName} ${emoji}`;
      let notificationBody = "Você tem uma nova atualização";

      switch (nType) {
      case "activity_created":
        // Template: activityCreated
        notificationTitle = `${activityName} ${emoji}`;
        notificationBody = `${creatorName} quer ${activityName}, bora?`;
        break;

      case "activity_heating_up":
        // Template: activityHeatingUp
        notificationTitle = "Atividade bombando!🔥";
        notificationBody =
          `As pessoas estão entrando na atividade de ${creatorName}! ` +
          "Não fique de fora!";
        break;

      case "activity_join_request":
        // Template: activityJoinRequest
        notificationTitle = `${activityName} ${emoji}`;
        notificationBody =
          `${pushData.requesterName || creatorName} pediu ` +
          "para entrar na sua atividade";
        break;

      case "activity_join_approved":
        // Template: activityJoinApproved
        notificationTitle = `${activityName} ${emoji}`;
        notificationBody = "Você foi aprovado para participar!";
        break;

      case "activity_join_rejected":
        // Template: activityJoinRejected
        notificationTitle = `${activityName} ${emoji}`;
        notificationBody = "Seu pedido para entrar foi recusado";
        break;

      case "activity_new_participant":
        // Template: activityNewParticipant
        notificationTitle = `${activityName} ${emoji}`;
        notificationBody =
          `${pushData.participantName || creatorName} ` +
          "entrou na sua atividade!";
        break;

      case "activity_expiring_soon":
        // Template: activityExpiringSoon
        notificationTitle = `${activityName} ${emoji}`;
        notificationBody =
          "Esta atividade está quase acabando. Última chance!";
        break;

      case "activity_canceled":
        // Template: activityCanceled
        notificationTitle = `${activityName} ${emoji}`;
        notificationBody = "Esta atividade foi cancelada";
        break;
      }

      // Montar deepLink baseado no tipo de notificação
      const activityId = pushData.activityId as string;
      let deepLink = `partiu://activity/${activityId}`;

      // Casos especiais de navegação
      switch (nType) {
      case "activity_join_request":
        // Redireciona para a tela de gerenciamento do evento
        deepLink = `partiu://group-info/${activityId}?tab=requests`;
        break;
      case "activity_join_approved":
      case "activity_join_rejected":
        // Redireciona para o mapa focando no evento
        deepLink = `partiu://home?event=${activityId}`;
        break;
      default:
        // Todos os outros casos vão para o evento no mapa
        deepLink = `partiu://home?event=${activityId}`;
        break;
      }

      // Disparar push via gateway único (type guard garante segurança)
      await sendPush({
        userId: receiverId,
        event: nType,
        origin: "activityPushNotifications",
        notification: {
          title: notificationTitle,
          body: notificationBody,
        },
        data: {
          ...pushData,
          relatedId: activityId,
          n_related_id: activityId,
          deepLink: deepLink,
        },
        context: {
          groupId: activityId,
        },
        onDispatchMetrics: (payload) => {
          dispatch.metrics = payload;
        },
      });

      // 🔒 MARCAR COMO ENVIADO para evitar duplicação em retry
      await snap.ref.update({push_sent: true});
      metrics.addWrites(1);

      console.log(
        `✅ [ActivityPush] Push disparado: ${nType} → ${receiverId}`
      );
      metrics.done({
        notificationId,
        receiverId,
        nType,
        relatedId: String(relatedId),
        dedupeKey,
        pushSent: dispatch.metrics?.pushSent ?? true,
        tokensFound: dispatch.metrics?.tokensFound ?? 0,
        tokensDeleted: dispatch.metrics?.tokensDeleted ?? 0,
        pushSuccessCount: dispatch.metrics?.successCount ?? 0,
        pushFailureCount: dispatch.metrics?.failureCount ?? 0,
        pushSkippedReason: dispatch.metrics?.skippedReason,
      });
    } catch (error) {
      console.error(
        "❌ [ActivityPush] Erro ao processar notificação:",
        error
      );
      console.error(`   Notification ID: ${notificationId}`);
      metrics.fail(error, {
        notificationId,
        tokensFound: dispatch.metrics?.tokensFound ?? 0,
        tokensDeleted: dispatch.metrics?.tokensDeleted ?? 0,
        pushSent: dispatch.metrics?.pushSent ?? false,
        pushSkippedReason: dispatch.metrics?.skippedReason,
      });
    }
  });

