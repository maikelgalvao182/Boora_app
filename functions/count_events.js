const admin = require('firebase-admin');

admin.initializeApp({ projectId: 'partiu-app' });
const db = admin.firestore();

async function run() {
  const r1 = await db.collection('events').where('status', '==', 'active').count().get();
  console.log('status=active:', r1.data().count);
  
  const r2 = await db.collection('events').where('isActive', '==', true).count().get();
  console.log('isActive=true:', r2.data().count);
  
  const r3 = await db.collection('events').count().get();
  console.log('Total:', r3.data().count);
  
  const sample = await db.collection('events').limit(3).get();
  console.log('\nAmostra de campos:');
  sample.docs.forEach((doc, i) => {
    const d = doc.data();
    const gh = d.geohash ? d.geohash.substring(0,6) : 'null';
    console.log('  ' + (i+1) + '. id=' + doc.id + ', status=' + d.status + ', isActive=' + d.isActive + ', geohash=' + gh);
  });
  
  process.exit(0);
}
run().catch(e => { console.error(e); process.exit(1); });
