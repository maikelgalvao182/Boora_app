import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {createExecutionMetrics} from "../utils/executionMetrics";
import {getBooleanFeatureFlag} from "../utils/featureFlags";

const db = admin.firestore();

/**
 * 🎯 Cloud Function: Sincroniza Users → users_preview
 *
 * Objetivo: Criar versão otimizada com campos básicos para avatar/perfil light
 *
 * Economia esperada:
 * - Users completo: ~5-10KB por documento
 * - users_preview: ~500 bytes (95% menor)
 * - Redução adicional: 40-60% nos custos de leitura do ranking
 *
 * Campos mantidos:
 * - userId, fullName/displayName, username
 * - photoUrl, avatarThumbUrl
 * - isVerified, isVip, locality, state, country, flag
 * - overallRating (opcional para cards)
 */
export const onUserWriteUpdatePreview = functions.firestore
  .document("Users/{userId}")
  .onWrite(async (change, context) => {
    const userId = context.params.userId;
    const metrics = createExecutionMetrics({
      executionId: context.eventId,
    });

    const disableLegacySync =
      await getBooleanFeatureFlag("disableLegacyUsersPreviewSync", false) ||
      await getBooleanFeatureFlag("disableLegacyUsersPreviewTriggers", false);

    if (disableLegacySync) {
      metrics.done({
        userId,
        skipped: true,
        reason: "legacy_preview_sync_disabled_by_flag",
      });
      return;
    }

    // Caso 1: Usuário deletado → deletar preview também
    if (!change.after.exists) {
      try {
        await db.collection("users_preview").doc(userId).delete();
        metrics.addDeletes(1);
        console.log(`✅ users_preview deletado: ${userId}`);
        metrics.done({userId, action: "delete_preview"});
      } catch (error) {
        console.error(`❌ Erro ao deletar preview ${userId}:`, error);
        metrics.fail(error, {userId, action: "delete_preview"});
      }
      return;
    }

    const userData = change.after.data();
    if (!userData) {
      console.error(`❌ Documento Users/${userId} sem dados`);
      metrics.done({userId, action: "missing_user_data"});
      return;
    }

    const fullName = userData.fullName || userData.displayName || null;
    const username = userData.username || userData.userName || null;
    const photoUrl = userData.photoUrl || userData.profilePhoto || null;
    const avatarThumbUrl =
      userData.avatarThumbUrl || userData.photoThumbUrl || null;
    const isVerified = Boolean(userData.user_is_verified || userData.isVerified || userData.verified);
    const isVip = Boolean(userData.user_is_vip || userData.isVip || userData.vip);

    // 🔥 DIFF GUARD: Só escreve se algum campo relevante mudou
    // Evita writes desnecessários (83% das invocações eram idempotentes)
    const previewFields = {
      fullName,
      displayName: fullName,
      username,
      photoUrl,
      avatarThumbUrl,
      isVerified,
      isVip,
      locality: userData.locality || null,
      state: userData.state || null,
      country: userData.country || null,
      flag: userData.flag || null,
      overallRating: userData.overallRating || 0,
    };

    if (change.before.exists) {
      const beforeData = change.before.data();
      if (beforeData) {
        const beforeFullName = beforeData.fullName || beforeData.displayName || null;
        const beforeUsername = beforeData.username || beforeData.userName || null;
        const beforePhotoUrl = beforeData.photoUrl || beforeData.profilePhoto || null;
        const beforeAvatarThumbUrl =
          beforeData.avatarThumbUrl || beforeData.photoThumbUrl || null;
        const beforeIsVerified = Boolean(beforeData.user_is_verified || beforeData.isVerified || beforeData.verified);
        const beforeIsVip = Boolean(beforeData.user_is_vip || beforeData.isVip || beforeData.vip);

        const beforeFields = {
          fullName: beforeFullName,
          displayName: beforeFullName,
          username: beforeUsername,
          photoUrl: beforePhotoUrl,
          avatarThumbUrl: beforeAvatarThumbUrl,
          isVerified: beforeIsVerified,
          isVip: beforeIsVip,
          locality: beforeData.locality || null,
          state: beforeData.state || null,
          country: beforeData.country || null,
          flag: beforeData.flag || null,
          overallRating: beforeData.overallRating || 0,
        };

        // Comparação rápida via JSON (campos são todos primitivos)
        if (JSON.stringify(previewFields) === JSON.stringify(beforeFields)) {
          console.log(
            `⏭️ users_preview SKIP (sem diff): ${userId}`
          );
          metrics.done({userId, skipped: true, reason: "no_diff"});
          return;
        }
      }
    }

    // Caso 2: Criar/atualizar preview com campos básicos
    const previewData = {
      ...previewFields,
      userId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    try {
      await db.collection("users_preview").doc(userId).set(previewData, {
        merge: true,
      });
      metrics.addWrites(1);
      console.log(`✅ users_preview sincronizado: ${userId}`);
      metrics.done({userId, action: "upsert_preview"});
    } catch (error) {
      console.error(`❌ Erro ao sincronizar preview ${userId}:`, error);
      metrics.fail(error, {userId, action: "upsert_preview"});
      throw error; // Permitir retry automático do Firebase
    }
  });
