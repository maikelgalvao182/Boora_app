import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Função agendada para rodar todos os dias à meia-noite (Horário de SP)
 * Remove documentos da coleção 'ProfileVisits' com mais de 7 dias
 */
export const cleanupOldProfileVisits = functions.pubsub
  .schedule("0 0 * * *")
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const db = admin.firestore();
    console.log("🧹 Iniciando limpeza de visitas antigas (ProfileVisits)...");

    // 1. Calcular data de corte (7 dias atrás)
    const now = new Date();
    const cutoffDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    console.log(`📅 Data de corte: ${cutoffDate.toISOString()}`);

    // Limite de segurança para não estourar tempo de execução
    // Vamos processar em batches de 500 (limite do Firestore)
    const BATCH_SIZE = 500;
    const MAX_LOOPS = 20; // 10k docs max
    let totalDeleted = 0;

    for (let i = 0; i < MAX_LOOPS; i++) {
      // Buscar documentos antigos
      const snapshot = await db
        .collection("ProfileVisits")
        .where("visitedAt", "<", cutoffDate)
        .limit(BATCH_SIZE)
        .get();

      if (snapshot.empty) {
        if (i === 0) {
          console.log("✅ Nenhuma visita antiga encontrada para deletar.");
        } else {
          console.log("✅ Limpeza concluída.");
        }
        break;
      }

      // Criar batch de deleção
      const batch = db.batch();
      snapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
      });

      await batch.commit();

      totalDeleted += snapshot.size;
      console.log(`🗑️ Batch ${i + 1}: ${snapshot.size} visitas deletadas.`);

      // Se veio menos que o limite, acabou.
      if (snapshot.size < BATCH_SIZE) {
        break;
      }
    }

    console.log(`🏁 Total removido: ${totalDeleted} documentos.`);
    return null;
  });
