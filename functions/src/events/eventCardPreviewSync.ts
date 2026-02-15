import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {writeEventTombstone} from "./eventTombstoneHelper";

const db = admin.firestore();

/**
 * Helper: Busca dados relevantes do criador para filtragem
 * @param {string | null} creatorId - ID do criador do evento
 * @return {Promise<object>} Dados do criador para filtragem
 */
async function getCreatorFilterData(creatorId: string | null): Promise<{
  creatorGender: string | null;
  creatorBirthYear: number | null;
  creatorAge: number | null;
  creatorVerified: boolean;
  creatorInterests: string[];
  creatorSexualOrientation: string | null;
}> {
  if (!creatorId) {
    return {
      creatorGender: null,
      creatorBirthYear: null,
      creatorAge: null,
      creatorVerified: false,
      creatorInterests: [],
      creatorSexualOrientation: null,
    };
  }

  try {
    const userDoc = await db.collection("Users").doc(creatorId).get();
    if (!userDoc.exists) {
      return {
        creatorGender: null,
        creatorBirthYear: null,
        creatorAge: null,
        creatorVerified: false,
        creatorInterests: [],
        creatorSexualOrientation: null,
      };
    }

    const userData = userDoc.data() || {};

    // Extrair birthYear de birthDate (Timestamp ou Date)
    let birthYear: number | null = null;
    const birthDate = userData.birthDate;
    if (birthDate) {
      if (typeof birthDate.toDate === "function") {
        birthYear = birthDate.toDate().getFullYear();
      } else if (birthDate instanceof Date) {
        birthYear = birthDate.getFullYear();
      }
    }

    return {
      creatorGender: (userData.gender as string) ?? null,
      creatorBirthYear: birthYear,
      creatorAge: (userData.age as number) ?? null,
      creatorVerified: (userData.isVerified as boolean) ?? false,
      creatorInterests: (userData.interests as string[]) ?? [],
      creatorSexualOrientation: (userData.sexualOrientation as string) ?? null,
    };
  } catch (error) {
    console.error(`❌ Erro ao buscar dados do criador ${creatorId}:`, error);
    return {
      creatorGender: null,
      creatorBirthYear: null,
      creatorAge: null,
      creatorVerified: false,
      creatorInterests: [],
      creatorSexualOrientation: null,
    };
  }
}

/**
 * 🎯 Cloud Function: Sincroniza events → events_card_preview
 *
 * Objetivo: versão leve para EventCard (reduz leitura do doc completo).
 * Inclui dados desnormalizados do criador para filtragem sem N+1.
 */
export const onEventWriteUpdateCardPreview = functions.firestore
  .document("events/{eventId}")
  .onWrite(async (change, context) => {
    const eventId = context.params.eventId;

    // ═══════════════════════════════════════════════════
    // 💀 CASO 1: Documento deletado (hard delete)
    // ═══════════════════════════════════════════════════
    if (!change.after.exists) {
      await db.collection("events_card_preview").doc(eventId).delete();

      // Grava tombstone com coordenadas do doc anterior (se disponível)
      const prevData = change.before.data();
      const prevLoc = (prevData?.location || {}) as Record<string, unknown>;
      const prevLat = (prevLoc["latitude"] as number | undefined) ?? null;
      const prevLng = (prevLoc["longitude"] as number | undefined) ?? null;
      await writeEventTombstone(eventId, prevLat, prevLng, "deleted");
      return;
    }

    const data = change.after.data() || {};
    const location = (data.location || {}) as Record<string, unknown>;
    const schedule = (data.schedule || {}) as Record<string, unknown>;
    const participants = (data.participants || {}) as Record<string, unknown>;

    // Extrair coordenadas para query de bounding box
    const lat = (location["latitude"] as number | undefined) ?? null;
    const lng = (location["longitude"] as number | undefined) ?? null;

    // ═══════════════════════════════════════════════════
    // 💀 CASO 2: Evento mudou para inativo/cancelado
    //    Detecta transição isActive true→false, ou isCanceled false→true,
    //    ou status mudou para != "active".
    // ═══════════════════════════════════════════════════
    if (change.before.exists) {
      const prevData = change.before.data() || {};
      const prevIsActive = (prevData.isActive as boolean | undefined) ?? true;
      const prevIsCanceled = (prevData.isCanceled as boolean | undefined) ?? false;
      const prevStatus = (prevData.status as string | undefined) ?? "active";

      const nowIsActive = (data.isActive as boolean | undefined) ?? true;
      const nowIsCanceled = (data.isCanceled as boolean | undefined) ?? false;
      const nowStatus = (data.status as string | undefined) ?? "active";

      const becameInactive = prevIsActive && !nowIsActive;
      const becameCanceled = !prevIsCanceled && nowIsCanceled;
      const statusBecameInactive =
        prevStatus === "active" && nowStatus !== "active";

      if (becameInactive || becameCanceled || statusBecameInactive) {
        const reason = becameCanceled
          ? "canceled"
          : statusBecameInactive
            ? nowStatus
            : "inactive";
        await writeEventTombstone(eventId, lat, lng, reason);
      }
    }

    const status = (data.status as string | undefined) ?? undefined;
    const isCanceled = (data.isCanceled as boolean | undefined) ?? false;
    const isActive =
      (data.isActive as boolean | undefined) ?? (status == null || status == "active");

    const approvedList =
      (participants["approved"] as unknown[] | undefined) ?? undefined;

    const participantsCount =
      (data.participantsCount as number | undefined) ??
      (approvedList != null ? approvedList.length : undefined);

    //  Buscar dados do criador para desnormalização
    const creatorId = (data.createdBy as string) ?? null;
    const creatorData = await getCreatorFilterData(creatorId);

    const previewData = {
      eventId,
      emoji: (data.emoji as string | undefined) ?? "🎉",
      activityText:
        (data.activityText as string | undefined) ??
        (data.title as string | undefined) ??
        "",
      category: (data.category as string | undefined) ?? null,
      // 🆕 Coordenadas para query de bounding box
      location: {
        latitude: lat,
        longitude: lng,
      },
      locationName: location["locationName"] ?? null,
      formattedAddress: location["formattedAddress"] ?? null,
      locality: location["locality"] ?? null,
      state: location["state"] ?? null,
      scheduleDate: schedule["date"] ?? null,
      scheduleFlexible: schedule["flexible"] ?? false,
      privacyType: participants["privacyType"] ?? null,
      minAge: participants["minAge"] ?? null,
      maxAge: participants["maxAge"] ?? null,
      gender: participants["gender"] ?? null,
      createdBy: creatorId,
      participantsCount: participantsCount ?? null,
      isCanceled,
      isActive,
      status: status ?? null,
      // 🆕 Dados desnormalizados do criador
      ...creatorData,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db
      .collection("events_card_preview")
      .doc(eventId)
      .set(previewData, {merge: true});
  });

/**
 * 🔄 Cloud Function: Sincroniza atualizações de perfil → eventos do usuário
 *
 * Quando o usuário atualiza gender, birthDate, interests, isVerified ou sexualOrientation,
 * propaga para todos os eventos_card_preview onde ele é criador.
 */
export const onUserProfileUpdateSyncEvents = functions.firestore
  .document("Users/{userId}")
  .onUpdate(async (change, context) => {
    const userId = context.params.userId;
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    // Campos relevantes para filtragem de eventos
    const relevantFields = ["gender", "birthDate", "interests", "isVerified", "sexualOrientation"];

    // Detectar se algum campo relevante mudou
    const hasRelevantChange = relevantFields.some((field) => {
      const beforeVal = JSON.stringify(before[field] ?? null);
      const afterVal = JSON.stringify(after[field] ?? null);
      return beforeVal !== afterVal;
    });

    if (!hasRelevantChange) {
      return; // Nenhum campo de filtragem mudou
    }

    console.log(`🔄 [onUserProfileUpdateSyncEvents] Usuário ${userId} atualizou dados de filtragem`);

    // Buscar todos os eventos criados por este usuário
    const eventsSnapshot = await db
      .collection("events_card_preview")
      .where("createdBy", "==", userId)
      .get();

    if (eventsSnapshot.empty) {
      console.log(`ℹ️ [onUserProfileUpdateSyncEvents] Usuário ${userId} não tem eventos`);
      return;
    }

    // Calcular novos dados do criador
    let birthYear: number | null = null;
    const birthDate = after.birthDate;
    if (birthDate) {
      if (typeof birthDate.toDate === "function") {
        birthYear = birthDate.toDate().getFullYear();
      } else if (birthDate instanceof Date) {
        birthYear = birthDate.getFullYear();
      }
    }

    const creatorData = {
      creatorGender: (after.gender as string) ?? null,
      creatorBirthYear: birthYear,
      creatorAge: (after.age as number) ?? null,
      creatorVerified: (after.isVerified as boolean) ?? false,
      creatorInterests: (after.interests as string[]) ?? [],
      creatorSexualOrientation: (after.sexualOrientation as string) ?? null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Atualizar todos os eventos em batch
    const batch = db.batch();
    eventsSnapshot.docs.forEach((doc) => {
      batch.update(doc.ref, creatorData);
    });

    await batch.commit();
    console.log(`✅ [onUserProfileUpdateSyncEvents] Atualizados ${eventsSnapshot.size} eventos do usuário ${userId}`);
  });
