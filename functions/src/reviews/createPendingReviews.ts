import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Cria PendingReviews automaticamente após evento iniciar
 *
 * Trigger: Scheduled function (executa a cada 1 hora)
 * Busca eventos que iniciaram há mais de 6 horas
 *
 * Garante idempotência com flag: pendingReviewsCreated
 *
 * NOTA IMPORTANTE:
 * - schedule.date é o horário de INÍCIO do evento
 * - Criamos PendingReviews 6 horas após o início
 * - TODO V2: Adicionar campo de duração configurável pelo usuário
 */
export const createPendingReviewsScheduled = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .pubsub
  .schedule("every 1 hours")
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    // Constantes de tempo
    const HOURS_AFTER_EVENT_START = 6; // Criar reviews 6h após início do evento

    // Calcular timestamp: now - 6 horas
    // Exemplo: Se são 15h, busca eventos que começaram até 09h
    const sixHoursAgo = admin.firestore.Timestamp.fromMillis(
      now.toMillis() - (HOURS_AFTER_EVENT_START * 60 * 60 * 1000)
    );

    console.log("🔍 [PendingReviews] Buscando eventos finalizados...");
    console.log(
      `📅 [PendingReviews] Processando eventos que INICIARAM até: ${
        sixHoursAgo.toDate().toISOString()
      }`
    );

    try {
      // Buscar eventos que começaram há mais de 6 horas
      // orderBy ANTES do where para evitar problemas de índice
      const eventsSnapshot = await admin.firestore()
        .collection("events")
        .orderBy("schedule.date", "desc")
        .where("schedule.date", "<=", sixHoursAgo)
        .limit(100) // TODO V2: Implementar paginação adequada
        .get();

      console.log(
        `📅 [PendingReviews] ${eventsSnapshot.size} eventos encontrados`
      );

      if (eventsSnapshot.empty) {
        console.log("✅ [PendingReviews] Nenhum evento para processar");
        return null;
      }

      // Filtrar eventos que:
      // 1. Ainda não criaram reviews
      // 2. Não foram deletados
      const eventsToProcess = eventsSnapshot.docs
        .filter((doc) => {
          const data = doc.data();

          console.log(`🔍 [PendingReviews] Evento ${doc.id}:`);
          console.log(`   - deleted: ${data.deleted}`);
          console.log(`   - reviewsCreated: ${data.reviewsCreated}`);
          const dateStr = data.schedule?.date?.toDate?.()?.toISOString();
          console.log(`   - schedule.date: ${dateStr}`);

          // Evento deletado? Pular
          if (!data || data.deleted === true) {
            console.log("   ❌ Pulando - evento deletado");
            return false;
          }

          // Já criou reviews? Pular
          if (data.reviewsCreated === true) {
            console.log("   ❌ Pulando - reviews já criados");
            return false;
          }

          console.log("   ✅ Elegível para processar");
          return true;
        })
        .slice(0, 50); // Processar no máximo 50 por execução

      console.log(
        `✅ [PendingReviews] ${eventsToProcess.length} eventos para processar`
      );

      if (eventsToProcess.length === 0) {
        console.log("ℹ️ [PendingReviews] Nenhum evento elegível");
        return null;
      }

      // Processar cada evento individualmente com error handling
      let successCount = 0;
      let errorCount = 0;

      for (const doc of eventsToProcess) {
        try {
          await processEvent(doc);
          successCount++;
        } catch (error) {
          errorCount++;
          const errMsg = `Erro ao processar evento ${doc.id}`;
          console.error(`❌ [PendingReviews] ${errMsg}:`, error);
          // Continua processando outros eventos
        }
      }

      console.log(
        "✅ [PendingReviews] Processamento concluído: " +
        `${successCount} sucesso, ${errorCount} erro(s)`
      );
      return null;
    } catch (error) {
      // NUNCA fazer throw em scheduled function
      // Apenas loga e retorna null para evitar retry infinito
      console.error(
        "❌ [PendingReviews] Erro fatal, mas scheduler continuará:",
        error
      );
      return null;
    }
  });

/**
 * Processa um evento: cria PendingReview para o owner
 * @param {FirebaseFirestore.DocumentSnapshot} eventDoc Document do evento
 */
async function processEvent(
  eventDoc: FirebaseFirestore.DocumentSnapshot
): Promise<void> {
  const eventId = eventDoc.id;
  const eventData = eventDoc.data();

  // Validações de segurança
  if (!eventData) {
    console.warn(`⚠️ [PendingReviews] Evento ${eventId} sem dados`);
    return;
  }

  if (eventData.deleted === true) {
    console.warn(`⚠️ [PendingReviews] Evento ${eventId} foi deletado`);
    return;
  }

  // Verificar se já foi processado (double-check)
  if (eventData.reviewsCreated === true) {
    console.warn(
      `⚠️ [PendingReviews] Evento ${eventId} já foi processado`
    );
    return;
  }

  const ownerId = eventData.createdBy;
  if (!ownerId) {
    console.warn(`⚠️ [PendingReviews] Evento ${eventId} sem createdBy`);
    // Marcar como processado para não tentar novamente
    await eventDoc.ref.update({
      reviewsCreated: true,
      reviewsCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  const eventTitle = eventData.activityText || "Evento";
  const eventEmoji = eventData.emoji || "🎉";
  const eventLocationName =
    eventData.locationName || eventData.location?.locationName;
  const eventScheduleDate = eventData.schedule?.date;

  console.log(`🎯 [PendingReviews] Processando evento: ${eventId}`);

  // 1. Buscar participantes aprovados com presence="Vou"
  const applicationsSnapshot = await admin.firestore()
    .collection("EventApplications")
    .where("eventId", "==", eventId)
    .where("presence", "==", "Vou")
    .where("status", "in", ["approved", "autoApproved"])
    .get();

  const participantCount = applicationsSnapshot.size;
  console.log(`👥 [PendingReviews] ${participantCount} participantes "Vou"`);

  if (applicationsSnapshot.empty) {
    // Marcar como processado mesmo sem participantes
    await eventDoc.ref.update({
      reviewsCreated: true,
      reviewsCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const msg = `Evento ${eventId} sem participantes - marcado como processado`;
    console.log(`✅ [PendingReviews] ${msg}`);
    return;
  }

  // 2. Buscar perfis dos participantes (BATCH - 1 query por chunk)
  const participantIds = applicationsSnapshot.docs.map(
    (doc) => doc.data().userId
  );

  // ⚠️ IMPORTANTE: Filtrar o owner da lista de participantes
  // O owner não pode avaliar a si mesmo
  const filteredParticipantIds = participantIds.filter((id) => id !== ownerId);
  const userIds = [...new Set(filteredParticipantIds)]; // Remover duplicatas

  // Se não sobrou nenhum participante (owner era o único), não criar review
  if (userIds.length === 0) {
    await eventDoc.ref.update({
      reviewsCreated: true,
      reviewsCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(
      `✅ [PendingReviews] Evento ${eventId} - owner é o único, nada a avaliar`
    );
    return;
  }

  // Firestore permite "in" com até 10 valores, então fazer em chunks
  const participantProfiles: Record<
    string,
    { name: string; photo: string | null; presence_confirmed: boolean }
  > = {};

  for (let i = 0; i < userIds.length; i += 10) {
    const chunk = userIds.slice(i, i + 10);
    const usersSnapshot = await admin.firestore()
      .collection("Users")
      .where(admin.firestore.FieldPath.documentId(), "in", chunk)
      .get();

    usersSnapshot.docs.forEach((userDoc) => {
      const userData = userDoc.data();
      const photoUrl = userData.photoUrl || null;

      participantProfiles[userDoc.id] = {
        name: userData.fullName || "Usuário",
        photo: photoUrl,
        presence_confirmed: false, // Inicializa como false
      };
    });
  }

  const profileCount = Object.keys(participantProfiles).length;
  console.log(`📸 [PendingReviews] ${profileCount} perfis carregados`);

  // 3. Preparar Batch para criar todas as reviews atomicamente
  const batch = admin.firestore().batch();
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    admin.firestore.Timestamp.now().toMillis() +
    (30 * 24 * 60 * 60 * 1000) // 30 dias
  );

  // 3a. Criar PendingReview para o OWNER
  const ownerPendingReviewId = `${eventId}_owner_${ownerId}`;
  const ownerReviewRef = admin.firestore()
    .collection("PendingReviews")
    .doc(ownerPendingReviewId);

  batch.set(ownerReviewRef, {
    pending_review_id: ownerPendingReviewId,
    event_id: eventId,
    reviewer_id: ownerId,
    reviewee_id: "multiple", // Owner avalia múltiplos participantes
    reviewer_role: "owner",
    event_title: eventTitle,
    event_emoji: eventEmoji,
    event_location: eventLocationName,
    event_date: eventScheduleDate,
    participant_ids: userIds, // Evitar duplicatas
    participant_profiles: participantProfiles, // presence_confirmed individual
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    expires_at: expiresAt,
    dismissed: false,
  });

  console.log(
    "✅ [PendingReviews] Owner review criado com " +
    `${userIds.length} participantes (presence_confirmed=false)`
  );

  // 3b. NÃO criar PendingReview para participantes ainda
  // Será criado via onPresenceConfirmed quando owner confirmar presença

  // 4. Marcar evento como processado
  batch.update(eventDoc.ref, {
    reviewsCreated: true,
    reviewsCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  try {
    await batch.commit();
    const logMsg = `Owner review criado para ${userIds.length} participantes`;
    console.log(`✅ [PendingReviews] Evento ${eventId}. ${logMsg}`);
  } catch (error) {
    console.error("❌ [PendingReviews] Erro ao commitar batch:", error);
    throw error;
  }
}

