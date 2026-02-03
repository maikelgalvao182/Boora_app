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
    console.log("🔍 [updateUserRanking] Trigger iniciado para evento:", snap.id);

    const eventData = snap.data();
    console.log("📦 [updateUserRanking] Dados do evento:", JSON.stringify({
      id: snap.id,
      createdBy: eventData.createdBy,
      activityText: eventData.activityText || eventData.title,
      location: eventData.location ? "presente" : "ausente",
      hasLocation: !!eventData.location,
    }));

    const userId = eventData.createdBy;

    if (!userId) {
      console.warn("⚠️ [updateUserRanking] Evento sem createdBy:", snap.id);
      return null;
    }

    try {
      console.log(`🔍 [updateUserRanking] Buscando usuário: ${userId}`);

      // Buscar dados do usuário
      const userDoc = await admin
        .firestore()
        .collection("Users")
        .doc(userId)
        .get();

      if (!userDoc.exists) {
        console.warn(
          `⚠️ [updateUserRanking] Usuário não encontrado: ${userId}`
        );
        return null;
      }

      const userData = userDoc.data();
      console.log(
        `✅ [updateUserRanking] Usuário encontrado: ${
          userData?.fullName || "Sem nome"
        }`
      );

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
        console.log(
          `📍 [updateUserRanking] Localização: ${
            location.latitude
          }, ${location.longitude}`
        );
      } else {
        console.warn(
          "⚠️ [updateUserRanking] Evento sem coordenadas de localização"
        );
      }

      console.log(`💾 [updateUserRanking] Atualizando userRanking/${userId}`);
      await rankingRef.set(updateData, {merge: true});

      console.log(
        `✅ [updateUserRanking] UserRanking atualizado para ${
          fullName
        } (${userId})`
      );
      return null;
    } catch (error) {
      console.error(
        "❌ [updateUserRanking] Erro ao atualizar UserRanking:",
        error
      );
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
    console.log(
      "🔍 [updateLocationRanking] Trigger iniciado para evento:",
      snap.id
    );

    const eventData = snap.data();
    const location = eventData.location;

    console.log("📦 [updateLocationRanking] Dados do evento:", JSON.stringify({
      id: snap.id,
      hasLocation: !!location,
      placeId: location?.placeId || "ausente",
      locationName: location?.locationName || "ausente",
      activityText: eventData.activityText || eventData.title,
    }));

    // placeId está dentro de location
    const placeId = location?.placeId;

    if (!placeId) {
      console.warn(
        "⚠️ [updateLocationRanking] Evento sem location.placeId:",
        snap.id
      );
      return null;
    }

    try {
      console.log(`🔍 [updateLocationRanking] Processando placeId: ${placeId}`);

      const rankingRef = admin
        .firestore()
        .collection("locationRanking")
        .doc(placeId);

      // Extrair dados do location object
      const locationName = location.locationName || "Local desconhecido";
      const formattedAddress = location.formattedAddress || "";
      const locality = location.locality || null;
      const city = location.city || null;
      const state = location.state || null;
      const country = location.country || null;

      // photoReferences está no root do evento, não dentro de location
      const photoReferences = eventData.photoReferences || [];
      console.log(
        `📸 [updateLocationRanking] photoReferences: ${
          photoReferences.length
        } foto(s)`
      );

      // Buscar visitantes aprovados de todos os eventos neste local
      console.log(
        `🔍 [updateLocationRanking] Buscando eventos no local: ${
          locationName
        }`
      );

      const eventsQuery = await admin
        .firestore()
        .collection("events")
        .where("location.placeId", "==", placeId)
        .where("status", "==", "active")
        .where("isCanceled", "==", false)
        .get();

      console.log(
        `📊 [updateLocationRanking] Encontrados ${
          eventsQuery.size
        } eventos ativos no local`
      );

      const allVisitorIds = new Set<string>();
      for (const eventDoc of eventsQuery.docs) {
        const participantIds = eventDoc.data().participants
          ?.participantIds || [];
        console.log(
          `👥 [updateLocationRanking] Evento ${eventDoc.id}: ${
            participantIds.length
          } participantes`
        );
        participantIds.forEach((id: string) => allVisitorIds.add(id));
      }

      console.log(
        `👥 [updateLocationRanking] Total de visitantes únicos: ${
          allVisitorIds.size
        }`
      );

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

      console.log(
        `👤 [updateLocationRanking] Visitantes processados: ${
          visitorsList.length
        }/3`
      );

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

      // Adicionar campos de localização separados se disponíveis
      if (locality) {
        updateData.locality = locality;
      }
      if (city) {
        updateData.city = city;
      }
      if (state) {
        updateData.state = state;
      }
      if (country) {
        updateData.country = country;
      }

      // Adicionar photoReferences
      updateData.photoReferences = photoReferences;

      // Adicionar coordenadas se disponíveis
      if (location?.latitude && location?.longitude) {
        updateData.lastLat = location.latitude;
        updateData.lastLng = location.longitude;
        console.log(
          `📍 [updateLocationRanking] Coordenadas: ${
            location.latitude
          }, ${location.longitude}`
        );
      }

      console.log(
        `💾 [updateLocationRanking] Atualizando locationRanking/${
          placeId
        }`
      );
      await rankingRef.set(updateData, {merge: true});

      console.log(
        `✅ [updateLocationRanking] LocationRanking atualizado para ${
          locationName
        }`
      );
      return null;
    } catch (error) {
      console.error(
        "❌ [updateLocationRanking] Erro ao atualizar LocationRanking:",
        error
      );
      console.error(
        "❌ [updateLocationRanking] Stack trace:",
        (error as Error).stack
      );
      return null;
    }
  });
