#!/usr/bin/env node
/**
 * 🔒 Script de Migração: Mover latitude/longitude para subcoleção privada
 * 
 * Este script migra os campos latitude/longitude de Users/{userId}
 * para Users/{userId}/private/location
 * 
 * Uso:
 *   node migrate_location_to_private.js --dry-run    # Simular sem escrever
 *   node migrate_location_to_private.js              # Executar migração
 *   node migrate_location_to_private.js --limit=100  # Limitar a 100 usuários
 * 
 * Requisitos:
 *   - Estar na pasta functions/scripts
 *   - Ter o arquivo serviceAccountKey.json na pasta functions/
 *   - Ou estar autenticado via: firebase login
 */

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');
const os = require('os');

// Parse argumentos
const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const limitArg = args.find(a => a.startsWith('--limit='));
const limit = limitArg ? parseInt(limitArg.split('=')[1], 10) : null;

console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log('🔒 MIGRAÇÃO: Localização Real → Subcoleção Privada');
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log(`   Modo: ${dryRun ? '🧪 DRY-RUN (simulação)' : '🚀 PRODUÇÃO (escrita real)'}`);
if (limit) console.log(`   Limite: ${limit} usuários`);
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

// Inicializar Firebase Admin
function initializeFirebase() {
  const projectId = 'partiu-479902';
  
  // Opção 1: serviceAccountKey.json na pasta functions
  const serviceAccountPath = path.join(__dirname, '..', 'serviceAccountKey.json');
  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id || projectId,
    });
    console.log(`✅ Firebase inicializado com serviceAccountKey.json\n`);
    return;
  }
  
  // Opção 2: Service account na raiz do projeto (padrão Firebase)
  const rootPath = path.join(__dirname, '..', '..');
  const files = fs.readdirSync(rootPath);
  const saFile = files.find(f => f.includes('firebase-adminsdk') && f.endsWith('.json'));
  if (saFile) {
    const serviceAccount = require(path.join(rootPath, saFile));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id || projectId,
    });
    console.log(`✅ Firebase inicializado com ${saFile}\n`);
    return;
  }
  
  // Opção 3: GOOGLE_APPLICATION_CREDENTIALS
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: projectId,
    });
    console.log(`✅ Firebase inicializado com GOOGLE_APPLICATION_CREDENTIALS\n`);
    return;
  }
  
  console.error('❌ Erro ao inicializar Firebase:');
  console.error('');
  console.error('   Para executar este script, você precisa:');
  console.error('');
  console.error('   1. Baixar a Service Account Key:');
  console.error('      - Acesse: https://console.firebase.google.com/project/partiu-479902/settings/serviceaccounts/adminsdk');
  console.error('      - Clique em "Gerar nova chave privada"');
  console.error('      - Salve como: functions/serviceAccountKey.json');
  console.error('');
  process.exit(1);
}

initializeFirebase();
const db = admin.firestore();

// Estatísticas
const stats = {
  total: 0,
  migrated: 0,
  skipped: 0,
  alreadyMigrated: 0,
  noCoordinates: 0,
  errors: 0,
  errorDetails: [],
};

async function migrateUser(doc) {
  const userId = doc.id;
  const data = doc.data();
  
  stats.total++;
  
  // Verificar se tem coordenadas
  const latitude = data.latitude;
  const longitude = data.longitude;
  
  if (latitude === undefined || longitude === undefined) {
    stats.noCoordinates++;
    return;
  }
  
  // Verificar se já foi migrado
  const privateLocationRef = db
    .collection('Users')
    .doc(userId)
    .collection('private')
    .doc('location');
  
  const existingPrivate = await privateLocationRef.get();
  
  if (existingPrivate.exists) {
    const existingData = existingPrivate.data();
    if (existingData?.latitude === latitude && existingData?.longitude === longitude) {
      stats.alreadyMigrated++;
      return;
    }
  }
  
  // Migrar
  if (!dryRun) {
    try {
      await privateLocationRef.set({
        latitude,
        longitude,
        migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        migratedFrom: 'script',
      }, { merge: true });
      stats.migrated++;
    } catch (error) {
      stats.errors++;
      stats.errorDetails.push({ userId, error: error.message });
    }
  } else {
    stats.migrated++;
  }
}

async function migrate() {
  const batchSize = 500;
  let lastDoc = null;
  let processedCount = 0;
  
  console.log('📊 Iniciando migração...\n');
  
  while (true) {
    // Verificar limite
    if (limit && processedCount >= limit) {
      console.log(`\n⚠️  Limite de ${limit} usuários atingido`);
      break;
    }
    
    // Construir query
    let query = db
      .collection('Users')
      .orderBy('__name__')
      .limit(Math.min(batchSize, limit ? limit - processedCount : batchSize));
    
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }
    
    const snapshot = await query.get();
    
    if (snapshot.empty) {
      break;
    }
    
    // Processar batch
    const promises = snapshot.docs.map(doc => migrateUser(doc));
    await Promise.all(promises);
    
    processedCount += snapshot.docs.length;
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    
    // Log de progresso
    process.stdout.write(`\r   Processados: ${processedCount} usuários...`);
  }
  
  console.log('\n');
}

async function printStats() {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('📊 RESULTADO DA MIGRAÇÃO');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`   Total processados:    ${stats.total}`);
  console.log(`   ✅ Migrados:          ${stats.migrated}`);
  console.log(`   ⏭️  Já migrados:       ${stats.alreadyMigrated}`);
  console.log(`   ⚠️  Sem coordenadas:   ${stats.noCoordinates}`);
  console.log(`   ❌ Erros:             ${stats.errors}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  if (dryRun) {
    console.log('\n🧪 MODO DRY-RUN: Nenhuma alteração foi feita.');
    console.log('   Execute sem --dry-run para aplicar as mudanças.\n');
  } else {
    console.log('\n✅ Migração concluída!\n');
  }
  
  if (stats.errorDetails.length > 0) {
    console.log('❌ Detalhes dos erros:');
    stats.errorDetails.forEach(({ userId, error }) => {
      console.log(`   - ${userId}: ${error}`);
    });
    console.log('');
  }
}

async function verifyMigration() {
  console.log('🔍 Verificando migração (amostra de 5 usuários)...\n');
  
  const sample = await db
    .collection('Users')
    .where('latitude', '>', 0)
    .limit(5)
    .get();
  
  for (const doc of sample.docs) {
    const userId = doc.id;
    const userData = doc.data();
    
    const privateDoc = await db
      .collection('Users')
      .doc(userId)
      .collection('private')
      .doc('location')
      .get();
    
    const privateData = privateDoc.exists ? privateDoc.data() : null;
    
    const match = privateData && 
      privateData.latitude === userData.latitude && 
      privateData.longitude === userData.longitude;
    
    console.log(`   ${match ? '✅' : '❌'} ${userId.substring(0, 8)}...`);
    console.log(`      Users: (${userData.latitude}, ${userData.longitude})`);
    console.log(`      Private: ${privateData ? `(${privateData.latitude}, ${privateData.longitude})` : 'N/A'}`);
    console.log('');
  }
}

// Executar
(async () => {
  try {
    await migrate();
    await printStats();
    
    if (!dryRun && stats.migrated > 0) {
      await verifyMigration();
    }
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Erro fatal:', error);
    process.exit(1);
  }
})();
