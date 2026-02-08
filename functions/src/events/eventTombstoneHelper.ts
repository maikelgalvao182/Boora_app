import * as admin from "firebase-admin";
import {encodeGeohash} from "../utils/geohash";

const db = admin.firestore();

/**
 * 💀 Grava um tombstone na coleção `event_tombstones` para propagação
 * eficiente de deleções/desativações para todos os usuários do mapa.
 *
 * Os clientes fazem polling leve por região:
 *   where regionKey in [prefixes]
 *   where deletedAt > lastSeenDeletedAt
 *
 * Resultado típico: 0–poucos docs por poll, custo mínimo.
 *
 * @param {string} eventId  ID do evento deletado/desativado
 * @param {number|null} lat      Latitude do evento (para calcular regionKey)
 * @param {number|null} lng      Longitude do evento (para calcular regionKey)
 * @param {string} reason   Motivo: "deleted" | "expired" | "canceled" | "inactive"
 */
export async function writeEventTombstone(
  eventId: string,
  lat: number | null,
  lng: number | null,
  reason: string
): Promise<void> {
  try {
    // regionKey = geohash prefix de 4 chars (~40km x 20km)
    // Permite queries eficientes por região sem listar TODOS os tombstones.
    const regionKey =
      lat != null && lng != null ? encodeGeohash(lat, lng, 4) : "unknown";

    await db.collection("event_tombstones").doc(eventId).set({
      eventId,
      regionKey,
      reason,
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(
      `💀 [Tombstone] Gravado: eventId=${eventId}, region=${regionKey}, reason=${reason}`
    );
  } catch (error) {
    // Fire-and-forget: falha no tombstone NÃO deve bloquear o fluxo principal
    console.error(
      `⚠️ [Tombstone] Erro ao gravar tombstone para ${eventId}:`,
      error
    );
  }
}
