import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { ApplicationsGateway } from './gateways/applications.gateway';
import { MessagesGateway } from './gateways/messages.gateway';
import { NotifyController } from './notify.controller';
import { HealthController } from './health.controller';

@Module({
  imports: [],
  controllers: [AppController, NotifyController, HealthController],
  providers: [AppService, ApplicationsGateway, MessagesGateway],
})
export class AppModule {}
