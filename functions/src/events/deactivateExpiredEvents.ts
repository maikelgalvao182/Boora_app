import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Desativa eventos expirados automaticamente
 *
 * Trigger: Scheduled function (executa todos os dias à meia-noite)
 * Busca eventos ativos cuja data do evento (schedule.date) já passou
 * (mesmo dia)
 *
 * Comportamento:
 * - Executa à 00:00 (meia-noite) horário de São Paulo
 * - Busca eventos com isActive=true
 * - Verifica se schedule.date é no dia anterior (ou antes)
 * - Atualiza isActive=false
 * - O Firestore emite automaticamente stream que remove markers no mapa
 *
 * Exemplo:
 * - Hoje: 20/12/2025 00:00
 * - Evento com schedule.date: 19/12/2025 09:26:26
 * - Resultado: isActive = false
 */
export const deactivateExpiredEvents = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .pubsub
  .schedule("0 0 * * *") // Cron: todos os dias à meia-noite
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const todayStart = new Date(now.toDate());

    // Definir início do dia atual (00:00:00)
    todayStart.setHours(0, 0, 0, 0);

    const todayStartTimestamp = admin.firestore.Timestamp
      .fromDate(todayStart);

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
      // Buscar eventos ativos cuja data já passou (antes de hoje 00:00)
      const eventsSnapshot = await admin.firestore()
        .collection("events")
        .where("isActive", "==", true)
        .where("schedule.date", "<", todayStartTimestamp)
        .limit(500) // Processar até 500 eventos por execução
        .get();

      console.log(
        `📅 [DeactivateEvents] ${
          eventsSnapshot.size} eventos expirados encontrados`
      );

      if (eventsSnapshot.empty) {
        console.log(
          "✅ [DeactivateEvents] Nenhum evento expirado para desativar"
        );
        return null;
      }

      // Processar em batch para performance
      const batch = admin.firestore().batch();
      let batchCount = 0;
      const batches: FirebaseFirestore.WriteBatch[] = [batch];

      for (const doc of eventsSnapshot.docs) {
        const data = doc.data();
        const eventDate = data.schedule?.date?.toDate?.();

        console.log(`🔍 [DeactivateEvents] Evento ${doc.id}:`);
        console.log(
          `   - Título: ${data.title || "Sem título"}`
        );
        console.log(
          `   - Data do evento: ${
            eventDate?.toISOString() || "Sem data"}`
        );
        console.log(`   - isActive: ${data.isActive}`);

        // Pular eventos já deletados
        if (data.deleted === true) {
          console.log("   ❌ Pulando - evento deletado");
          continue;
        }

        // Adicionar ao batch
        const currentBatch = batches[batches.length - 1];
        currentBatch.update(doc.ref, {
          isActive: false,
          deactivatedAt: now,
          deactivatedReason: "expired",
        });

        batchCount++;
        console.log(
          "   ✅ Marcado para desativação " +
          `(batch ${batches.length}, item ${batchCount % 500})`
        );

        // Firestore batch limit é 500 operações
        // Criar novo batch se necessário
        if (batchCount % 500 === 0) {
          batches.push(admin.firestore().batch());
          console.log(
            "📦 [DeactivateEvents] Criado novo batch " +
            `(total: ${batches.length})`
          );
        }
      }

      // Commit todos os batches
      console.log(
        `💾 [DeactivateEvents] Commitando ${batches.length} ` +
        `batch(es) com ${batchCount} atualizações...`
      );

      await Promise.all(batches.map((b) => b.commit()));

      console.log(
        `✅ [DeactivateEvents] ${batchCount} eventos desativados ` +
        "com sucesso"
      );
      console.log(
        "📡 [DeactivateEvents] Firestore streams notificarão " +
        "clientes automaticamente"
      );

      return {
        processed: batchCount,
        batches: batches.length,
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

