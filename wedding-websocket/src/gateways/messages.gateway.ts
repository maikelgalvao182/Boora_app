import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  MessageBody,
  ConnectedSocket,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import * as admin from 'firebase-admin';

@WebSocketGateway({
  cors: {
    origin: '*',
    credentials: true,
  },
  transports: ['polling', 'websocket'],
  allowEIO3: true,
  pingTimeout: 60000,
  pingInterval: 25000,
})
export class MessagesGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  server: Server;

  private authenticatedClients = new Map<string, string>(); // socketId -> userId
  private userChatSubscriptions = new Map<string, Set<string>>(); // userId -> Set<chatWithUserId>

  async handleConnection(client: Socket) {
    try {
      const token = client.handshake.auth.token;
      if (!token) {
        console.log('❌ No token provided');
        client.disconnect();
        return;
      }

      const decodedToken = await admin.auth().verifyIdToken(token);
      const userId = decodedToken.uid;

      this.authenticatedClients.set(client.id, userId);
      console.log(`✅ Client connected to Messages: ${userId} (socket: ${client.id})`);

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
    if (userId) {
      this.userChatSubscriptions.delete(userId);
    }
    this.authenticatedClients.delete(client.id);
    console.log(`🔌 Client disconnected from Messages: ${userId || client.id}`);
  }

  /**
   * Cliente subscreve para receber mensagens de um chat específico
   */
  @SubscribeMessage('messages:subscribe')
  handleSubscribe(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { withUserId: string },
  ) {
    const userId = this.authenticatedClients.get(client.id);
    if (!userId) return;

    const { withUserId } = data;
    if (!withUserId) {
      console.log(`❌ Missing withUserId for ${userId}`);
      return;
    }

    // Cria room do chat (formato: chat:userA:userB onde userA < userB alfabeticamente)
    const chatRoomId = this.getChatRoomId(userId, withUserId);
    client.join(chatRoomId);

    // Registra subscrição
    if (!this.userChatSubscriptions.has(userId)) {
      this.userChatSubscriptions.set(userId, new Set());
    }
    this.userChatSubscriptions.get(userId)!.add(withUserId);

    console.log(`💬 Client ${userId} subscribed to chat with ${withUserId} (room: ${chatRoomId})`);

    // Envia snapshot inicial (últimas 50 mensagens)
    this.sendInitialSnapshot(client, userId, withUserId);

    // Confirmação
    client.emit('messages:subscription_confirmed', {
      withUserId,
      chatRoomId,
      timestamp: new Date().toISOString(),
    });
  }

  /**
   * Cliente cancela subscrição de um chat
   */
  @SubscribeMessage('messages:unsubscribe')
  handleUnsubscribe(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { withUserId: string },
  ) {
    const userId = this.authenticatedClients.get(client.id);
    if (!userId) return;

    const { withUserId } = data;
    const chatRoomId = this.getChatRoomId(userId, withUserId);
    client.leave(chatRoomId);

    // Remove subscrição
    this.userChatSubscriptions.get(userId)?.delete(withUserId);

    console.log(`🔕 Client ${userId} unsubscribed from chat with ${withUserId}`);
  }

  /**
   * Envia snapshot inicial de mensagens
   */
  private async sendInitialSnapshot(
    client: Socket,
    userId: string,
    withUserId: string,
  ) {
    try {
      const db = admin.firestore();
      
      // Busca mensagens do lado do usuário atual
      const messagesSnapshot = await db
        .collection('Messages')
        .doc(userId)
        .collection(withUserId)
        .orderBy('timestamp', 'desc')
        .limit(50)
        .get();

      const messages = messagesSnapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      }));

      client.emit('messages:snapshot', {
        withUserId,
        messages: messages.reverse(), // Inverte para ordem cronológica
        timestamp: new Date().toISOString(),
      });

      console.log(`📸 Sent initial snapshot to ${userId}: ${messages.length} messages`);
    } catch (error) {
      console.error(`❌ Error sending snapshot to ${userId}:`, error);
    }
  }

  /**
   * Notifica nova mensagem para os participantes do chat
   * Chamado pelo Firestore Trigger
   */
  notifyNewMessage(payload: {
    senderId: string;
    receiverId: string;
    message: any;
  }) {
    console.log('\n💬 ===== NEW MESSAGE NOTIFICATION =====');
    console.log(`📝 From: ${payload.senderId}`);
    console.log(`📝 To: ${payload.receiverId}`);
    console.log(`📝 Message ID: ${payload.message.id}`);

    const chatRoomId = this.getChatRoomId(payload.senderId, payload.receiverId);
    
    // Envia para a room do chat (todos os clientes subscrevidos)
    this.server.to(chatRoomId).emit('messages:new', {
      senderId: payload.senderId,
      receiverId: payload.receiverId,
      message: payload.message,
      timestamp: new Date().toISOString(),
    });

    console.log(`✅ Notified room: ${chatRoomId}`);
    console.log('=====================================\n');
  }

  /**
   * Notifica atualização de mensagem (ex: marcar como lida)
   */
  notifyMessageUpdate(payload: {
    senderId: string;
    receiverId: string;
    messageId: string;
    updates: any;
  }) {
    const chatRoomId = this.getChatRoomId(payload.senderId, payload.receiverId);
    
    this.server.to(chatRoomId).emit('messages:updated', {
      messageId: payload.messageId,
      updates: payload.updates,
      timestamp: new Date().toISOString(),
    });

    console.log(`🔄 Message ${payload.messageId} updated in room ${chatRoomId}`);
  }

  /**
   * Gera ID da room do chat (sempre na mesma ordem alfabética)
   */
  private getChatRoomId(userId1: string, userId2: string): string {
    const [userA, userB] = [userId1, userId2].sort();
    return `chat:${userA}:${userB}`;
  }
}
