const admin = require('firebase-admin');
const path = require('path');
const serviceAccount = require(path.join(__dirname, 'service-account.json'));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkDoc() {
  const photoId = 'dh5KXvI03xAba3Mvp5LH';
  const expectedUserId = '6KyYn8NGqpSPhpHQJK7PCmgzaqz2';
  
  console.log('Buscando documento:', photoId);
  
  const doc = await db.collection('EventPhotos').doc(photoId).get();
  
  const exists = doc.exists;
  if (exists === false) {
    console.log('Documento NAO existe');
    return;
  }
  
  const data = doc.data();
  console.log('Documento encontrado:');
  console.log('   - id:', doc.id);
  console.log('   - userId:', data.userId);
  console.log('   - status:', data.status);
  console.log('   - eventId:', data.eventId);
  console.log('   - userId match:', data.userId === expectedUserId);
  
  process.exit(0);
}

checkDoc().catch(e => {
  console.error('Erro:', e);
  process.exit(1);
});
