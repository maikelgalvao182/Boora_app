import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * Cria notificação de novo seguidor
 * @param {object} params - Parâmetros da notificação
 * @return {Promise<void>}
 */
async function createNewFollowerNotification(params: {
  receiverId: string;
  followerId: string;
  followerName: string;
  followerPhotoUrl?: string;
}): Promise<void> {
  const now = admin.firestore.FieldValue.serverTimestamp();

  await db.collection("Notifications").add({
    // Campos padronizados (n_ prefix)
    n_receiver_id: params.receiverId,
    n_type: "new_follower",
    n_origin: "cloud_function",
    n_created_at: now,
    timestamp: now,
    n_read: false,
    n_related_id: params.followerId,

    // Dados do sender (quem seguiu)
    n_sender_id: params.followerId,
    n_sender_fullname: params.followerName,
    n_sender_photo_url: params.followerPhotoUrl || null,

    // Parâmetros para template
    n_params: {
      title: `${params.followerName} começou a te seguir`,
      body: "Toque para ver o perfil",
      preview: `${params.followerName} te seguiu`,
      followerId: params.followerId,
      followerName: params.followerName,
      deepLink: `partiu://profile/${params.followerId}`,
    },

    // Campos legados para compatibilidade
    userId: params.receiverId,
    type: "new_follower",
    createdAt: now,
    read: false,
  });

  console.log(
    `✅ Notificação de novo seguidor criada para ${params.receiverId}`
  );
}

/**
 * Envia push notification de novo seguidor
 * @param {object} params - Parâmetros
 * @return {Promise<void>}
 */
async function sendNewFollowerPush(params: {
  receiverId: string;
  followerId: string;
  followerName: string;
}): Promise<void> {
  try {
    // Buscar FCM tokens do receiver na coleção DeviceTokens (raiz)
    const tokensSnap = await db
      .collection("DeviceTokens")
      .where("userId", "==", params.receiverId)
      .get();

    if (tokensSnap.empty) {
      console.log(`⚠️ Usuário ${params.receiverId} não tem FCM tokens`);
      return;
    }

    // ✅ Extrair token do campo 'token' dentro de cada documento
    const tokens: string[] = [];
    const tokenDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];

    tokensSnap.docs.forEach((doc) => {
      const token = doc.data().token;
      if (token && typeof token === "string" && token.length > 0) {
        tokens.push(token);
        tokenDocs.push(doc);
      }
    });

    if (tokens.length === 0) {
      console.log(`⚠️ Usuário ${params.receiverId} sem tokens válidos`);
      return;
    }

    console.log(
      `📱 [FollowPush] Enviando para ${tokens.length} dispositivo(s)`
    );

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: "Novo seguidor 👋",
        body: `${params.followerName} começou a te seguir`,
      },
      data: {
        type: "new_follower",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        deepLink: `partiu://profile/${params.followerId}`,
        senderId: params.followerId,
        senderName: params.followerName,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
          channelId: "boora_high_importance",
        },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(
      `📱 Push enviado: ${response.successCount}/${tokens.length} sucesso`
    );

    // Limpar tokens inválidos
    response.responses.forEach((resp, idx) => {
      if (
        !resp.success &&
        (resp.error?.code === "messaging/invalid-registration-token" ||
          resp.error?.code === "messaging/registration-token-not-registered")
      ) {
        // ✅ Usar o documento correto para deletar
        tokenDocs[idx].ref
          .delete()
          .catch((e) => console.debug("Token cleanup:", e));
      }
    });
  } catch (error) {
    console.error("❌ Erro ao enviar push de novo seguidor:", error);
  }
}

/**
 * followUser
 * Input: { targetUid: string }
 * Output: { status: 'followed' | 'already_following', followersCount: number }
 */
export const followUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be logged in to follow."
    );
  }

  const uid = context.auth.uid;
  const targetUid = data.targetUid;

  if (!targetUid || typeof targetUid !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "The function must be called with one argument 'targetUid'."
    );
  }

  if (uid === targetUid) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "You cannot follow yourself."
    );
  }

  const userRef = db.collection("Users").doc(uid);
  const targetUserRef = db.collection("Users").doc(targetUid);

  const followingRef = userRef.collection("following").doc(targetUid);
  const followersRef = targetUserRef.collection("followers").doc(uid);

  try {
    const result = await db.runTransaction(async (transaction) => {
      const followingDoc = await transaction.get(followingRef);

      if (followingDoc.exists) {
        return {status: "already_following"};
      }

      // Create doc in users/{uid}/following/{targetUid}
      transaction.set(followingRef, {
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Create doc in users/{targetUid}/followers/{uid}
      transaction.set(followersRef, {
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Increment followingCount for current user
      transaction.update(userRef, {
        followingCount: admin.firestore.FieldValue.increment(1),
      });

      // Increment followersCount for target user
      transaction.update(targetUserRef, {
        followersCount: admin.firestore.FieldValue.increment(1),
      });

      return {status: "followed"};
    });

    // Se seguiu com sucesso, criar notificação e enviar push
    if (result.status === "followed") {
      // Buscar dados do usuário que seguiu (follower)
      const followerDoc = await userRef.get();
      const followerData = followerDoc.data();

      // ✅ Campo correto no Firestore: fullName (camelCase)
      const followerName =
        followerData?.fullName ||
        followerData?.userFullname ||
        followerData?.user_fullname ||
        "Alguém";

      // ✅ Campo correto no Firestore: profilePicture
      const followerPhotoUrl =
        followerData?.profilePicture ||
        followerData?.userPhotoUrl ||
        followerData?.user_photo_url;

      console.log(
        `📤 [Follow] Criando notificação - followerName: ${followerName}`
      );

      // Criar notificação in-app
      await createNewFollowerNotification({
        receiverId: targetUid,
        followerId: uid,
        followerName,
        followerPhotoUrl,
      });

      // Enviar push notification (async, não bloqueia resposta)
      sendNewFollowerPush({
        receiverId: targetUid,
        followerId: uid,
        followerName,
      }).catch((err) =>
        console.error("Erro ao enviar push de novo seguidor:", err)
      );
    }

    return result;
  } catch (error) {
    console.error("Error following user:", error);
    throw new functions.https.HttpsError("internal", "Unable to follow user.");
  }
});

/**
 * unfollowUser
 * Input: { targetUid: string }
 * Output: { status: 'unfollowed' | 'not_following' }
 */
export const unfollowUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be logged in to unfollow."
    );
  }

  const uid = context.auth.uid;
  const targetUid = data.targetUid;

  if (!targetUid || typeof targetUid !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "The function must be called with one argument 'targetUid'."
    );
  }

  const userRef = db.collection("Users").doc(uid);
  const targetUserRef = db.collection("Users").doc(targetUid);

  const followingRef = userRef.collection("following").doc(targetUid);
  const followersRef = targetUserRef.collection("followers").doc(uid);

  try {
    const result = await db.runTransaction(async (transaction) => {
      const followingDoc = await transaction.get(followingRef);

      if (!followingDoc.exists) {
        return {status: "not_following"};
      }

      // Delete doc in users/{uid}/following/{targetUid}
      transaction.delete(followingRef);

      // Delete doc in users/{targetUid}/followers/{uid}
      transaction.delete(followersRef);

      // Decrement followingCount for current user
      transaction.update(userRef, {
        followingCount: admin.firestore.FieldValue.increment(-1),
      });

      // Decrement followersCount for target user
      transaction.update(targetUserRef, {
        followersCount: admin.firestore.FieldValue.increment(-1),
      });

      return {status: "unfollowed"};
    });

    return result;
  } catch (error) {
    console.error("Error unfollowing user:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Unable to unfollow user."
    );
  }
});
