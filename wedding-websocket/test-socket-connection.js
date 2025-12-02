/**
 * Script de teste para conexão Socket.IO
 * Testa a conexão WebSocket pura (sem HTTP polling)
 */

const io = require('socket.io-client');

const socket = io('http://localhost:8080', {
  transports: ['websocket'], // Force WebSocket only
  forceNew: true,
  reconnection: true,
  reconnectionAttempts: 3,
  reconnectionDelay: 1000,
  auth: {
    token: 'test-token-123' // Token de teste (vai falhar autenticação mas testa conexão)
  }
});

console.log('🔌 Attempting to connect to WebSocket...');

socket.on('connect', () => {
  console.log('✅ Connected successfully!');
  console.log('   Socket ID:', socket.id);
  console.log('   Transport:', socket.io.engine.transport.name);
  
  // Tenta subscrever
  socket.emit('applications:subscribe', {});
  console.log('📡 Subscription sent');
  
  // Desconecta após 2 segundos
  setTimeout(() => {
    console.log('🔌 Disconnecting...');
    socket.disconnect();
  }, 2000);
});

socket.on('connect_error', (error) => {
  console.error('❌ Connection error:', error.message);
});

socket.on('disconnect', (reason) => {
  console.log('🔌 Disconnected:', reason);
  process.exit(0);
});

socket.on('error', (error) => {
  console.error('⚠️ Socket error:', error);
});

// Timeout de 5 segundos
setTimeout(() => {
  console.error('⏱️ Connection timeout');
  process.exit(1);
}, 5000);
