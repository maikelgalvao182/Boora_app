/**
 * Cloud Function: Processa visualizações de perfil agregadas
 *
 * Roda periodicamente (ex: a cada 15 minutos) para:
 * 1. Buscar usuários com visualizações pendentes
 * 2. Agregar visualizações por usuário
 * 3. Enviar notificação única do tipo "X pessoas visualizaram seu perfil"
 * 4. Marcar visualizações como notificadas
 *
 * Deploy:
 * ```bash
 * cd functions
 * npm run deploy
 * ```
 *
 * Teste local:
 * ```bash
 * npm run serve
 * curl http://localhost:5001/{PROJECT_ID}/us-central1/processProfileViewNotifications
 * ```
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {sendPush} from "./services/pushDispatcher";

// Inicializa Firebase Admin (apenas uma vez)
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

interface ProfileView {
  viewerId: string;
  viewedUserId: string;
  viewedAt: admin.firestore.Timestamp;
  notified: boolean;
  viewerName?: string;
  viewerPhotoUrl?: string;
}

interface AggregatedViews {
  [userId: string]: {
    count: number;
    viewIds: string[];
    lastViewedAt: admin.firestore.Timestamp;
    viewerIds: string[];
  };
}

/**
 * Função agendada que roda a cada 15 minutos
 *
 * Configuração no Firebase Console:
 * - Região: us-central1
 * - Schedule: every 15 minutes
 * - Timeout: 540s (9 minutos)
 * - Memory: 512MB
 */
export const processProfileViewNotifications = functions
  .runWith({
    timeoutSeconds: 540,
    memory: "512MB",
  })
  .pubsub.schedule("every 15 minutes")
  .onRun(async () => {
    console.log("🔔 Iniciando processamento de visualizações de perfil");

    try {
      // 1. Busca visualizações não notificadas (últimas 1000)
      const unnotifiedSnapshot = await db
        .collection("ProfileViews")
        .where("notified", "==", false)
        .orderBy("viewedAt", "desc")
        .limit(1000)
        .get();

      if (unnotifiedSnapshot.empty) {
        console.log("✅ Nenhuma visualização pendente");
        return null;
      }

      console.log(`📊 ${unnotifiedSnapshot.size} visualizações pendentes`);

      // 2. Agrupa por usuário visualizado
      const aggregated: AggregatedViews = {};

      unnotifiedSnapshot.docs.forEach((doc) => {
        const data = doc.data() as ProfileView;
        const userId = data.viewedUserId;

        if (!aggregated[userId]) {
          aggregated[userId] = {
            count: 0,
            viewIds: [],
            lastViewedAt: data.viewedAt,
            viewerIds: [],
          };
        }

        aggregated[userId].count++;
        aggregated[userId].viewIds.push(doc.id);
        aggregated[userId].viewerIds.push(data.viewerId);

        // Atualiza timestamp se for mais recente
        const isMoreRecent = data.viewedAt.toMillis() >
          aggregated[userId].lastViewedAt.toMillis();
        if (isMoreRecent) {
          aggregated[userId].lastViewedAt = data.viewedAt;
        }
      });

      console.log(`👥 ${Object.keys(aggregated).length} usuários únicos`);

      // 3. Cria notificações agregadas
      let notificationsSent = 0;
      const batch = db.batch();

      for (const [userId, data] of Object.entries(aggregated)) {
        // Mínimo de 1 visualização para notificar (temporário para teste)
        if (data.count < 1) {
          console.log(
            `⏭️ Pulando ${userId}: apenas ${data.count} ` +
            "visualizações (mínimo: 1)"
          );
          continue;
        }

        // ✅ NOVO: Deletar notificações anteriores do mesmo tipo
        // Garante UMA notificação com o count agregado
        const existingNotifs = await db
          .collection("Notifications")
          .where("n_receiver_id", "==", userId)
          .where("n_type", "==", "profile_views_aggregated")
          .get();

        for (const existingDoc of existingNotifs.docs) {
          batch.delete(existingDoc.ref);
          console.log(`🗑️ Deletando notif: ${existingDoc.id}`);
        }

        // Cria notificação agregada
        const notificationRef = db
          .collection("Notifications")
          .doc();

        batch.set(notificationRef, {
          n_receiver_id: userId, // Campo padrão para queries
          userId: userId, // Campo duplicado para compatibilidade
          n_type: "profile_views_aggregated",
          n_params: {
            count: data.count.toString(),
            lastViewedAt: formatRelativeTime(data.lastViewedAt.toDate()),
            viewerIds: data.viewerIds.join(","),
            emoji: "👀", // Emoji para exibição no widget
          },
          n_related_id: "profile_visits", // Identificador para navegação
          n_read: false,
          n_sender_id: "",
          n_sender_fullname: "Sistema",
          n_sender_photo_link: "",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Marca visualizações como notificadas
        for (const viewId of data.viewIds) {
          const viewRef = db.collection("ProfileViews").doc(viewId);
          batch.update(viewRef, {notified: true});
        }

        notificationsSent++;
      }

      // Commit em lote (atômico)
      await batch.commit();

      console.log(`✅ ${notificationsSent} notificações in-app criadas`);

      // Disparar push notifications para cada usuário
      const pushPromises = Object.entries(aggregated)
        .filter(([, data]) => data.count >= 1)
        .map(([userId, data]) => {
          // Template: profileViewsAggregated
          const count = data.count;
          const body = count === 1 ?
            "1 pessoa da região visualizou seu perfil" :
            `${count} pessoas da região visualizaram seu perfil`;

          // DeepLink: abre tela de visitas ao perfil
          const deepLink = "partiu://profile-visits";

          return sendPush({
            userId: userId,
            event: "profile_views_aggregated",
            notification: {
              title: "👀 Visitas ao perfil",
              body: body,
            },
            data: {
              n_type: "profile_views_aggregated",
              count: data.count.toString(),
              viewerIds: data.viewerIds.join(","),
              deepLink: deepLink,
            },
          });
        });

      await Promise.all(pushPromises);
      console.log(`✅ ${pushPromises.length} push notifications enviadas`);

      return {
        success: true,
        notificationsSent,
        viewsProcessed: unnotifiedSnapshot.size,
      };
    } catch (error) {
      console.error("❌ Erro ao processar visualizações:", error);
      return {
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
      };
    }
  });

/**
 * Função HTTP para trigger manual (útil para testes)
 *
 * Uso:
 * ```bash
 * curl -X POST https://us-central1-{PROJECT_ID}.cloudfunctions.net/processProfileViewNotificationsHttp
 * ```
 */
export const processProfileViewNotificationsHttp = functions.https.onRequest(
  async (req, res) => {
    // Permite apenas POST
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    try {
      console.log("🔔 Trigger manual iniciado via HTTP");

      // Executa a mesma lógica da função agendada
      const unnotifiedSnapshot = await db
        .collection("ProfileViews")
        .where("notified", "==", false)
        .orderBy("viewedAt", "desc")
        .limit(1000)
        .get();

      if (unnotifiedSnapshot.empty) {
        console.log("✅ Nenhuma visualização pendente");
        res.status(200).json({
          success: true,
          message: "Nenhuma visualização pendente",
        });
        return;
      }

      console.log(`📊 ${unnotifiedSnapshot.size} visualizações pendentes`);

      // Agrupa por usuário
      const aggregated: AggregatedViews = {};

      unnotifiedSnapshot.docs.forEach((doc) => {
        const data = doc.data() as ProfileView;
        const userId = data.viewedUserId;

        if (!aggregated[userId]) {
          aggregated[userId] = {
            count: 0,
            viewIds: [],
            lastViewedAt: data.viewedAt,
            viewerIds: [],
          };
        }

        aggregated[userId].count++;
        aggregated[userId].viewIds.push(doc.id);
        aggregated[userId].viewerIds.push(data.viewerId);

        const isMoreRecent = data.viewedAt.toMillis() >
          aggregated[userId].lastViewedAt.toMillis();
        if (isMoreRecent) {
          aggregated[userId].lastViewedAt = data.viewedAt;
        }
      });

      console.log(`👥 ${Object.keys(aggregated).length} usuários únicos`);

      // Cria notificações
      let notificationsSent = 0;
      const batch = db.batch();

      for (const [userId, data] of Object.entries(aggregated)) {
        // Mínimo de 1 visualização para notificar (temporário para teste)
        if (data.count < 1) {
          console.log(
            `⏭️ Pulando ${userId}: apenas ${data.count} ` +
            "visualizações (mínimo: 1)"
          );
          continue;
        }

        // ✅ NOVO: Deletar notificações anteriores do mesmo tipo
        // Garante UMA notificação com o count agregado
        const existingNotifs = await db
          .collection("Notifications")
          .where("n_receiver_id", "==", userId)
          .where("n_type", "==", "profile_views_aggregated")
          .get();

        for (const existingDoc of existingNotifs.docs) {
          batch.delete(existingDoc.ref);
          console.log(`🗑️ Deletando notif: ${existingDoc.id}`);
        }

        const notificationRef = db
          .collection("Notifications")
          .doc();

        batch.set(notificationRef, {
          n_receiver_id: userId, // Campo padrão para queries
          userId: userId, // Campo duplicado para compatibilidade
          n_type: "profile_views_aggregated",
          n_params: {
            count: data.count.toString(),
            lastViewedAt: formatRelativeTime(data.lastViewedAt.toDate()),
            viewerIds: data.viewerIds.join(","),
          },
          n_related_id: null,
          n_read: false,
          n_sender_id: "",
          n_sender_fullname: "Sistema",
          n_sender_photo_link: "",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        for (const viewId of data.viewIds) {
          const viewRef = db.collection("ProfileViews").doc(viewId);
          batch.update(viewRef, {notified: true});
        }

        notificationsSent++;
      }

      await batch.commit();

      console.log(`✅ ${notificationsSent} notificações in-app criadas`);

      // Disparar push notifications
      const pushPromises = Object.entries(aggregated)
        .filter(([, data]) => data.count >= 1)
        .map(([userId, data]) => {
          // Template: profileViewsAggregated
          const count = data.count;
          const body = count === 1 ?
            "1 pessoa da região visualizou seu perfil" :
            `${count} pessoas da região visualizaram seu perfil`;

          // DeepLink: abre tela de visitas ao perfil
          const deepLink = "partiu://profile-visits";

          return sendPush({
            userId: userId,
            event: "profile_views_aggregated",
            notification: {
              title: "👀 Visitas ao perfil",
              body: body,
            },
            data: {
              n_type: "profile_views_aggregated",
              count: data.count.toString(),
              viewerIds: data.viewerIds.join(","),
              deepLink: deepLink,
            },
          });
        });

      await Promise.all(pushPromises);
      console.log(`✅ ${pushPromises.length} push notifications enviadas`);

      res.status(200).json({
        success: true,
        notificationsSent,
        viewsProcessed: unnotifiedSnapshot.size,
      });
    } catch (error) {
      console.error("❌ Erro:", error);
      res.status(500).json({
        error: error instanceof Error ? error.message : "Unknown error",
      });
    }
  }
);

/**
 * Formata timestamp relativo
 * @param {Date} date - Data para formatar
 * @return {string} Tempo relativo formatado
 */
function formatRelativeTime(date: Date): string {
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);

  if (diffMins < 1) return "agora mesmo";
  if (diffMins < 60) return `há ${diffMins}m`;

  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return `há ${diffHours}h`;

  const diffDays = Math.floor(diffHours / 24);
  return `há ${diffDays}d`;
}

