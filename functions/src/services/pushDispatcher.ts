import * as admin from "firebase-admin";

/**
 * 🎯 EVENTOS DE PUSH DO PARTIU
 *
 * Cada tipo representa um evento de domínio que pode gerar
 * uma push notification.
 * Flutter usa n_type para mapear ao template correto
 * (NotificationTemplates.dart).
 */
export type PushEvent =
  // Chat
  | "chat_message"
  | "event_chat_message"
  | "event_join"
  // Atividades
  | "activity_created"
  | "activity_heating_up"
  | "activity_join_request"
  | "activity_join_approved"
  | "activity_join_rejected"
  | "activity_new_participant"
  | "activity_expiring_soon"
  | "activity_canceled"
  // Perfil & Reviews
  | "profile_views_aggregated"
  | "review_pending"
  | "new_review_received"
  // Sistema
  | "system_alert"
  | "custom";

/**
 * 🔒 CATEGORIA DE PREFERÊNCIA DO USUÁRIO
 *
 * Mapeamento para advancedSettings.push_preferences no Firestore.
 * Permite controle granular de notificações.
 */
export type PushPreferenceType =
  | "global"
  | "chat_event"
  | "activity_updates";

/**
 * 📋 CATEGORIZAÇÃO DE EVENTOS
 *
 * Centraliza mapeamento de eventos para preferências.
 * Evita divergências entre type guards e
 * getPreferenceTypeForEvent.
 */
const CHAT_EVENTS: PushEvent[] = [
  "chat_message",
  "event_chat_message",
  "event_join",
];

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
 * 📦 PAYLOAD SEMÂNTICO DO DISPATCHER
 *
 * O dispatcher NÃO recebe title/body.
 * Ele recebe dados brutos e deixa o Flutter formatar usando
 * NotificationTemplates.
 */
export interface SendPushParams {
  userId: string;
  event: PushEvent;
  data: Record<string, string | number | boolean>;
  notification?: {
    title: string;
    body: string;
  };
  silent?: boolean;
  /**
   * Quando true, envia APENAS data (sem notification/aps.alert).
   * Útil para garantir que o app em foreground receba via onMessage
   * e o cliente mostre uma local notification controlada.
   */
  dataOnly?: boolean;
  context?: {
    groupId?: string;
  };
}

/**
 * 🚀 PUSH DISPATCHER - GATEWAY ÚNICO DE NOTIFICAÇÕES
 *
 * ✅ Responsabilidades:
 * - Validar preferências do usuário
 * - Buscar tokens FCM
 * - Montar payload padronizado (Android + iOS)
 * - Enviar via FCM
 * - Limpar tokens inválidos
 * - Log centralizado
 *
 * ❌ NÃO faz:
 * - Lógica de domínio (quem recebe, quando envia)
 * - Formatação de mensagem (Flutter faz isso)
 * - Queries complexas no Firestore
 */
export async function sendPush({
  userId,
  event,
  data,
  notification: explicitNotification,
  silent = false,
  dataOnly = false,
  context,
}: SendPushParams): Promise<void> {
  try {
    // Determinar preferenceType automaticamente baseado no event
    const preferenceType = getPreferenceTypeForEvent(event);

    const isDev = process.env.NODE_ENV !== "production";

    if (isDev) {
      console.log("🔥 [PushDispatcher] sendPush CALLED");
      console.log(`   - userId: ${userId}`);
      console.log(`   - event: ${event}`);
      console.log(`   - preferenceType: ${preferenceType} (auto)`);
      console.log(`   - silent: ${silent}`);
      console.log(`   - context: ${JSON.stringify(context)}`);
      console.log("   - data:", JSON.stringify(data, null, 2));
    } else {
      console.log(`🔥 [PushDispatcher] ${event} → ${userId}`);
    }

    // ETAPA 1: Validar entrada
    if (!userId || !event || !data) {
      console.error("❌ [PushDispatcher] Parâmetros inválidos");
      return;
    }

    // ETAPA 2: Buscar usuário para verificar preferências
    const userDoc = await admin
      .firestore()
      .collection("Users")
      .doc(userId)
      .get();

    if (!userDoc.exists) {
      console.warn(`⚠️ [PushDispatcher] Usuário não encontrado: ${userId}`);
      return;
    }

    const userData = userDoc.data();

    // ETAPA 3: Verificar preferências do usuário
    // Caminho: advancedSettings.push_preferences.{preferenceType}
    const preferences = userData?.advancedSettings?.push_preferences || {};

    // 3.1: Verificar Global (Master Switch)
    // Se global for false, bloqueia tudo
    if (preferences.global === false) {
      console.log(
        "🔕 [PushDispatcher] Push bloqueado por preferência GLOBAL. " +
        `UserId: ${userId}`
      );
      return;
    }

    // 3.2: Verificar Categoria (preferenceType)
    // Default: true (se não existir)
    const isCategoryEnabled = preferences[preferenceType] ?? true;
    if (isCategoryEnabled === false) {
      console.log(
        "🔕 [PushDispatcher] Push bloqueado por preferência " +
        `do usuário. Type: ${preferenceType}, ` +
        `Event: ${event}, UserId: ${userId}`
      );
      return;
    }

    // 3.3: Verificar Grupo Específico (se houver context.groupId)
    if (context?.groupId) {
      const groupId = context.groupId;
      const groupPrefs = preferences.groups?.[groupId];

      // a) Grupo Mutado (Master switch do grupo)
      if (groupPrefs?.muted === true) {
        console.log(
          "🔕 [PushDispatcher] Push bloqueado por grupo mutado: " +
          `${groupId}, UserId: ${userId}`
        );
        return;
      }

      // b) Categoria específica dentro do grupo (Opcional, mas preparado)
      if (preferenceType === "chat_event" && groupPrefs?.chat === false) {
        console.log(
          "🔕 [PushDispatcher] Push de chat bloqueado no grupo: " +
          `${groupId}, UserId: ${userId}`
        );
        return;
      }

      if (
        preferenceType === "activity_updates" &&
        groupPrefs?.activities === false
      ) {
        console.log(
          "🔕 [PushDispatcher] Push de atividade bloqueado no grupo: " +
          `${groupId}, UserId: ${userId}`
        );
        return;
      }
    }

    // ETAPA 4: Log se é push silencioso
    if (silent) {
      console.log(
        "🔇 [PushDispatcher] Push silencioso - sem som/alerta, apenas data"
      );
    }

    // ETAPA 5: Buscar tokens FCM
    if (isDev) {
      console.log(`🔍 [PushDispatcher] Buscando tokens para userId: ${userId}`);
      console.log("📍 [PushDispatcher] Collection: DeviceTokens");
      console.log(
        "🔎 [PushDispatcher] Query: " +
        `where("userId", "==", "${userId}")`
      );
    }

    const tokensSnapshot = await admin
      .firestore()
      .collection("DeviceTokens")
      .where("userId", "==", userId)
      .get();

    if (isDev) {
      console.log(
        "📊 [PushDispatcher] Tokens encontrados: " +
        `${tokensSnapshot.size}`
      );
    }

    if (tokensSnapshot.empty) {
      console.log(`ℹ️ [PushDispatcher] Usuário sem tokens FCM: ${userId}`);
      return;
    }

    const fcmTokens: string[] = [];
    const tokenDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];

    tokensSnapshot.docs.forEach((doc) => {
      const token = doc.data().token;
      if (token && token.length > 0) {
        fcmTokens.push(token);
        tokenDocs.push(doc);
      }
    });

    if (fcmTokens.length === 0) {
      console.log(`ℹ️ [PushDispatcher] Usuário sem tokens válidos: ${userId}`);
      return;
    }

    console.log(
      `🚀 [PushDispatcher] Enviando push (${event}) ` +
      `para ${fcmTokens.length} dispositivo(s). ` +
      `User: ${userId}`
    );

    // ETAPA 6: Montar payload HÍBRIDO (estratégia profissional)
    // 🎯 PUSH HÍBRIDO = Notification (SO) + Data (App)
    //
    // ✅ Notification com título/body genérico:
    //    - Garante que SO exiba mesmo com app fechado
    //    - Apple EXIGE alert{} para mostrar UI
    //    - Android precisa notification{} para som/vibração
    //
    // ✅ Data com payload semântico:
    //    - Flutter usa NotificationTemplates para formatar corretamente
    //    - Navegação precisa mantém n_type, sender_name, etc
    //    - Ignora title/body genérico ao processar
    //
    // 📌 Apps profissionais (WhatsApp, Instagram, Slack) fazem assim
    // 🔔 Regras centrais do modelo final
    // ✅ Todos os eventos mostram UI (entrega garantida)
    // 🔊 Apenas chat_message toca som (atenção seletiva)
    // const shouldShowUI = true; // Unused
    const shouldPlaySound = event === "chat_message" && !silent;

    // Converter data para strings (FCM só aceita strings)
    const stringData: Record<string, string> = {};
    Object.entries(data).forEach(([key, value]) => {
      stringData[key] = String(value);
    });

    // 📝 Texto da notificação (Fallback para quando o app não está rodando)
    // Tenta replicar a lógica do NotificationTemplates.dart para consistência
    const getNotificationContent = (): {title: string; body: string} => {
      // 0. Se o caller forneceu notificação explícita, use-a
      if (explicitNotification) {
        return explicitNotification;
      }

      // 1. Default genérico
      return {
        title: "Notificação",
        body: "Você tem uma nova atualização",
      };
    };

    const notification = getNotificationContent();

    // Se for silent, sempre deve ser data-only.
    const effectiveDataOnly = dataOnly || silent;

    const payload = {
      data: {
        // Dados semânticos do evento (Flutter processa)
        ...stringData,
        // Garante que n_type sempre existe
        n_type: stringData.n_type || event,
        // 🔒 MARCA ORIGEM PARA PREVENIR LOOP INFINITO
        // "push" = payload com notificação; "data" = data-only
        n_origin: effectiveDataOnly ? "data" : "push",
        // Metadados de roteamento (mais relevante pro Android)
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      // 🤖 Android
      android: {
        priority: (shouldPlaySound ? "high" : "normal") as "high" | "normal",
        ...(effectiveDataOnly ? {} : {
          notification: {
            title: notification.title,
            body: notification.body,
            ...(shouldPlaySound ? {sound: "default"} : {}),
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        }),
      },
      // 🍎 iOS (APNs)
      // ⚠️ BADGE: NÃO definido aqui!
      // O app Flutter controla o badge via flutter_app_badger
      // Isso evita que toda notificação resete para 1
      apns: {
        payload: {
          aps: {
            ...(effectiveDataOnly ? {
              // data-only: background push com content-available.
              // iOS entrega ao Flutter via onMessage.
              "content-available": 1,
            } : {
              alert: {
                title: notification.title,
                body: notification.body,
              },
              ...(shouldPlaySound ? {sound: "default"} : {}),
            }),
            // badge: NÃO ENVIAR - Flutter controla via BadgeService
          },
        },
        headers: {
          // background = prioridade menor; alert = 10
          "apns-priority": effectiveDataOnly ? "5" : "10",
          "apns-push-type": effectiveDataOnly ? "background" : "alert",
        },
      },
    };

    if (isDev) {
      console.log("📦 [PushDispatcher] Payload completo:");
      console.log(JSON.stringify(payload, null, 2));
      const tokenCount = fcmTokens.length;
      console.log(`📱 [PushDispatcher] Tokens a enviar (${tokenCount}):`);
      fcmTokens.forEach((token, idx) => {
        const start = token.substring(0, 20);
        const end = token.substring(token.length - 10);
        const preview = `${start}...${end}`;
        console.log(`   ${idx + 1}. ${preview}`);
      });
    }

    console.log("🚀 [PushDispatcher] Enviando via FCM...");

    // ETAPA 7: Enviar via FCM (data-only message)
    const response = await admin.messaging().sendEachForMulticast({
      tokens: fcmTokens,
      data: payload.data,
      android: payload.android,
      apns: payload.apns,
    });

    console.log(
      `✅ [PushDispatcher] Resultado: ${response.successCount} ` +
      `sucessos, ${response.failureCount} falhas`
    );

    // Log detalhado de cada resultado (apenas em dev)
    if (isDev) {
      response.responses.forEach((result, idx) => {
        const token = fcmTokens[idx];
        const start = token.substring(0, 20);
        const end = token.substring(token.length - 10);
        const tokenPreview = `${start}...${end}`;
        if (result.success) {
          console.log(`   ✅ Token ${idx + 1}: SUCCESS`);
          console.log(`      - Token: ${tokenPreview}`);
          console.log(`      - Message ID: ${result.messageId}`);
        } else {
          console.log(`   ❌ Token ${idx + 1}: FAILED`);
          console.log(`      - Token: ${tokenPreview}`);
          console.log(`      - Error code: ${result.error?.code}`);
          console.log(`      - Error message: ${result.error?.message}`);
        }
      });
    } else if (response.failureCount > 0) {
      console.warn(
        "⚠️ [PushDispatcher] Falhas: " +
        `${response.failureCount}/${fcmTokens.length} ` +
        `(event=${event}, user=${userId})`
      );
    }

    // ETAPA 8: Limpar tokens inválidos
    if (response.failureCount > 0) {
      const batch = admin.firestore().batch();
      let deletedCount = 0;

      response.responses.forEach((result, index) => {
        if (!result.success && result.error) {
          const errorCode = result.error.code;
          if (
            errorCode === "messaging/invalid-registration-token" ||
            errorCode === "messaging/registration-token-not-registered"
          ) {
            const tokenDoc = tokenDocs[index];
            batch.delete(tokenDoc.ref);
            deletedCount++;
          }
        }
      });

      if (deletedCount > 0) {
        console.warn(
          `⚠️ [PushDispatcher] Removendo ${deletedCount} ` +
          "tokens inválidos"
        );
        await batch.commit();
      }
    }

    console.log(
      "✅ [PushDispatcher] Push enviado com sucesso! " +
      `Event: ${event}, User: ${userId}, ` +
      `Tokens: ${response.successCount}/${fcmTokens.length}`
    );
  } catch (error) {
    console.error("❌ [PushDispatcher] Erro fatal:", error);
    console.error(`   - Event: ${event}`);
    console.error(`   - UserId: ${userId}`);
    console.error("   - Data:", JSON.stringify(data, null, 2));
  }
}

/**
 * 🔄 HELPER: Mapeia evento para tipo de preferência
 *
 * Permite controle granular de notificações por categoria.
 * Se não especificado, o dispatcher usa este mapeamento automático.
 * @param {PushEvent} event - Tipo do evento
 * @return {PushPreferenceType} Tipo de preferência
 */
export function getPreferenceTypeForEvent(
  event: PushEvent
): PushPreferenceType {
  if (CHAT_EVENTS.includes(event)) {
    return "chat_event";
  }

  if (ACTIVITY_EVENTS.includes(event)) {
    return "activity_updates";
  }

  // Default: global
  return "global";
}
