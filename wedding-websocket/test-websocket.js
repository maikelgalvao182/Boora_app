/**
 * Script de teste para simular notificação do Firestore Trigger
 * 
 * Como usar:
 * 1. Certifique-se que o WebSocket Service está rodando (npm run start:dev)
 * 2. Rode: node test-websocket.js
 */

const axios = require('axios');

const WEBSOCKET_URL = 'http://localhost:8080';
const INTERNAL_SECRET = 'your-secret-key';

async function testWebSocketNotification() {
  console.log('🧪 Testing WebSocket notification...\n');

  // Payload simulando uma mudança no Firestore
  const payload = {
    brideId: 'test-bride-123',
    vendorId: 'test-vendor-456',
    type: 'status_change',
    application: {
      id: 'test-app-789',
      vendorId: 'test-vendor-456',
      announcementId: 'test-announcement-123',
      categoryId: 'photography',
      status: 'accepted',
      appliedAt: new Date().toISOString(),
      message: 'Test application from script',
    },
  };

  try {
    const response = await axios.post(
      `${WEBSOCKET_URL}/notify`,
      payload,
      {
        headers: {
          'Authorization': `Bearer ${INTERNAL_SECRET}`,
          'Content-Type': 'application/json',
        },
        timeout: 5000,
      }
    );

    console.log('✅ Notification sent successfully!');
    console.log('📨 Response:', response.data);
    console.log('\n💡 Check WebSocket Service logs for:');
    console.log('   "📨 Notified bride test-bride-123 and vendor test-vendor-456"');
    console.log('\n💡 Check Flutter app for real-time update!');
  } catch (error) {
    console.error('❌ Failed to send notification:');
    console.error('   Error:', error.message);
    
    if (error.response) {
      console.error('   Status:', error.response.status);
      console.error('   Data:', error.response.data);
    }
  }
}

// Execute o teste
testWebSocketNotification();
