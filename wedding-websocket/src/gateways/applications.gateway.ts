import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import * as admin from 'firebase-admin';

@WebSocketGateway({
  cors: {
    origin: '*',
    credentials: true,
  },
  transports: ['polling', 'websocket'], // Permite polling para health checks e WebSocket
  allowEIO3: true, // Compatibilidade com Engine.IO v3
  pingTimeout: 60000,
  pingInterval: 25000,
})
export class ApplicationsGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  server: Server;

  private authenticatedClients = new Map<string, string>(); // socketId -> userId

  async handleConnection(client: Socket) {
    try {
      // Valida token do Firebase Auth
      const token = client.handshake.auth.token;
      if (!token) {
        console.log('❌ No token provided');
        client.disconnect();
        return;
      }

      const decodedToken = await admin.auth().verifyIdToken(token);
      const userId = decodedToken.uid;

      this.authenticatedClients.set(client.id, userId);
      console.log(`✅ Client connected: ${userId} (socket: ${client.id})`);

      // Cliente entra na sua própria room
      client.join(`user:${userId}`);
      console.log(`📍 Client ${userId} joined room: user:${userId}`);
    } catch (error) {
      console.error('❌ Authentication failed:', error.message);
      client.disconnect();
    }
  }

  handleDisconnect(client: Socket) {
    const userId = this.authenticatedClients.get(client.id);
    this.authenticatedClients.delete(client.id);
    console.log(`🔌 Client disconnected: ${userId || client.id}`);
  }

  @SubscribeMessage('applications:subscribe')
  handleSubscribe(client: Socket, data: { announcementId?: string }) {
    const userId = this.authenticatedClients.get(client.id);
    if (!userId) return;

    // Subscreve para receber updates como bride
    client.join(`bride:${userId}`);
    console.log(`👰 Client ${userId} joined room: bride:${userId}`);

    // Subscreve para receber updates como vendor
    client.join(`vendor:${userId}`);
    console.log(`🤵 Client ${userId} joined room: vendor:${userId}`);

    console.log(`📡 ${userId} subscribed to applications`);
    console.log(`🏠 Active rooms for ${userId}:`, Array.from(client.rooms));
    
    if (data.announcementId) {
      client.join(`announcement:${data.announcementId}`);
      console.log(`📡 ${userId} subscribed to announcement ${data.announcementId}`);
    }
    
    // 🔥 CONFIRMAÇÃO: Envia mensagem de teste para verificar se cliente recebe
    client.emit('subscription:confirmed', {
      userId,
      rooms: Array.from(client.rooms),
      timestamp: new Date().toISOString(),
    });
    console.log(`✅ Subscription confirmation sent to ${userId}`);
  }

  /**
   * Método chamado pelo Firestore Trigger para notificar mudanças
   */
  notifyApplicationUpdate(payload: {
    brideId: string;
    vendorId: string;
    type: 'create' | 'update' | 'status_change';
    application: any;
  }) {
    console.log('\n🔔 ===== NOTIFICATION REQUEST =====');
    console.log(`📝 Type: ${payload.type}`);
    console.log(`👰 Bride ID: ${payload.brideId}`);
    console.log(`🤵 Vendor ID: ${payload.vendorId}`);
    console.log(`📦 Application:`, JSON.stringify(payload.application, null, 2));
    
    // Verifica quantos clientes estão na room da bride
    const brideRoom = this.server.sockets.adapter.rooms.get(`bride:${payload.brideId}`);
    console.log(`👰 Clients in bride:${payload.brideId} room: ${brideRoom?.size || 0}`);
    if (brideRoom) {
      console.log(`   Socket IDs:`, Array.from(brideRoom));
    }
    
    // Verifica quantos clientes estão na room do vendor
    const vendorRoom = this.server.sockets.adapter.rooms.get(`vendor:${payload.vendorId}`);
    console.log(`🤵 Clients in vendor:${payload.vendorId} room: ${vendorRoom?.size || 0}`);
    if (vendorRoom) {
      console.log(`   Socket IDs:`, Array.from(vendorRoom));
    }
    
    // Notifica a bride
    this.server.to(`bride:${payload.brideId}`).emit('applications:updated', {
      type: payload.type,
      application: payload.application,
    });
    console.log(`📤 Emitted to bride:${payload.brideId}`);

    // Notifica o vendor
    this.server.to(`vendor:${payload.vendorId}`).emit('applications:updated', {
      type: payload.type,
      application: payload.application,
    });
    console.log(`📤 Emitted to vendor:${payload.vendorId}`);

    console.log('🔔 ===== NOTIFICATION COMPLETE =====\n');
  }
}
