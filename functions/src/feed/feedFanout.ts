import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * =====================================================================
 * FEED FANOUT SYSTEM
 * =====================================================================
 *
 * Quando um usuário cria um EventPhoto ou ActivityFeed item, esta função
 * distribui (fanout) o item para a coleção `feeds/{followerId}/items`
 * de cada seguidor.
 *
 * Benefícios:
 * - Aba "Seguindo" vira 1 query simples ao invés de N queries (whereIn chunking)
 * - Escala melhor com muitos seguidores
 * - Reads muito mais baratos
 *
 * Trade-offs:
 * - Mais writes na criação (1 write por seguidor)
 * - Storage aumenta (duplicação de referências)
 *
 * Estrutura do fanout item:
 * feeds/{followerId}/items/{itemId}
 *   - sourceType: 'event_photo' | 'activity_feed'
 *   - sourceId: string (ID do documento original)
 *   - authorId: string (quem criou)
 *   - createdAt: timestamp
 *   - eventId: string (para navegação)
 *   - preview: { ... } (dados mínimos para ordenação/filtro)
 */

// Limite de seguidores por batch (Firestore batch limit = 500)
const BATCH_SIZE = 400;

// Limite máximo de seguidores para fanout (evita explosão de writes)
const MAX_FOLLOWERS_FANOUT = 5000;

/**
 * Interface para item de fanout
 */
interface FanoutItem {
  sourceType: "event_photo" | "activity_feed";
  sourceId: string;
  authorId: string;
  createdAt: admin.firestore.FieldValue;
  eventId: string;
  preview: {
    thumbnailUrl?: string;
    eventTitle?: string;
    eventEmoji?: string;
    userName?: string;
    userPhotoUrl?: string;
  };
}

/**
 * Busca todos os seguidores de um usuário
 * @param {string} userId - ID do usuário
 * @return {Promise<string[]>} Lista de IDs dos seguidores
 */
async function getFollowers(userId: string): Promise<string[]> {
  const followersSnap = await db
    .collection("Users")
    .doc(userId)
    .collection("followers")
    .limit(MAX_FOLLOWERS_FANOUT)
    .get();

  return followersSnap.docs.map((doc) => doc.id);
}

/**
 * Distribui um item para os feeds dos seguidores
 * @param {string} authorId - ID do autor do post
 * @param {FanoutItem} item - Item a ser distribuído
 * @return {Promise<number>} Número de writes realizados
 */
async function fanoutToFollowers(
  authorId: string,
  item: FanoutItem
): Promise<number> {
  const followers = await getFollowers(authorId);

  if (followers.length === 0) {
    console.log(`ℹ️ [FeedFanout] Autor ${authorId} não tem seguidores`);
    return 0;
  }

  console.log(
    `📤 [FeedFanout] Distribuindo para ${followers.length} seguidores`
  );

  // Processa em batches
  let totalWritten = 0;
  for (let i = 0; i < followers.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = followers.slice(i, i + BATCH_SIZE);

    for (const followerId of chunk) {
      // Usa sourceId como docId para facilitar deleção
      const feedItemRef = db
        .collection("feeds")
        .doc(followerId)
        .collection("items")
        .doc(item.sourceId);

      batch.set(feedItemRef, item);
    }

    await batch.commit();
    totalWritten += chunk.length;
    console.log(
      `✅ [FeedFanout] Batch ${Math.floor(i / BATCH_SIZE) + 1}: ${chunk.length} writes`
    );
  }

  return totalWritten;
}

/**
 * Remove um item dos feeds dos seguidores (quando deletado)
 * @param {string} authorId - ID do autor do post
 * @param {string} sourceId - ID do documento original
 * @return {Promise<number>} Número de deletes realizados
 */
async function removeFanoutFromFollowers(
  authorId: string,
  sourceId: string
): Promise<number> {
  const followers = await getFollowers(authorId);

  if (followers.length === 0) {
    return 0;
  }

  console.log(
    `🗑️ [FeedFanout] Removendo de ${followers.length} seguidores`
  );

  let totalDeleted = 0;
  for (let i = 0; i < followers.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = followers.slice(i, i + BATCH_SIZE);

    for (const followerId of chunk) {
      const feedItemRef = db
        .collection("feeds")
        .doc(followerId)
        .collection("items")
        .doc(sourceId);

      batch.delete(feedItemRef);
    }

    await batch.commit();
    totalDeleted += chunk.length;
  }

  return totalDeleted;
}

/**
 * =====================================================================
 * TRIGGER: EventPhotos
 * =====================================================================
 * Quando um EventPhoto é criado/atualizado/deletado
 */
export const onEventPhotoWriteFanout = functions.firestore
  .document("EventPhotos/{photoId}")
  .onWrite(async (change, context) => {
    const photoId = context.params.photoId;
    const before = change.before.data();
    const after = change.after.data();

    // DELETED: remove dos feeds
    if (!after) {
      if (before?.userId) {
        console.log(`🗑️ [FeedFanout] EventPhoto deletado: ${photoId}`);
        const count = await removeFanoutFromFollowers(before.userId, photoId);
        console.log(`✅ [FeedFanout] Removido de ${count} feeds`);
      }
      return;
    }

    // Só faz fanout para posts com status 'active'
    // (ignora under_review, hidden, etc.)
    if (after.status !== "active") {
      // Se mudou de active para outro status, remove dos feeds
      if (before?.status === "active" && after.status !== "active") {
        console.log(
          `🔄 [FeedFanout] EventPhoto mudou de active para ${after.status}: ${photoId}`
        );
        const count = await removeFanoutFromFollowers(after.userId, photoId);
        console.log(`✅ [FeedFanout] Removido de ${count} feeds`);
      }
      return;
    }

    // CREATED ou mudou para active: faz fanout
    const isNewlyActive = !before || before.status !== "active";

    if (isNewlyActive) {
      console.log(`📸 [FeedFanout] EventPhoto ativo: ${photoId}`);

      const item: FanoutItem = {
        sourceType: "event_photo",
        sourceId: photoId,
        authorId: after.userId,
        createdAt: after.createdAt || admin.firestore.FieldValue.serverTimestamp(),
        eventId: after.eventId || "",
        preview: {
          thumbnailUrl: after.thumbnailUrl || after.imageUrl,
          eventTitle: after.eventTitle,
          eventEmoji: after.eventEmoji,
          userName: after.userName,
          userPhotoUrl: after.userPhotoUrl,
        },
      };

      const count = await fanoutToFollowers(after.userId, item);
      console.log(`✅ [FeedFanout] EventPhoto distribuído para ${count} feeds`);
    }
  });

/**
 * =====================================================================
 * TRIGGER: ActivityFeed
 * =====================================================================
 * Quando um ActivityFeed item é criado/atualizado/deletado
 */
export const onActivityFeedWriteFanout = functions.firestore
  .document("ActivityFeed/{itemId}")
  .onWrite(async (change, context) => {
    const itemId = context.params.itemId;
    const before = change.before.data();
    const after = change.after.data();

    // DELETED: remove dos feeds
    if (!after) {
      if (before?.userId) {
        console.log(`🗑️ [FeedFanout] ActivityFeed deletado: ${itemId}`);
        const count = await removeFanoutFromFollowers(before.userId, itemId);
        console.log(`✅ [FeedFanout] Removido de ${count} feeds`);
      }
      return;
    }

    // Só faz fanout para posts com status 'active'
    if (after.status !== "active") {
      if (before?.status === "active" && after.status !== "active") {
        console.log(
          `🔄 [FeedFanout] ActivityFeed mudou de active para ${after.status}: ${itemId}`
        );
        const count = await removeFanoutFromFollowers(after.userId, itemId);
        console.log(`✅ [FeedFanout] Removido de ${count} feeds`);
      }
      return;
    }

    // CREATED ou mudou para active: faz fanout
    const isNewlyActive = !before || before.status !== "active";

    if (isNewlyActive) {
      console.log(`📝 [FeedFanout] ActivityFeed ativo: ${itemId}`);

      const item: FanoutItem = {
        sourceType: "activity_feed",
        sourceId: itemId,
        authorId: after.userId,
        createdAt: after.createdAt || admin.firestore.FieldValue.serverTimestamp(),
        eventId: after.eventId || "",
        preview: {
          eventTitle: after.activityText,
          eventEmoji: after.emoji,
          userName: after.userFullName,
          userPhotoUrl: after.userPhotoUrl,
        },
      };

      const count = await fanoutToFollowers(after.userId, item);
      console.log(`✅ [FeedFanout] ActivityFeed distribuído para ${count} feeds`);
    }
  });

/**
 * =====================================================================
 * TRIGGER: Novo seguidor
 * =====================================================================
 * Quando alguém começa a seguir um usuário, backfill os posts recentes
 * desse usuário no feed do novo seguidor.
 */
export const onNewFollowerBackfillFeed = functions.firestore
  .document("Users/{userId}/followers/{followerId}")
  .onCreate(async (snap, context) => {
    const userId = context.params.userId; // Quem foi seguido
    const followerId = context.params.followerId; // Quem seguiu

    console.log(`👥 [FeedFanout] Novo seguidor: ${followerId} → ${userId}`);

    // Busca os últimos N posts do usuário seguido
    const BACKFILL_LIMIT = 20;

    try {
      // Busca EventPhotos recentes
      const photosSnap = await db
        .collection("EventPhotos")
        .where("userId", "==", userId)
        .where("status", "==", "active")
        .orderBy("createdAt", "desc")
        .limit(BACKFILL_LIMIT)
        .get();

      // Busca ActivityFeed recentes
      const activitiesSnap = await db
        .collection("ActivityFeed")
        .where("userId", "==", userId)
        .where("status", "==", "active")
        .orderBy("createdAt", "desc")
        .limit(BACKFILL_LIMIT)
        .get();

      if (photosSnap.empty && activitiesSnap.empty) {
        console.log(
          `ℹ️ [FeedFanout] Usuário ${userId} não tem posts para backfill`
        );
        return;
      }

      const batch = db.batch();
      let count = 0;

      // Adiciona EventPhotos ao feed do novo seguidor
      for (const doc of photosSnap.docs) {
        const data = doc.data();
        const feedItemRef = db
          .collection("feeds")
          .doc(followerId)
          .collection("items")
          .doc(doc.id);

        batch.set(feedItemRef, {
          sourceType: "event_photo",
          sourceId: doc.id,
          authorId: userId,
          createdAt: data.createdAt,
          eventId: data.eventId || "",
          preview: {
            thumbnailUrl: data.thumbnailUrl || data.imageUrl,
            eventTitle: data.eventTitle,
            eventEmoji: data.eventEmoji,
            userName: data.userName,
            userPhotoUrl: data.userPhotoUrl,
          },
        });
        count++;
      }

      // Adiciona ActivityFeed ao feed do novo seguidor
      for (const doc of activitiesSnap.docs) {
        const data = doc.data();
        const feedItemRef = db
          .collection("feeds")
          .doc(followerId)
          .collection("items")
          .doc(doc.id);

        batch.set(feedItemRef, {
          sourceType: "activity_feed",
          sourceId: doc.id,
          authorId: userId,
          createdAt: data.createdAt,
          eventId: data.eventId || "",
          preview: {
            eventTitle: data.activityText,
            eventEmoji: data.emoji,
            userName: data.userFullName,
            userPhotoUrl: data.userPhotoUrl,
          },
        });
        count++;
      }

      await batch.commit();
      console.log(
        `✅ [FeedFanout] Backfill completo: ${count} posts de ${userId} → feed de ${followerId}`
      );
    } catch (error) {
      console.error("❌ [FeedFanout] Erro no backfill:", error);
    }
  });

/**
 * =====================================================================
 * TRIGGER: Deixou de seguir
 * =====================================================================
 * Quando alguém deixa de seguir, remove os posts desse usuário do feed.
 */
export const onUnfollowCleanupFeed = functions.firestore
  .document("Users/{userId}/followers/{followerId}")
  .onDelete(async (snap, context) => {
    const userId = context.params.userId; // Quem deixou de ser seguido
    const followerId = context.params.followerId; // Quem deixou de seguir

    console.log(`👋 [FeedFanout] Unfollow: ${followerId} ✕ ${userId}`);

    try {
      // Busca todos os items do autor no feed do ex-seguidor
      const feedItemsSnap = await db
        .collection("feeds")
        .doc(followerId)
        .collection("items")
        .where("authorId", "==", userId)
        .get();

      if (feedItemsSnap.empty) {
        console.log(
          `ℹ️ [FeedFanout] Nenhum item de ${userId} no feed de ${followerId}`
        );
        return;
      }

      // Deleta em batches
      const chunks: FirebaseFirestore.QueryDocumentSnapshot[][] = [];
      for (let i = 0; i < feedItemsSnap.docs.length; i += BATCH_SIZE) {
        chunks.push(feedItemsSnap.docs.slice(i, i + BATCH_SIZE));
      }

      let totalDeleted = 0;
      for (const chunk of chunks) {
        const batch = db.batch();
        for (const doc of chunk) {
          batch.delete(doc.ref);
        }
        await batch.commit();
        totalDeleted += chunk.length;
      }

      console.log(
        `✅ [FeedFanout] Removidos ${totalDeleted} items de ${userId} do feed de ${followerId}`
      );
    } catch (error) {
      console.error("❌ [FeedFanout] Erro ao limpar feed:", error);
    }
  });
