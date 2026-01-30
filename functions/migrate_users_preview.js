#!/usr/bin/env node

/**
 * 🚀 Script de Migração: Popular users_preview Collection
 * 
 * Objetivo:
 * - Criar documentos em users_preview para todos os usuários existentes em Users
 * - Executar antes de ativar queries no ranking (zero downtime)
 * 
 * Uso:
 *   node migrate_users_preview.js [--batch-size 500] [--dry-run]
 * 
 * Exemplo:
 *   node migrate_users_preview.js --dry-run          # Simula sem escrever
 *   node migrate_users_preview.js                    # Executa migração real
 *   node migrate_users_preview.js --batch-size 200   # Ajusta tamanho do lote
 */

const admin = require('firebase-admin');

const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!serviceAccountPath) {
  console.error('❌ GOOGLE_APPLICATION_CREDENTIALS não definido.');
  console.error('   Exemplo: export GOOGLE_APPLICATION_CREDENTIALS="/caminho/para/serviceAccountKey.json"');
  process.exit(1);
}

// Configurações
const BATCH_SIZE = parseInt(process.argv.find(arg => arg.startsWith('--batch-size='))?.split('=')[1]) || 500;
const DRY_RUN = process.argv.includes('--dry-run');

// Inicializar Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccountPath)
});

const db = admin.firestore();

/**
 * Migra um lote de usuários para users_preview
 */
async function migrateBatch(users) {
  const batch = db.batch();
  let count = 0;

  for (const userDoc of users) {
    const userId = userDoc.id;
    const userData = userDoc.data();

    // Extrair apenas os 6 campos necessários
    const previewData = {
      fullName: userData.fullName || null,
      photoUrl: userData.photoUrl || null,
      locality: userData.locality || null,
      state: userData.state || null,
      overallRating: userData.overallRating || 0,
      jobTitle: userData.jobTitle || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const previewRef = db.collection('users_preview').doc(userId);
    batch.set(previewRef, previewData);
    count++;
  }

  if (!DRY_RUN) {
    await batch.commit();
  }

  return count;
}

/**
 * Executa a migração completa
 */
async function migrateAllUsers() {
  console.log('🚀 Iniciando migração users_preview...');
  console.log(`📊 Configuração: batch-size=${BATCH_SIZE}, dry-run=${DRY_RUN}`);
  console.log('');

  let totalMigrated = 0;
  let lastDoc = null;
  let batchNumber = 1;

  try {
    while (true) {
      // Buscar próximo lote
      let query = db.collection('Users')
        .orderBy('__name__')
        .limit(BATCH_SIZE);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();

      if (snapshot.empty) {
        break; // Fim da migração
      }

      // Migrar lote
      const migrated = await migrateBatch(snapshot.docs);
      totalMigrated += migrated;
      lastDoc = snapshot.docs[snapshot.docs.length - 1];

      console.log(`✅ Lote ${batchNumber}: ${migrated} usuários migrados (total: ${totalMigrated})`);
      batchNumber++;

      // Pequeno delay para não sobrecarregar Firestore
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    console.log('');
    console.log('🎉 Migração concluída!');
    console.log(`📊 Total migrado: ${totalMigrated} usuários`);
    
    if (DRY_RUN) {
      console.log('⚠️  DRY-RUN: Nenhum dado foi escrito (simula\u00e7\u00e3o)');
    } else {
      console.log('✅ Collection users_preview pronta para uso!');
    }

  } catch (error) {
    console.error('❌ Erro durante migração:', error);
    process.exit(1);
  }
}

/**
 * Validação pós-migração
 */
async function validateMigration() {
  console.log('');
  console.log('🔍 Validando migração...');

  const usersCount = await db.collection('Users').count().get();
  const previewCount = await db.collection('users_preview').count().get();

  const usersTotal = usersCount.data().count;
  const previewTotal = previewCount.data().count;

  console.log(`📊 Users: ${usersTotal}`);
  console.log(`📊 users_preview: ${previewTotal}`);

  if (usersTotal === previewTotal) {
    console.log('✅ Validação OK: ambas collections têm o mesmo número de documentos');
  } else {
    console.warn(`⚠️  Divergência: Users (${usersTotal}) vs users_preview (${previewTotal})`);
  }
}

// Executar migração
(async () => {
  try {
    await migrateAllUsers();
    
    if (!DRY_RUN) {
      await validateMigration();
    }
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Erro fatal:', error);
    process.exit(1);
  }
})();
