import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {DateTime} from "luxon";

// Constantes de configuração
const BATCH_SIZE = 500;
// Configurável via variável de ambiente (padrão: 5 para segurança)
const MAX_CONCURRENT_NOTIFICATION_DELETES = Number(
  process.env.NOTIF_DELETE_CONCURRENCY ?? 5
);

/**
 * Desativa eventos expirados automaticamente
 *
 * Trigger: Scheduled function (executa todos os dias à meia-noite)
 * Busca eventos ativos cuja data do evento (schedule.date) já passou
 *
 * Comportamento:
 * - Executa à 00:00 (meia-noite) horário de São Paulo
 * - Busca eventos com isActive=true (paginado, sem limite)
 * - Verifica se schedule.date < início do dia atual (00:00 de hoje)
 * - Atualiza isActive=false
 * - Deleta todas as notificações relacionadas ao evento (em paralelo)
 * - O Firestore emite automaticamente stream que remove markers no mapa
 *
 * Requisitos:
 * - Índice composto no Firestore: events(isActive ASC, schedule.date ASC)
 *
 * Exemplo:
 * - Função roda: 25/12/2025 00:00
 * - Evento com schedule.date: 20/12/2025 14:00 ou 24/12/2025 23:59
 * - Resultado: isActive = false (eventos anteriores a 25/12 desativados)
 */
export const deactivateExpiredEvents = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .pubsub
  .schedule("0 0 * * *") // Cron: todos os dias à meia-noite
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    // ✅ Uso do Luxon para garantir que o startOf('day') respeite
    // o timezone correto (America/Sao_Paulo), incluindo horário de verão
    // e mudanças históricas, convertendo para UTC corretamente.
    const todayStartTimestamp = admin.firestore.Timestamp.fromDate(
      DateTime.now()
        .setZone("America/Sao_Paulo")
        .startOf("day")
        .toJSDate()
    );

    console.log(
      "🗓️ [DeactivateEvents] Verificando eventos expirados..."
    );
    console.log(
      `📅 [DeactivateEvents] Data/hora atual: ${
        now.toDate().toISOString()}`
    );
    console.log(
      `📅 [DeactivateEvents] Início de hoje: ${
        todayStartTimestamp.toDate().toISOString()}`
    );
    console.log(
      "📅 [DeactivateEvents] Desativando eventos com " +
      `schedule.date < ${todayStartTimestamp.toDate().toISOString()}`
    );

    try {
      // Contadores globais
      let totalBatchCount = 0;
      let totalBatches = 0;
      let totalNotificationsDeleted = 0;
      let pageNumber = 0;

      // ✅ Loop paginado para processar TODOS os eventos expirados
      let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;

      do {
        // Construir query paginada
        // Busca eventos cuja data já passou (schedule.date < início de hoje)
        let query = admin.firestore()
          .collection("events")
          .where("isActive", "==", true)
          .where("schedule.date", "<", todayStartTimestamp)
          .orderBy("schedule.date", "asc") // Necessário para paginação
          .limit(BATCH_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const eventsSnapshot = await query.get();

        if (eventsSnapshot.empty) {
          if (totalBatchCount === 0) {
            console.log(
              "✅ [DeactivateEvents] Nenhum evento expirado para desativar"
            );
          }
          break;
        }

        pageNumber++;

        // Se retornou menos que o batch size, é a última página
        if (eventsSnapshot.size < BATCH_SIZE) {
          lastDoc = null;
        } else {
          // Atualizar cursor para próxima página
          lastDoc = eventsSnapshot.docs[eventsSnapshot.docs.length - 1];
        }

        console.log(
          `📅 [DeactivateEvents] Página ${pageNumber}: ` +
          `${eventsSnapshot.size} eventos encontrados`
        );

        // ✅ IDs desta página apenas (não acumula em memória)
        const pageEventIds: string[] = [];

        // Processar em batch para performance
        const batch = admin.firestore().batch();
        let batchCount = 0;

        for (const doc of eventsSnapshot.docs) {
          const data = doc.data();
          const eventDate = data.schedule?.date?.toDate?.();

          // 🔇 Reduce logs: only log details if DEBUG is enabled
          if (process.env.DEBUG === "true") {
            console.log(`🔍 [DeactivateEvents] Evento ${doc.id}:`);
            console.log(
              `   - Título: ${data.title || data.activityText || "Sem título"}`
            );
            console.log(
              `   - Data do evento: ${
                eventDate?.toISOString() || "Sem data"}`
            );
          }

          // Pular eventos já deletados
          if (data.deleted === true) {
            if (process.env.DEBUG === "true") {
              console.log("   ❌ Pulando - evento deletado");
            }
            continue;
          }

          // ✅ Coletar ID do evento para deletar notificações desta página
          // Apenas se o evento NÃO estiver deletado
          pageEventIds.push(doc.id);

          // Adicionar ao batch
          batch.update(doc.ref, {
            isActive: false,
            status: "inactive",
            deactivatedAt: now,
            deactivatedReason: "expired",
          });

          batchCount++;
          // console.log("   ✅ Marcado para desativação");
          // Removido por excesso de logs
        }

        // Commit batch desta página
        if (batchCount > 0) {
          await batch.commit();
          totalBatchCount += batchCount;
          totalBatches++;
          console.log(
            `💾 [DeactivateEvents] Batch ${totalBatches} commitado ` +
            `(${batchCount} eventos)`
          );
        }

        // ✅ Deletar notificações DESTA PÁGINA imediatamente
        // Evita acúmulo de memória em cenários de escala extrema
        if (pageEventIds.length > 0) {
          console.log(
            "🗑️ [DeactivateEvents] Deletando notificações de " +
            `${pageEventIds.length} eventos da página ${pageNumber}...`
          );

          const pageNotificationsDeleted = await deleteNotificationsInParallel(
            pageEventIds,
            MAX_CONCURRENT_NOTIFICATION_DELETES
          );

          totalNotificationsDeleted += pageNotificationsDeleted;
          console.log(
            `   ✅ ${pageNotificationsDeleted} notificações deletadas`
          );
        }

        // Continuar enquanto houver mais páginas
      } while (lastDoc !== null);

      console.log(
        `✅ [DeactivateEvents] ${totalBatchCount} eventos desativados ` +
        `em ${totalBatches} batch(es)`
      );
      console.log(
        `✅ [DeactivateEvents] ${totalNotificationsDeleted} ` +
        "notificações deletadas no total"
      );

      console.log(
        "📡 [DeactivateEvents] Firestore streams notificarão " +
        "clientes automaticamente"
      );

      return {
        processed: totalBatchCount,
        batches: totalBatches,
        notificationsDeleted: totalNotificationsDeleted,
        timestamp: now.toDate().toISOString(),
      };
    } catch (error) {
      console.error(
        "❌ [DeactivateEvents] Erro ao desativar eventos:",
        error
      );
      throw error;
    }
  });

/**
 * Deleta notificações de múltiplos eventos em paralelo
 * com controle de concorrência para evitar timeout
 * @param {string[]} eventIds - IDs dos eventos
 * @param {number} concurrency - Número máximo de operações simultâneas
 * @return {Promise<number>} - Total de notificações deletadas
 */
async function deleteNotificationsInParallel(
  eventIds: string[],
  concurrency: number
): Promise<number> {
  let totalDeleted = 0;

  // Processar em chunks de 'concurrency' eventos por vez
  for (let i = 0; i < eventIds.length; i += concurrency) {
    const chunk = eventIds.slice(i, i + concurrency);

    const results = await Promise.all(
      chunk.map((eventId) => deleteEventNotifications(eventId))
    );

    totalDeleted += results.reduce((sum, count) => sum + count, 0);

    console.log(
      `   📊 Progresso: ${Math.min(i + concurrency, eventIds.length)}/` +
      `${eventIds.length} eventos processados`
    );
  }

  return totalDeleted;
}

/**
 * Deleta todas as notificações relacionadas a um evento específico
 * Busca por eventId em n_params.eventId e no campo eventId direto
 * @param {string} eventId - ID do evento
 * @return {Promise<number>} - Número de notificações deletadas
 */
async function deleteEventNotifications(eventId: string): Promise<number> {
  const db = admin.firestore();
  if (!eventId) return 0;

  try {
    let docs: FirebaseFirestore.QueryDocumentSnapshot[] = [];

    try {
      // Tentativa 1: OR filter (mais barato)
      // Pode exigir índice composto: Notifications(eventId, n_params.eventId)
      const snap = await db
        .collection("Notifications")
        .where(
          admin.firestore.Filter.or(
            admin.firestore.Filter.where("eventId", "==", eventId),
            admin.firestore.Filter.where("n_params.eventId", "==", eventId)
          )
        )
        .get();

      docs = snap.docs;
    } catch (orError) {
      // Fallback: duas queries + dedupe (para compatibilidade/falta de índice)
      console.warn(
        `⚠️ [DeactivateEvents] OR filter falhou para ${eventId}. ` +
        "Usando fallback lento.",
        orError
      );

      const [direct, nested] = await Promise.all([
        db.collection("Notifications").where("eventId", "==", eventId).get(),
        db.collection("Notifications")
          .where("n_params.eventId", "==", eventId).get(),
      ]);

      const map = new Map<string, FirebaseFirestore.DocumentReference>();
      direct.docs.forEach((d) => map.set(d.id, d.ref));
      nested.docs.forEach((d) => map.set(d.id, d.ref));

      // Se houver documentos no fallback, deleta e retorna aqui mesmo
      const refs = Array.from(map.values());
      console.warn(
        `⚠️ [DeactivateEvents] Fallback retornou ${refs.length} notificações.`
      );

      if (refs.length > 0) {
        for (let i = 0; i < refs.length; i += BATCH_SIZE) {
          const batch = db.batch();
          refs.slice(i, i + BATCH_SIZE).forEach((ref) => batch.delete(ref));
          await batch.commit();
        }
      }
      return refs.length;
    }

    if (docs.length === 0) {
      return 0;
    }

    // Deletar em batch (máximo 500 por batch) - Fluxo principal (OR Filter)
    const refs = docs.map((doc) => doc.ref);

    for (let i = 0; i < refs.length; i += BATCH_SIZE) {
      const batchRefs = refs.slice(i, i + BATCH_SIZE);
      const batch = db.batch();

      batchRefs.forEach((ref) => batch.delete(ref));
      await batch.commit();
    }

    return refs.length;
  } catch (error) {
    console.error(
      `   ❌ Erro ao deletar notificações do evento ${eventId}:`,
      error
    );
  }

  return 0;
}
