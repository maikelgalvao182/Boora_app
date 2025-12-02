import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import * as admin from 'firebase-admin';

async function bootstrap() {
  // Inicializa Firebase Admin (usa Application Default Credentials)
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: process.env.FIRESTORE_PROJECT_ID || 'wedconnexpro',
    });
  }

  const app = await NestFactory.create(AppModule, {
    logger: ['error', 'warn', 'log', 'debug', 'verbose'],
  });
  
  // Habilita CORS para todas as origens
  app.enableCors({
    origin: '*',
    credentials: true,
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  });

  // Garante que responde a requisições do Cloud Run Load Balancer
  app.enableShutdownHooks();

  // 🔍 LOG CRÍTICO - Verificar PORT do Cloud Run
  console.log('🔍 DEBUG - process.env.PORT =', process.env.PORT);
  console.log('🔍 DEBUG - PORT type:', typeof process.env.PORT);
  
  // Cloud Run SEMPRE define PORT - garantir tipo para TypeScript
  const port = process.env.PORT || '8080';
  console.log('🔍 DEBUG - Using PORT:', port);
  
  await app.listen(port, '0.0.0.0');
  
  console.log(`✅ LISTENING on PORT: ${port}`);
  console.log(`🚀 WebSocket Service running on http://0.0.0.0:${port}`);
  console.log(`📡 Socket.IO ready for connections`);
  console.log(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
}

bootstrap().catch((err) => {
  console.error('❌ Failed to start application:', err);
  process.exit(1);
});
