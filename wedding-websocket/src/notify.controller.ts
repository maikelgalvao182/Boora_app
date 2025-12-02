import { Controller, Post, Body, Headers, UnauthorizedException } from '@nestjs/common';
import { ApplicationsGateway } from './gateways/applications.gateway';
import { MessagesGateway } from './gateways/messages.gateway';

@Controller('notify')
export class NotifyController {
  constructor(
    private readonly applicationsGateway: ApplicationsGateway,
    private readonly messagesGateway: MessagesGateway,
  ) {}

  @Post()
  notifyChange(
    @Headers('authorization') auth: string,
    @Body() payload: {
      brideId: string;
      vendorId: string;
      type: 'create' | 'update' | 'status_change';
      application: any;
    },
  ) {
    console.log('\n🌐 ===== HTTP NOTIFY ENDPOINT CALLED =====');
    console.log(`📝 Payload received:`, JSON.stringify(payload, null, 2));
    
    // Valida secret interno (evita chamadas não autorizadas)
    const expectedSecret = process.env.INTERNAL_SECRET || 'your-secret-key';
    if (!auth || auth !== `Bearer ${expectedSecret}`) {
      console.log('❌ Invalid authorization');
      throw new UnauthorizedException('Invalid secret');
    }
    console.log('✅ Authorization valid');

    // Encaminha para o gateway notificar via WebSocket
    this.applicationsGateway.notifyApplicationUpdate(payload);

    console.log('🌐 ===== HTTP NOTIFY COMPLETE =====\n');
    return { success: true };
  }

  @Post('message')
  notifyMessage(
    @Headers('authorization') auth: string,
    @Body() payload: {
      senderId: string;
      receiverId: string;
      message: any;
    },
  ) {
    console.log('\n💬 ===== HTTP NOTIFY MESSAGE ENDPOINT CALLED =====');
    console.log(`📝 Payload received:`, JSON.stringify(payload, null, 2));
    
    // Valida secret interno (evita chamadas não autorizadas)
    const expectedSecret = process.env.INTERNAL_SECRET || 'your-secret-key';
    if (!auth || auth !== `Bearer ${expectedSecret}`) {
      console.log('❌ Invalid authorization');
      throw new UnauthorizedException('Invalid secret');
    }
    console.log('✅ Authorization valid');

    // Encaminha para o gateway notificar via WebSocket
    this.messagesGateway.notifyNewMessage(payload);

    console.log('💬 ===== HTTP NOTIFY MESSAGE COMPLETE =====\n');
    return { success: true };
  }
}
