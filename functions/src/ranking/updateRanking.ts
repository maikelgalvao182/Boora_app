import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Cloud Function: Atualiza ranking de usuários quando um evento é criado
 *
 * Trigger: onCreate em 'events/{eventId}'
 *
 * Atualiza a coleção userRanking com:
 * - userId, fullName, photoUrl (dados do perfil)
 * - totalEventsCreated (incrementa)
 * - lastEventAt (timestamp do servidor)
 * - lastLat/lastLng (localização do último evento)
 */
export const updateUserRanking = functions.firestore
  .document("events/{eventId}")
  .onCreate(async (snap) => {
    const eventData = snap.data();
    const userId = eventData.createdBy;

    if (!userId) {
      console.warn("⚠️ Evento sem createdBy:", snap.id);
      return null;
    }

    try {
      // Buscar dados do usuário
      const userDoc = await admin
        .firestore()
        .collection("Users")
        .doc(userId)
        .get();

      const userData = userDoc.data();
      const fullName = userData?.fullName || "Usuário";
      const photoUrl = userData?.photoUrl || null;
      const from = userData?.country || null;

      const rankingRef = admin
        .firestore()
        .collection("userRanking")
        .doc(userId);

      // Extrair localização do evento (se disponível)
      const location = eventData.location;
      const updateData: Record<string, unknown> = {
        userId: userId,
        fullName: fullName,
        photoUrl: photoUrl,
        from: from,
        totalEventsCreated: admin.firestore.FieldValue.increment(1),
        lastEventAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Adicionar lat/lng se disponíveis
      if (location?.latitude && location?.longitude) {
        updateData.lastLat = location.latitude;
        updateData.lastLng = location.longitude;
      }

      await rankingRef.set(updateData, {merge: true});

      const msg = "✅ UserRanking atualizado para " + fullName;
      console.log(msg + " (" + userId + ")");
      return null;
    } catch (error) {
      console.error("❌ Erro ao atualizar UserRanking:", error);
      return null;
    }
  });

/**
 * Cloud Function: Atualiza ranking de locais quando um evento é criado
 *
 * Trigger: onCreate em 'events/{eventId}'
 *
 * Atualiza a coleção locationRanking com:
 * - placeId, locationName, formattedAddress, locality
 * - photoReferences (array de URLs)
 * - totalEventsHosted (incrementa)
 * - lastEventAt (timestamp do servidor)
 * - lat/lng (coordenadas do local)
 */
export const updateLocationRanking = functions.firestore
  .document("events/{eventId}")
  .onCreate(async (snap) => {
    const eventData = snap.data();
    const location = eventData.location;

    // placeId está dentro de location
    const placeId = location?.placeId;

    if (!placeId) {
      console.warn("⚠️ Evento sem location.placeId:", snap.id);
      return null;
    }

    try {
      const rankingRef = admin
        .firestore()
        .collection("locationRanking")
        .doc(placeId);

      // Extrair dados do location object
      const locationName = location.locationName || "Local desconhecido";
      const formattedAddress = location.formattedAddress || "";
      const locality = location.locality || null;

      // photoReferences está no root do evento, não dentro de location
      const photoReferences = eventData.photoReferences || [];

      // Buscar visitantes aprovados de todos os eventos neste local
      const eventsQuery = await admin
        .firestore()
        .collection("events")
        .where("location.placeId", "==", placeId)
        .where("isActive", "==", true)
        .where("isCanceled", "==", false)
        .get();

      const allVisitorIds = new Set<string>();
      for (const eventDoc of eventsQuery.docs) {
        const participantIds = eventDoc.data().participants
          ?.participantIds || [];
        participantIds.forEach((id: string) => allVisitorIds.add(id));
      }

      // Buscar dados dos 3 visitantes mais recentes
      const visitorsList: Array<Record<string, unknown>> = [];
      let count = 0;
      for (const userId of Array.from(allVisitorIds)) {
        if (count >= 3) break;

        const userDoc = await admin
          .firestore()
          .collection("Users")
          .doc(userId)
          .get();

        if (userDoc.exists) {
          const userData = userDoc.data();
          visitorsList.push({
            userId: userId,
            fullName: userData?.fullName || "Usuário",
            photoUrl: userData?.photoUrl || null,
          });
          count++;
        }
      }

      const updateData: Record<string, unknown> = {
        placeId: placeId,
        locationName: locationName,
        formattedAddress: formattedAddress,
        totalEventsHosted: admin.firestore.FieldValue.increment(1),
        totalVisitors: allVisitorIds.size,
        visitors: visitorsList,
        lastEventAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Adicionar locality se disponível
      if (locality) {
        updateData.locality = locality;
      }

      // Adicionar photoReferences
      updateData.photoReferences = photoReferences;

      // Adicionar coordenadas se disponíveis
      if (location?.latitude && location?.longitude) {
        updateData.lastLat = location.latitude;
        updateData.lastLng = location.longitude;
      }

      await rankingRef.set(updateData, {merge: true});

      const msg = "✅ LocationRanking atualizado para " + locationName;
      console.log(msg);
      return null;
    } catch (error) {
      console.error("❌ Erro ao atualizar LocationRanking:", error);
      return null;
    }
  });
