import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

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

    // Caso 1: Usuário deletado → deletar preview também
    if (!change.after.exists) {
      try {
        await db.collection("users_preview").doc(userId).delete();
        console.log(`✅ users_preview deletado: ${userId}`);
      } catch (error) {
        console.error(`❌ Erro ao deletar preview ${userId}:`, error);
      }
      return;
    }

    const userData = change.after.data();
    if (!userData) {
      console.error(`❌ Documento Users/${userId} sem dados`);
      return;
    }

    const fullName = userData.fullName || userData.displayName || null;
    const username = userData.username || userData.userName || null;
    const photoUrl = userData.photoUrl || userData.profilePhoto || null;
    const avatarThumbUrl =
      userData.avatarThumbUrl || userData.photoThumbUrl || null;
    const isVerified = Boolean(userData.user_is_verified || userData.isVerified || userData.verified);
    const isVip = Boolean(userData.user_is_vip || userData.isVip || userData.vip);

    // Caso 2: Criar/atualizar preview com campos básicos
    const previewData = {
      userId,
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
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    try {
      await db.collection("users_preview").doc(userId).set(previewData, {
        merge: true,
      });
      console.log(`✅ users_preview sincronizado: ${userId}`);
    } catch (error) {
      console.error(`❌ Erro ao sincronizar preview ${userId}:`, error);
      throw error; // Permitir retry automático do Firebase
    }
  });
