#!/usr/bin/env node
/**
 * 🗑️ Script de Limpeza: Remover latitude/longitude do documento principal
 * 
 * Este script remove os campos latitude/longitude de Users/{userId}
 * APÓS a migração para Users/{userId}/private/location estar completa
 * 
 * ⚠️ ATENÇÃO: Execute APENAS após confirmar que:
 *   1. Todos os dados foram migrados para private/location
 *   2. O app foi atualizado para usar displayLatitude/displayLongitude
 *   3. As Cloud Functions foram atualizadas
 * 
 * Uso:
 *   node cleanup_original_location.js --dry-run    # Simular sem escrever
 *   node cleanup_original_location.js              # Executar limpeza
 *   node cleanup_original_location.js --limit=100  # Limitar a 100 usuários
 */

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

// Parse argumentos
const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const limitArg = args.find(a => a.startsWith('--limit='));
const limit = limitArg ? parseInt(limitArg.split('=')[1], 10) : null;

console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log('🗑️  LIMPEZA: Remover latitude/longitude originais');
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
  
  // Opção 2: Service account na raiz do projeto
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
  
  console.error('❌ Erro ao inicializar Firebase');
  process.exit(1);
}

initializeFirebase();
const db = admin.firestore();

// Estatísticas
const stats = {
  total: 0,
  cleaned: 0,
  skipped: 0,
  noPrivateData: 0,
  noOriginalFields: 0,
  errors: 0,
  errorDetails: [],
};

async function cleanupUser(doc) {
  const userId = doc.id;
  const data = doc.data();
  
  stats.total++;
  
  // Verificar se tem os campos originais para remover
  const hasLatitude = data.latitude !== undefined;
  const hasLongitude = data.longitude !== undefined;
  
  if (!hasLatitude && !hasLongitude) {
    stats.noOriginalFields++;
    return;
  }
  
  // Verificar se os dados foram migrados para private/location
  const privateLocationRef = db
    .collection('Users')
    .doc(userId)
    .collection('private')
    .doc('location');
  
  const privateDoc = await privateLocationRef.get();
  
  if (!privateDoc.exists) {
    stats.noPrivateData++;
    console.log(`⚠️  ${userId}: Sem dados em private/location - pulando`);
    return;
  }
  
  const privateData = privateDoc.data();
  if (privateData?.latitude === undefined || privateData?.longitude === undefined) {
    stats.noPrivateData++;
    console.log(`⚠️  ${userId}: Dados incompletos em private/location - pulando`);
    return;
  }
  
  // Remover campos originais
  if (!dryRun) {
    try {
      await db.collection('Users').doc(userId).update({
        latitude: admin.firestore.FieldValue.delete(),
        longitude: admin.firestore.FieldValue.delete(),
      });
      stats.cleaned++;
    } catch (error) {
      stats.errors++;
      stats.errorDetails.push({ userId, error: error.message });
    }
  } else {
    stats.cleaned++;
  }
}

async function cleanup() {
  const batchSize = 500;
  let lastDoc = null;
  let processedCount = 0;
  
  console.log('📊 Iniciando limpeza...\n');
  
  // Verificação de segurança
  if (!dryRun) {
    console.log('⚠️  ATENÇÃO: Este script vai REMOVER os campos latitude/longitude');
    console.log('   dos documentos Users. Pressione Ctrl+C em 5 segundos para cancelar...\n');
    await new Promise(resolve => setTimeout(resolve, 5000));
  }
  
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
    for (const doc of snapshot.docs) {
      await cleanupUser(doc);
    }
    
    processedCount += snapshot.docs.length;
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    
    // Log de progresso
    process.stdout.write(`\r   Processados: ${processedCount} usuários...`);
  }
  
  console.log('\n');
}

async function printStats() {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('📊 RESULTADO DA LIMPEZA');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`   Total processados:     ${stats.total}`);
  console.log(`   ✅ Limpos:             ${stats.cleaned}`);
  console.log(`   ⏭️  Sem campos originais: ${stats.noOriginalFields}`);
  console.log(`   ⚠️  Sem dados privados: ${stats.noPrivateData}`);
  console.log(`   ❌ Erros:              ${stats.errors}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  if (dryRun) {
    console.log('\n🧪 MODO DRY-RUN: Nenhuma alteração foi feita.');
    console.log('   Execute sem --dry-run para aplicar as mudanças.\n');
  } else {
    console.log('\n✅ Limpeza concluída!\n');
    console.log('🔒 Os campos latitude/longitude foram removidos dos documentos Users.');
    console.log('   A localização real agora está APENAS em Users/{userId}/private/location\n');
  }
  
  if (stats.errorDetails.length > 0) {
    console.log('❌ Detalhes dos erros:');
    stats.errorDetails.forEach(({ userId, error }) => {
      console.log(`   - ${userId}: ${error}`);
    });
    console.log('');
  }
}

// Executar
(async () => {
  try {
    await cleanup();
    await printStats();
    process.exit(0);
  } catch (error) {
    console.error('❌ Erro fatal:', error);
    process.exit(1);
  }
})();
