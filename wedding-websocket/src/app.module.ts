import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { ApplicationsGateway } from './gateways/applications.gateway';
import { MessagesGateway } from './gateways/messages.gateway';
import { NotifyController } from './notify.controller';

@Module({
  imports: [],
  controllers: [AppController, NotifyController],
  providers: [AppService, ApplicationsGateway, MessagesGateway],
})
export class AppModule {}
