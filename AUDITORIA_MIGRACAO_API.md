# 🔄 Auditoria de Migração para API REST

## 📋 Resumo Executivo

**Projeto:** Partiu App (Flutter + Firebase)  
**Data:** 02/02/2026  
**Objetivo:** Avaliar e planejar migração da arquitetura atual (escrita direta Firestore + Cloud Functions) para uma arquitetura baseada em API REST.

---

## 📊 Arquitetura Atual

### Stack Tecnológico
- **Frontend:** Flutter (iOS/Android/Web)
- **Backend:** Firebase Cloud Functions (Node.js/TypeScript)
- **Banco de Dados:** Firestore (NoSQL)
- **Autenticação:** Firebase Auth
- **Storage:** Cloud Storage
- **Push Notifications:** FCM
- **Pagamentos:** RevenueCat

### Padrão Atual de Comunicação
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Flutter   │────▶│  Firestore  │◀────│  Cloud      │
│     App     │     │  (Escrita   │     │  Functions  │
│             │◀────│   Direta)   │────▶│  (Triggers) │
└─────────────┘     └─────────────┘     └─────────────┘
```

---

## 📁 Coleções Firestore Identificadas (25 coleções)

### Coleções Principais
| Coleção | Escrita Cliente | Escrita Functions | Leitura Cliente |
|---------|-----------------|-------------------|-----------------|
| `Users` | ✅ Perfil próprio | ✅ Rating/VIP/Verificação | ✅ Perfis públicos |
| `users` | ✅ (espelho legado) | ✅ | ✅ |
| `users_preview` | ❌ | ✅ (sync automático) | ✅ |
| `events` | ✅ CRUD próprio | ✅ Desativação | ✅ |
| `events_map` | ❌ | ✅ (sync) | ✅ |
| `events_card_preview` | ❌ | ✅ (sync) | ✅ |
| `EventApplications` | ✅ Criar/atualizar | ✅ Aprovação automática | ✅ |
| `EventChats` | ❌ | ✅ (criação/update) | ✅ Participantes |
| `EventChats/{id}/Messages` | ✅ Enviar mensagens | ❌ | ✅ |
| `Connections` | ✅ Conversas 1-1 | ✅ Conversas de evento | ✅ |
| `Messages` | ✅ Mensagens 1-1 | ❌ | ✅ |
| `Notifications` | ✅ Criar notificação | ✅ (triggers) | ✅ Próprias |
| `DeviceTokens` | ✅ CRUD próprio | ❌ | ✅ |
| `Reviews` | ✅ Criar reviews | ❌ | ✅ |
| `PendingReviews` | ✅ Atualizar presença | ✅ (scheduled) | ✅ Próprias |
| `ProfileVisits` | ✅ Registrar visita | ❌ | ✅ VIP apenas |
| `ProfileViews` | ✅ Criar view | ❌ | ✅ |
| `userRanking` | ❌ | ✅ | ✅ |
| `locationRanking` | ❌ | ✅ | ✅ |
| `ranking_filters` | ❌ | ✅ | ✅ |
| `reports` | ✅ Criar report | ❌ | ❌ |
| `blockedUsers` | ✅ CRUD | ❌ | ✅ |
| `ActivityFeed` | ✅ Criar | ✅ (soft delete) | ✅ |
| `feeds/{userId}/items` | ❌ | ✅ (fanout) | ✅ Próprio |
| `SubscriptionStatus` | ❌ | ✅ (webhook) | ✅ Próprio |
| `DiditSessions` | ✅ Criar sessão | ✅ (webhook) | ✅ Próprias |
| `EventPhotos` | ✅ CRUD + likes | ❌ | ✅ |
| `push_receipts` | ❌ | ✅ | ❌ |
| `AppInfo` | ❌ | ❌ | ✅ |

---

## ⚡ Cloud Functions Atuais (Inventário Completo)

### 🔥 Firestore Triggers (21 funções)

| Função | Trigger Path | Descrição |
|--------|--------------|-----------|
| `onEventCreated` | `events/{eventId}` | Cria application + chat + conversação para criador |
| `onApplicationApproved` | `EventApplications/{id}` | Adiciona participante ao chat do evento |
| `onActivityCreatedNotification` | `events/{eventId}` | Notifica usuários próximos (30km) |
| `onActivityHeatingUp` | `events/{eventId}` | Notifica quando evento "esquenta" (3/5/10 participantes) |
| `onJoinRequestNotification` | `EventApplications/{id}` | Notifica dono sobre pedido de entrada |
| `onJoinDecisionNotification` | `EventApplications/{id}` | Notifica usuário sobre decisão |
| `onActivityCanceledNotification` | `events/{eventId}` | Notifica participantes sobre cancelamento |
| `onPrivateMessageCreated` | `Messages/{uid}/{pid}/{mid}` | Push notification chat 1-1 |
| `onEventChatMessageCreated` | `EventChats/{id}/Messages/{mid}` | Push notification chat grupo |
| `onReportCreated` | `reports/{reportId}` | Processa report de evento |
| `onUserCreatedReferral` | `Users/{userId}` | Processa código de referral |
| `onUserAvatarUpdated` | `Users/{userId}` | Sincroniza avatar em eventos |
| `onUserLocationUpdated` | `Users/{userId}/private/location` | Atualiza grid de usuários |
| `syncEventToMap` | `events/{eventId}` | Sincroniza para `events_map` |
| `onEventWriteUpdateCardPreview` | `events/{eventId}` | Sincroniza para `events_card_preview` |
| `onUserWriteUpdatePreview` | `Users/{userId}` | Sincroniza para `users_preview` |
| `cleanupOnEventDelete` | `events/{eventId}` | Limpa dados relacionados ao deletar evento |
| `onReviewCreated` | `Reviews/{reviewId}` | Processa nova review |
| `onPresenceConfirmed` | `PendingReviews/{id}` | Cria reviews para participantes confirmados |
| `onEventPhotoWriteFanout` | `EventPhotos/{id}` | Distribui foto para feeds de seguidores |
| `onActivityFeedWriteFanout` | `ActivityFeed/{id}` | Distribui atividade para feeds |

### 📞 Callable Functions (8 funções)

| Função | Descrição | Parâmetros |
|--------|-----------|------------|
| `getPeople` | Busca pessoas no mapa (geo-query complexa) | boundingBox, filters, plan |
| `deleteEvent` | Deleta evento + cleanup completo | eventId |
| `removeUserApplication` | Remove participante do evento | eventId, userId |
| `removeParticipant` | Remove participante (alias) | eventId, participantId |
| `followUser` | Seguir usuário | targetUserId |
| `unfollowUser` | Deixar de seguir | targetUserId |
| `deleteChatMessage` | Soft delete de mensagem | chatType, messageId, partnerId |
| `deleteUserAccount` | Deleta conta + todos os dados | (nenhum - usa context.auth) |
| `getProfileVisitsCount` | Retorna contador de visitas | (nenhum - usa context.auth) |

### ⏰ Scheduled Functions (8 cron jobs)

| Função | Schedule | Descrição |
|--------|----------|-----------|
| `deactivateExpiredEvents` | `0 0 * * *` (meia-noite) | Desativa eventos expirados |
| `cleanupOldProfileVisits` | `0 0 * * *` (meia-noite) | Remove visitas > 7 dias |
| `cleanupOldNotifications` | `10 3 * * *` (03:10) | Remove notificações > 10 dias |
| `processProfileViewNotifications` | `every 15 minutes` | Agrega e cria notificações de visualização |
| `createPendingReviewsScheduled` | `every 1 hour` | Cria pending reviews para eventos finalizados |
| `backfillMissingCreatorAvatarUrl` | `every 6 hours` | Corrige avatars faltantes |
| `syncRankingFilters` | `every 30 minutes` | Atualiza filtros agregados do ranking |
| `backfillMissingNotificationTimestamps` | `every 2 hours` | Backfill de timestamps |

### 🌐 HTTP Webhooks (3 funções)

| Função | Endpoint | Descrição |
|--------|----------|-----------|
| `revenueCatWebhook` | POST | Processa eventos de assinatura (VIP) |
| `diditWebhook` | POST | Processa verificação facial/ID |
| `faceioWebhook` | POST | Webhook legado de verificação |

### 🔧 Funções de Migração/Debug (7 funções)

| Função | Tipo | Descrição |
|--------|------|-----------|
| `patchAddCountryFlag` | HTTP | Adiciona country flag aos usuários |
| `patchRemoveFormattedAddress` | HTTP | Remove campo formattedAddress |
| `resyncUsersPreview` | HTTP | Resincroniza users_preview |
| `migrateUserLocationToPrivate` | HTTP | Migra localização para subcoleção private |
| `backfillUserGeohash` | HTTP | Adiciona geohash aos usuários |
| `debugCreateNotification` | HTTP | Testa criação de notificação |
| `testPushNotification` | HTTP | Testa envio de push |

---

## 🎯 Proposta de APIs REST

### API 1: **Users API** (Autenticação & Perfil)

```
POST   /api/v1/auth/login
POST   /api/v1/auth/register
POST   /api/v1/auth/refresh
DELETE /api/v1/auth/logout

GET    /api/v1/users/me
PUT    /api/v1/users/me
DELETE /api/v1/users/me
GET    /api/v1/users/{userId}
GET    /api/v1/users/search?q=...

POST   /api/v1/users/{userId}/follow
DELETE /api/v1/users/{userId}/follow
GET    /api/v1/users/{userId}/followers
GET    /api/v1/users/{userId}/following

POST   /api/v1/users/{userId}/block
DELETE /api/v1/users/{userId}/block
GET    /api/v1/users/me/blocked
```

**Endpoints especiais:**
```
POST   /api/v1/users/me/device-tokens
DELETE /api/v1/users/me/device-tokens/{tokenId}
POST   /api/v1/users/me/profile-visit/{userId}
GET    /api/v1/users/me/profile-visits (VIP only)
GET    /api/v1/users/me/profile-visits/count
```

---

### API 2: **Events API** (Atividades)

```
POST   /api/v1/events
GET    /api/v1/events/{eventId}
PUT    /api/v1/events/{eventId}
DELETE /api/v1/events/{eventId}

GET    /api/v1/events?lat=...&lng=...&radius=...
GET    /api/v1/events/map?bounds=...
GET    /api/v1/events/feed

POST   /api/v1/events/{eventId}/apply
DELETE /api/v1/events/{eventId}/apply
PUT    /api/v1/events/{eventId}/applications/{appId}/approve
PUT    /api/v1/events/{eventId}/applications/{appId}/reject
GET    /api/v1/events/{eventId}/participants
DELETE /api/v1/events/{eventId}/participants/{userId}

PUT    /api/v1/events/{eventId}/presence
POST   /api/v1/events/{eventId}/report
```

---

### API 3: **Chat API** (Mensagens)

```
GET    /api/v1/conversations
GET    /api/v1/conversations/{conversationId}
DELETE /api/v1/conversations/{conversationId}

GET    /api/v1/conversations/{conversationId}/messages
POST   /api/v1/conversations/{conversationId}/messages
DELETE /api/v1/conversations/{conversationId}/messages/{messageId}
PUT    /api/v1/conversations/{conversationId}/read

GET    /api/v1/events/{eventId}/chat
GET    /api/v1/events/{eventId}/chat/messages
POST   /api/v1/events/{eventId}/chat/messages
```

**WebSocket para real-time:**
```
WS     /api/v1/ws/chat
```

---

### API 4: **Notifications API**

```
GET    /api/v1/notifications
GET    /api/v1/notifications/unread-count
PUT    /api/v1/notifications/{notificationId}/read
PUT    /api/v1/notifications/read-all
DELETE /api/v1/notifications/{notificationId}
```

---

### API 5: **Reviews API**

```
GET    /api/v1/reviews/pending
POST   /api/v1/reviews
GET    /api/v1/users/{userId}/reviews
PUT    /api/v1/reviews/pending/{id}/confirm-presence
PUT    /api/v1/reviews/pending/{id}/dismiss
```

---

### API 6: **Discovery API** (Geo-queries)

```
GET    /api/v1/discover/people?bounds=...&filters=...
GET    /api/v1/discover/events?bounds=...
GET    /api/v1/ranking/users?city=...&state=...
GET    /api/v1/ranking/locations?city=...
GET    /api/v1/ranking/filters
```

---

### API 7: **Subscription API**

```
GET    /api/v1/subscription/status
POST   /api/v1/subscription/verify-purchase

# Webhooks (interno)
POST   /api/v1/webhooks/revenuecat
POST   /api/v1/webhooks/didit
```

---

### API 8: **Feed API** (Social Feed)

```
GET    /api/v1/feed
GET    /api/v1/feed/photos
POST   /api/v1/feed/photos
GET    /api/v1/feed/photos/{photoId}
DELETE /api/v1/feed/photos/{photoId}

POST   /api/v1/feed/photos/{photoId}/like
DELETE /api/v1/feed/photos/{photoId}/like

GET    /api/v1/feed/photos/{photoId}/comments
POST   /api/v1/feed/photos/{photoId}/comments
DELETE /api/v1/feed/photos/{photoId}/comments/{commentId}

POST   /api/v1/feed/photos/{photoId}/comments/{commentId}/replies
```

---

### API 9: **Verification API**

```
POST   /api/v1/verification/start-session
GET    /api/v1/verification/status
```

---

### API 10: **Reports & Admin API**

```
POST   /api/v1/reports/bug
POST   /api/v1/reports/event/{eventId}

# Admin (futuro)
GET    /api/admin/reports
PUT    /api/admin/reports/{reportId}/resolve
```

---

## ⏰ Cron Jobs Necessários (8 jobs)

| Job | Frequência | Descrição |
|-----|------------|-----------|
| `events:deactivate-expired` | Diário 00:00 | Desativa eventos cujo schedule.date passou |
| `cleanup:old-notifications` | Diário 03:10 | Remove notificações > 10 dias |
| `cleanup:old-profile-visits` | Diário 00:30 | Remove visitas > 7 dias |
| `reviews:create-pending` | A cada hora | Cria pending reviews após eventos |
| `notifications:aggregate-views` | A cada 15 min | Agrega visualizações de perfil |
| `ranking:sync-filters` | A cada 30 min | Atualiza filtros de ranking |
| `sync:avatars-backfill` | A cada 6 horas | Corrige avatars faltantes |
| `sync:timestamps-backfill` | A cada 2 horas | Backfill de timestamps |

---

## 🏗️ Recomendação de Infraestrutura

### Opção A: **VPS + PostgreSQL** (Recomendado para controle de custos)

```
┌─────────────────────────────────────────────────────┐
│                   Load Balancer                      │
│                   (Nginx/HAProxy)                    │
└─────────────────┬───────────────────┬───────────────┘
                  │                   │
       ┌──────────▼──────────┐ ┌──────▼──────────┐
       │   API Server 1      │ │  API Server 2   │
       │   (Node.js/NestJS)  │ │  (Node.js/NestJS)│
       └──────────┬──────────┘ └──────┬──────────┘
                  │                   │
       ┌──────────▼───────────────────▼──────────┐
       │            PostgreSQL + PostGIS          │
       │         (geo-queries otimizadas)         │
       └──────────────────────────────────────────┘
                           │
       ┌──────────────────┬┴┬──────────────────┐
       │                  │ │                  │
       ▼                  ▼ ▼                  ▼
   ┌────────┐      ┌────────────┐      ┌────────────┐
   │ Redis  │      │ Firebase   │      │ S3/Minio   │
   │ Cache  │      │ Auth/FCM   │      │ Storage    │
   └────────┘      └────────────┘      └────────────┘
```

**Prós:**
- ✅ Custo previsível e controlável
- ✅ PostgreSQL com PostGIS para geo-queries nativas
- ✅ Full control sobre a infraestrutura
- ✅ Pode usar Hetzner/DigitalOcean (~$50-100/mês)

**Contras:**
- ❌ Requer DevOps/manutenção
- ❌ Escalabilidade manual
- ❌ Precisa configurar backups, monitoramento

**Custo estimado:** $100-300/mês (depende do tráfego)

---

### Opção B: **AWS Serverless** (Escalabilidade automática)

```
┌─────────────────────────────────────────────────────┐
│                   API Gateway                        │
└─────────────────┬───────────────────┬───────────────┘
                  │                   │
       ┌──────────▼──────────┐ ┌──────▼──────────┐
       │   Lambda Functions   │ │ Lambda Functions │
       │   (REST endpoints)   │ │   (WebSocket)    │
       └──────────┬──────────┘ └──────┬──────────┘
                  │                   │
       ┌──────────▼───────────────────▼──────────┐
       │          Aurora PostgreSQL               │
       │          (Serverless v2)                 │
       └──────────────────────────────────────────┘
                           │
       ┌──────────────────┬┴┬──────────────────┐
       │                  │ │                  │
       ▼                  ▼ ▼                  ▼
   ┌────────────┐  ┌────────────┐      ┌────────┐
   │ ElastiCache│  │ EventBridge│      │   S3   │
   │   (Redis)  │  │  (Crons)   │      │Storage │
   └────────────┘  └────────────┘      └────────┘
```

**Prós:**
- ✅ Zero manutenção de infraestrutura
- ✅ Escala automaticamente
- ✅ Pay-per-use

**Contras:**
- ❌ Custo pode explodir com crescimento
- ❌ Cold starts em Lambda
- ❌ Vendor lock-in

**Custo estimado:** $200-500/mês (base) + uso

---

### Opção C: **Híbrida** (Recomendada para migração gradual)

```
┌─────────────────────────────────────────────────────┐
│                      Flutter App                     │
└─────────────────────────┬───────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
          ▼               ▼               ▼
   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
   │ API REST    │ │  Firestore  │ │  Firebase   │
   │ (Novo)      │ │  (Legado)   │ │  Auth/FCM   │
   │             │ │             │ │             │
   │ VPS/K8s     │ │ (gradual    │ │  (manter)   │
   │ + PostgreSQL│ │  migração)  │ │             │
   └─────────────┘ └─────────────┘ └─────────────┘
```

**Estratégia de migração:**

1. **Fase 1:** Manter Firebase Auth e FCM (já funciona bem)
2. **Fase 2:** Migrar escrita direta para API (eventos, aplicações)
3. **Fase 3:** Migrar geo-queries para PostgreSQL + PostGIS
4. **Fase 4:** Migrar chat para WebSocket dedicado
5. **Fase 5:** Migrar dados históricos e desligar Firestore

---

## 🗄️ Recomendação de Banco de Dados

### PostgreSQL + PostGIS (Recomendado)

**Motivos:**
1. **Geo-queries nativas** - PostGIS é superior ao Firestore para consultas geoespaciais
2. **Transações ACID** - Importante para consistência em operações de eventos/chat
3. **Índices compostos** - Mais flexíveis que Firestore
4. **Custo previsível** - Sem surpresas de billing
5. **Joins nativos** - Elimina N+1 queries

**Schema simplificado:**
```sql
-- Usuários com PostGIS
CREATE TABLE users (
  id UUID PRIMARY KEY,
  full_name VARCHAR(255),
  email VARCHAR(255) UNIQUE,
  location GEOGRAPHY(POINT, 4326),
  geohash VARCHAR(12),
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
);

CREATE INDEX idx_users_location ON users USING GIST (location);
CREATE INDEX idx_users_geohash ON users (geohash);

-- Eventos com geo-index
CREATE TABLE events (
  id UUID PRIMARY KEY,
  creator_id UUID REFERENCES users(id),
  activity_text VARCHAR(500),
  location GEOGRAPHY(POINT, 4326),
  schedule_date TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ
);

CREATE INDEX idx_events_location ON events USING GIST (location);
CREATE INDEX idx_events_active_date ON events (is_active, schedule_date);
```

### MongoDB (Alternativa)

**Prós:**
- Schema flexível (similar ao Firestore)
- Geo-queries com índices 2dsphere
- Fácil migração de dados do Firestore

**Contras:**
- Menos eficiente para joins complexos
- Custo de Atlas pode ser alto

---

## 📊 Resumo de Endpoints por API

| API | Endpoints | Prioridade |
|-----|-----------|------------|
| Users API | 18 | 🔴 Alta |
| Events API | 14 | 🔴 Alta |
| Chat API | 10 + WS | 🔴 Alta |
| Notifications API | 5 | 🟡 Média |
| Reviews API | 5 | 🟡 Média |
| Discovery API | 5 | 🔴 Alta |
| Subscription API | 3 | 🟡 Média |
| Feed API | 10 | 🟢 Baixa |
| Verification API | 2 | 🟡 Média |
| Reports API | 3 | 🟢 Baixa |

**Total: ~75 endpoints REST + 1 WebSocket**

---

## 🚀 Roadmap de Migração Sugerido

### Fase 1: Fundação (2-3 semanas)
- [ ] Setup do projeto API (NestJS ou Express)
- [ ] Configurar PostgreSQL + PostGIS
- [ ] Implementar autenticação (integrar com Firebase Auth ou migrar)
- [ ] Setup de CI/CD

### Fase 2: Users API (2 semanas)
- [ ] CRUD de usuários
- [ ] Sistema de follow
- [ ] Sistema de block
- [ ] Device tokens

### Fase 3: Events API (3 semanas)
- [ ] CRUD de eventos
- [ ] Sistema de aplicações
- [ ] Geo-queries para mapa
- [ ] Migrar triggers para event handlers

### Fase 4: Chat API (3 semanas)
- [ ] WebSocket server
- [ ] Mensagens 1-1
- [ ] Chat de grupo (evento)
- [ ] Push notifications

### Fase 5: Features Secundárias (4 semanas)
- [ ] Reviews
- [ ] Notifications
- [ ] Feed
- [ ] Subscription
- [ ] Discovery avançado

### Fase 6: Migração de Dados (2 semanas)
- [ ] Scripts de migração Firestore → PostgreSQL
- [ ] Validação de dados
- [ ] Cutover gradual

**Tempo total estimado: 4-5 meses**

---

## 💰 Comparativo de Custos

| Cenário | Firebase Atual | VPS + PostgreSQL | AWS Serverless |
|---------|----------------|------------------|----------------|
| 10K usuários | ~$100-200/mês | ~$50-100/mês | ~$150-250/mês |
| 50K usuários | ~$500-800/mês | ~$150-300/mês | ~$400-700/mês |
| 100K usuários | ~$1500-3000/mês | ~$300-600/mês | ~$800-1500/mês |

**Nota:** Firebase tem billing imprevisível com reads/writes. VPS tem custo fixo.

---

## ✅ Conclusão e Recomendação

### Recomendação: **VPS + PostgreSQL + Redis**

**Justificativa:**
1. **Custo controlado** - Importante para startup/scale-up
2. **Performance superior** para geo-queries (PostGIS)
3. **Flexibilidade** - Fácil de ajustar conforme crescimento
4. **Manter Firebase Auth + FCM** - Já funciona bem, não precisa reinventar

### Tecnologias Recomendadas:
- **API Framework:** NestJS (TypeScript)
- **Banco:** PostgreSQL 16 + PostGIS 3.4
- **Cache:** Redis
- **WebSocket:** Socket.IO ou ws
- **Hosting:** Hetzner Cloud ou DigitalOcean
- **CDN:** Cloudflare

### Manter do Firebase:
- Firebase Authentication
- Firebase Cloud Messaging (FCM)
- Cloud Storage (ou migrar para S3)

---

## 📝 Anexos

### A. Tabela de Migração de Triggers

| Trigger Firestore | Equivalente API |
|-------------------|-----------------|
| `onEventCreated` | Lógica no `POST /events` |
| `onApplicationApproved` | Lógica no `PUT /events/{id}/applications/{id}/approve` |
| `onPrivateMessageCreated` | Event handler no WebSocket |
| `syncEventToMap` | View materializada ou trigger PostgreSQL |

### B. Estrutura de Projeto Sugerida

```
/api
├── src/
│   ├── modules/
│   │   ├── auth/
│   │   ├── users/
│   │   ├── events/
│   │   ├── chat/
│   │   ├── notifications/
│   │   ├── reviews/
│   │   └── ...
│   ├── shared/
│   │   ├── database/
│   │   ├── cache/
│   │   ├── queue/
│   │   └── utils/
│   ├── jobs/           # Cron jobs
│   └── webhooks/       # Webhooks externos
├── prisma/             # ORM
├── migrations/
└── docker-compose.yml
```

---

**Documento gerado automaticamente via auditoria de código.**
