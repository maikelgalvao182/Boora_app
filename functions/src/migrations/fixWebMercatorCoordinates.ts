/**
 * 🔧 Migration: Corrigir coordenadas Web Mercator no Firestore
 *
 * PROBLEMA:
 * Alguns usuários têm coordenadas em Web Mercator (metros) salvas nos campos
 * latitude/longitude e displayLatitude/displayLongitude, ao invés de graus.
 *
 * DETECÇÃO:
 * - Latitude válida: -90 a +90
 * - Longitude válida: -180 a +180
 * - Valores fora desses ranges são Web Mercator
 *
 * AÇÃO:
 * Como não é possível converter Web Mercator para lat/lng sem saber a origem,
 * a função LIMPA os campos inválidos. O usuário precisará atualizar sua
 * localização novamente.
 *
 * USO:
 * curl -X POST https://us-central1-{PROJECT}.cloudfunctions.net/fixWebMercatorCoordinates
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Inicializa Firebase Admin (apenas uma vez)
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

interface CoordinateFields {
  latitude?: number;
  longitude?: number;
  displayLatitude?: number;
  displayLongitude?: number;
}

interface MigrationResult {
  totalUsers: number;
  usersWithInvalidCoords: number;
  usersCleaned: number;
  errors: string[];
  details: Array<{
    userId: string;
    invalidFields: string[];
    action: string;
  }>;
}

/**
 * Verifica se uma latitude é válida (em graus)
 * @param {number | undefined} lat - Latitude a verificar
 * @return {boolean} True se válida ou ausente
 */
function isValidLatitude(lat: number | undefined): boolean {
  if (lat === undefined || lat === null) return true; // Ausência é OK
  return lat >= -90 && lat <= 90;
}

/**
 * Verifica se uma longitude é válida (em graus)
 * @param {number | undefined} lng - Longitude a verificar
 * @return {boolean} True se válida ou ausente
 */
function isValidLongitude(lng: number | undefined): boolean {
  if (lng === undefined || lng === null) return true; // Ausência é OK
  return lng >= -180 && lng <= 180;
}

/**
 * Função HTTP para executar a migração manualmente
 */
export const fixWebMercatorCoordinates = functions
  .runWith({
    timeoutSeconds: 540,
    memory: "1GB",
  })
  .https.onRequest(async (req, res) => {
    // Apenas POST
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed. Use POST.");
      return;
    }

    console.log("🔧 [Migration] Iniciando correção de coordenadas...");

    const result: MigrationResult = {
      totalUsers: 0,
      usersWithInvalidCoords: 0,
      usersCleaned: 0,
      errors: [],
      details: [],
    };

    try {
      // Buscar todos os usuários
      const usersSnapshot = await db.collection("Users").get();
      result.totalUsers = usersSnapshot.size;

      console.log(`📊 [Migration] Total de usuários: ${result.totalUsers}`);

      const batch = db.batch();
      let batchCount = 0;
      const MAX_BATCH_SIZE = 500;

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        const data = userDoc.data() as CoordinateFields;

        const invalidFields: string[] = [];

        // Verificar cada campo de coordenada
        if (!isValidLatitude(data.latitude)) {
          invalidFields.push(`latitude=${data.latitude}`);
        }
        if (!isValidLongitude(data.longitude)) {
          invalidFields.push(`longitude=${data.longitude}`);
        }
        if (!isValidLatitude(data.displayLatitude)) {
          invalidFields.push(`displayLatitude=${data.displayLatitude}`);
        }
        if (!isValidLongitude(data.displayLongitude)) {
          invalidFields.push(`displayLongitude=${data.displayLongitude}`);
        }

        if (invalidFields.length > 0) {
          result.usersWithInvalidCoords++;

          console.log(`⚠️ [Migration] Usuário ${userId}:`);
          console.log(`   Campos inválidos: ${invalidFields.join(", ")}`);

          // Limpar campos inválidos usando FieldValue.delete()
          const updateData: Record<string, FirebaseFirestore.FieldValue> = {};

          if (!isValidLatitude(data.latitude)) {
            updateData.latitude = admin.firestore.FieldValue.delete();
          }
          if (!isValidLongitude(data.longitude)) {
            updateData.longitude = admin.firestore.FieldValue.delete();
          }
          if (!isValidLatitude(data.displayLatitude)) {
            updateData.displayLatitude = admin.firestore.FieldValue.delete();
          }
          if (!isValidLongitude(data.displayLongitude)) {
            updateData.displayLongitude = admin.firestore.FieldValue.delete();
          }

          // Adicionar ao batch
          batch.update(userDoc.ref, updateData);
          batchCount++;

          result.details.push({
            userId,
            invalidFields,
            action: "cleaned",
          });

          // Commit batch se atingir limite
          if (batchCount >= MAX_BATCH_SIZE) {
            await batch.commit();
            console.log(`✅ [Migration] Batch de ${batchCount} commits`);
            batchCount = 0;
          }
        }
      }

      // Commit batch final
      if (batchCount > 0) {
        await batch.commit();
        console.log(`✅ [Migration] Batch final de ${batchCount} commits`);
      }

      result.usersCleaned = result.usersWithInvalidCoords;

      console.log("✅ [Migration] Migração concluída!");
      console.log(`   Total de usuários: ${result.totalUsers}`);
      console.log(
        `   Usuários com coords inválidas: ${result.usersWithInvalidCoords}`
      );
      console.log(`   Usuários corrigidos: ${result.usersCleaned}`);

      res.status(200).json({
        success: true,
        message: "Migração concluída",
        ...result,
      });
    } catch (error) {
      console.error("❌ [Migration] Erro:", error);

      const errorMessage = error instanceof Error ?
        error.message :
        "Unknown error";

      result.errors.push(errorMessage);

      res.status(500).json({
        success: false,
        message: "Erro na migração",
        error: errorMessage,
        ...result,
      });
    }
  });

/**
 * Função para dry-run (apenas listar usuários afetados, sem modificar)
 */
export const listUsersWithInvalidCoordinates = functions
  .runWith({
    timeoutSeconds: 300,
    memory: "512MB",
  })
  .https.onRequest(async (req, res) => {
    console.log("🔍 [DryRun] Listando usuários com coordenadas inválidas...");

    const result: {
      totalUsers: number;
      usersWithInvalidCoords: number;
      details: Array<{
        userId: string;
        invalidFields: string[];
        values: Record<string, number | undefined>;
      }>;
    } = {
      totalUsers: 0,
      usersWithInvalidCoords: 0,
      details: [],
    };

    try {
      const usersSnapshot = await db.collection("Users").get();
      result.totalUsers = usersSnapshot.size;

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        const data = userDoc.data() as CoordinateFields;

        const invalidFields: string[] = [];

        if (!isValidLatitude(data.latitude)) {
          invalidFields.push("latitude");
        }
        if (!isValidLongitude(data.longitude)) {
          invalidFields.push("longitude");
        }
        if (!isValidLatitude(data.displayLatitude)) {
          invalidFields.push("displayLatitude");
        }
        if (!isValidLongitude(data.displayLongitude)) {
          invalidFields.push("displayLongitude");
        }

        if (invalidFields.length > 0) {
          result.usersWithInvalidCoords++;
          result.details.push({
            userId,
            invalidFields,
            values: {
              latitude: data.latitude,
              longitude: data.longitude,
              displayLatitude: data.displayLatitude,
              displayLongitude: data.displayLongitude,
            },
          });
        }
      }

      console.log("✅ [DryRun] Análise concluída!");
      console.log(`   Total: ${result.totalUsers}`);
      console.log(
        `   Com coordenadas inválidas: ${result.usersWithInvalidCoords}`
      );

      res.status(200).json({
        success: true,
        message: "Análise concluída (dry-run, nada foi modificado)",
        ...result,
      });
    } catch (error) {
      console.error("❌ [DryRun] Erro:", error);

      const errorMessage = error instanceof Error ?
        error.message :
        "Unknown error";

      res.status(500).json({
        success: false,
        error: errorMessage,
      });
    }
  });
