import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * Backfill para adicionar dados desnormalizados do criador em events_card_preview
 *
 * Campos adicionados:
 * - creatorGender
 * - creatorBirthYear
 * - creatorVerified
 * - creatorInterests
 * - creatorSexualOrientation
 *
 * Uso:
 * curl -X POST https://us-central1-<PROJECT>.cloudfunctions.net/backfillEventCreatorData \
 *   -H "Content-Type: application/json" \
 *   -d '{"limit": 500}'
 *
 * Continue chamando com nextCursor até retornar null.
 */
export const backfillEventCreatorData = functions
  .runWith({
    timeoutSeconds: 540,
    memory: "1GB",
  })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed. Use POST.");
      return;
    }

    const limit = Math.min(Number(req.body?.limit ?? 500), 1000);
    const startAfter = String(req.body?.startAfter ?? "").trim();

    try {
      // Query em events_card_preview
      let query = db.collection("events_card_preview")
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(limit);

      if (startAfter) {
        query = query.startAfter(startAfter);
      }

      const snapshot = await query.get();
      if (snapshot.empty) {
        res.status(200).json({
          updated: 0,
          scanned: 0,
          skipped: 0,
          nextCursor: null,
        });
        return;
      }

      // Coletar IDs únicos de criadores
      const creatorIds = new Set<string>();
      for (const doc of snapshot.docs) {
        const data = doc.data() || {};
        const createdBy = data.createdBy as string | undefined;
        if (createdBy) {
          creatorIds.add(createdBy);
        }
      }

      // Buscar dados dos criadores em paralelo
      const creatorDataMap = new Map<string, {
        gender: string | null;
        birthYear: number | null;
        age: number | null;
        isVerified: boolean;
        interests: string[];
        sexualOrientation: string | null;
      }>();

      const creatorDocs = await Promise.all(
        Array.from(creatorIds).map((id) => db.collection("Users").doc(id).get())
      );

      for (const creatorDoc of creatorDocs) {
        if (!creatorDoc.exists) continue;

        const userData = creatorDoc.data() || {};

        // Extrair birthYear de birthDate
        let birthYear: number | null = null;
        const birthDate = userData.birthDate;
        if (birthDate) {
          if (typeof birthDate.toDate === "function") {
            birthYear = birthDate.toDate().getFullYear();
          } else if (birthDate instanceof Date) {
            birthYear = birthDate.getFullYear();
          }
        }

        creatorDataMap.set(creatorDoc.id, {
          gender: (userData.gender as string) ?? null,
          birthYear,
          age: (userData.age as number) ?? null,
          isVerified: (userData.isVerified as boolean) ?? false,
          interests: (userData.interests as string[]) ?? [],
          sexualOrientation: (userData.sexualOrientation as string) ?? null,
        });
      }

      // Atualizar events_card_preview
      const batch = db.batch();
      let updates = 0;
      let skipped = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data() || {};
        const createdBy = data.createdBy as string | undefined;

        // Já tem dados do criador? Pular
        if (data.creatorGender !== undefined && data.creatorAge !== undefined) {
          skipped++;
          continue;
        }

        if (!createdBy) {
          skipped++;
          continue;
        }

        const creatorData = creatorDataMap.get(createdBy);
        if (!creatorData) {
          // Criador não encontrado - definir defaults
          batch.update(doc.ref, {
            creatorGender: null,
            creatorBirthYear: null,
            creatorAge: null,
            creatorVerified: false,
            creatorInterests: [],
            creatorSexualOrientation: null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          updates++;
          continue;
        }

        batch.update(doc.ref, {
          creatorGender: creatorData.gender,
          creatorBirthYear: creatorData.birthYear,
          creatorAge: creatorData.age,
          creatorVerified: creatorData.isVerified,
          creatorInterests: creatorData.interests,
          creatorSexualOrientation: creatorData.sexualOrientation,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        updates++;
      }

      if (updates > 0) {
        await batch.commit();
      }

      const lastDoc = snapshot.docs[snapshot.docs.length - 1];
      console.log(
        `✅ [backfillEventCreatorData] Processed ${snapshot.size} docs, ` +
        `updated ${updates}, skipped ${skipped}`
      );

      res.status(200).json({
        updated: updates,
        scanned: snapshot.size,
        skipped,
        nextCursor: lastDoc.id,
      });
    } catch (error) {
      console.error("❌ [backfillEventCreatorData] Error:", error);
      res.status(500).send("Internal error");
    }
  });
