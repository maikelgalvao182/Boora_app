# Plano de Migração para API Própria — Partiu

> **Data:** 15/02/2026 (revisado)  
> **Estratégia:** Migração Agressiva — Firebase (Auth + Chat APENAS) + API REST + PostgreSQL  
> **Status:** Planejamento  
> **Revisão:** v2 — Escopo expandido. Somente Auth e Chat permanecem no Firebase.

---

## Sumário Executivo

A aplicação Partiu hoje é **100% Firebase-dependente**: 63 Cloud Functions, 30+ coleções Firestore acessadas diretamente pelo client, 50 real-time streams, 9 cron jobs e 1 serviço Cloud Run (WebSocket/NestJS).

**Decisão estratégica:** manter no Firebase **apenas Auth e Chat**. Todo o resto migra para **API NestJS + PostgreSQL (PostGIS)**. Isso elimina ~85-90% do custo Firestore e remove toda a complexidade de denormalização.

### Comparação v1 → v2

| Aspecto | v1 (Híbrido) | v2 (Agressivo) |
|---------|-------------|----------------|
| Streams Firestore | 50 (todos ficam) | **~7** (só chat) |
| Cloud Functions mantidas | 17 triggers | **~3** (só chat) |
| Coleções Firestore ativas | 30+ | **~5** (auth + chat) |
| Denormalização (preview, tombstones) | Necessária | **Eliminada** (PostgreSQL faz JOINs) |
| Redução de custo Firestore | ~40-50% | **~85-90%** |
| Complexidade de migração | Média | Alta |
| Real-time (não-chat) | Firestore streams | **WebSocket + polling** |

---

## Parte 1 — Auditoria Completa (sem alterações da v1)

### 1.1 Cloud Functions (63 total)

| Categoria | Qtd | Tipo |
|-----------|-----|------|
| Event Lifecycle | 8 | Triggers + Callables |
| Event Sync/Denormalization | 4 | Triggers |
| Tombstones | 2 | Cron + HTTP |
| User Management | 5 | Triggers + Callables + HTTP |
| Follow System | 2 | Callables |
| Feed Fanout | 4 | Triggers |
| Notifications In-App | 5 | Triggers |
| Notifications Push | 3 | Triggers |
| Profile Views | 4 | Cron + Callable + HTTP |
| Ranking | 3 | Triggers + Cron |
| Reviews | 5 | Triggers + Cron |
| Devices/Blacklist | 3 | Callables + Trigger |
| Moderation/Referrals | 2 | Triggers |
| Webhooks | 2 | HTTP |
| Discovery (getPeople) | 1 | Callable |
| Chat Message | 1 | Callable |
| Notifications Cleanup | 2 | Cron |
| Patches/Migrations | 6 | HTTP + Callable |
| Debug | 1 | HTTP |

### 1.2 Cron Jobs (9 total)

| Job | Schedule | O que faz |
|-----|----------|-----------|
| `deactivateExpiredEvents` | Diário 00:00 BRT | Desativa eventos expirados |
| `processEventDeletions` | A cada 5 min | Processa deleção faseada de eventos |
| `cleanupOldTombstones` | Diário 04:00 BRT | Limpa tombstones > 14 dias |
| `cleanupOldNotifications` | Diário 03:10 BRT | Deleta notificações > 10 dias |
| `processProfileViewNotifications` | A cada 15 min | Agrega visualizações de perfil |
| `syncRankingFilters` | A cada 30 min | Sincroniza filtros de ranking |
| `createPendingReviewsScheduled` | A cada 1 hora | Cria pending reviews |
| `backfillMissingNotificationTimestamps` | A cada 2 horas | Corrige timestamps |
| `cleanupOldProfileVisits` | Diário 00:00 BRT | Limpa visitas > 7 dias |

---

## Parte 2 — Classificação v2: O que Fica vs. O que Sai do Firebase

### 2.1 🔴 PERMANECE NO FIREBASE (mínimo absoluto)

#### Firebase Auth — Intocável
- Login Phone + Apple Sign-In
- Token management (JWT)
- JWT validado na API via Firebase Admin SDK `verifyIdToken()`
- Sem mudança alguma para o usuário

#### Firestore — SOMENTE Chat
| Coleção | Uso | Streams | Motivo |
|---------|-----|---------|--------|
| `Connections/{uid}/Conversations` | Lista de conversas | 4 streams | Real-time obrigatório (lista, unread badge) |
| `EventChats/{eventId}/Messages` | Chat de grupo | 2 streams | Mensagens em tempo real |
| `Messages/{ownerId}/{partnerId}` | Chat direto (DM) | 1 stream | Mensagens em tempo real |

**Total: 3 coleções, ~7 streams**

#### Cloud Functions — SOMENTE Chat triggers (3)
| Função | Motivo |
|--------|--------|
| `onEventChatMessageCreated` | Atualiza Conversations + unread_count + push notification |
| `onPrivateMessageCreated` | Push notification de DM |
| `deleteChatMessage` | Soft-delete com validação de ownership |

#### Cloud Storage — Mantém (não é Firestore)
- Upload/download de fotos (barato, paga por GB armazenado)
- Security Rules baseadas em Firebase Auth
- **Custo irrelevante** comparado ao Firestore

#### FCM — Token registration (via Firebase SDK no client)
- `messaging.getToken()` continua no client
- Push dispatch muda para API (FCM HTTP v1)

---

### 2.2 🟢 SAI DO FIREBASE → PostgreSQL + API

#### Coleções Firestore que MORREM (migram para PostgreSQL)

| Coleção Firestore | Tabela PostgreSQL | Streams que morrem | Substituição |
|---|---|---|---|
| `Users` | `users` | 9 streams | API GET + WebSocket events |
| `users_preview` | **Eliminada** | — | `SELECT id, name, avatar FROM users` (view/projection) |
| `events` | `events` (PostGIS) | 4 streams | API GET + WebSocket events |
| `events_card_preview` | **Eliminada** | — | `SELECT` com join (denorm desnecessária) |
| `event_tombstones` | **Eliminada** | — | `WHERE deleted_at IS NOT NULL` (soft delete nativo) |
| `EventApplications` | `event_applications` | 4 streams | API GET + WebSocket events |
| `EventPhotos` + sublikes/comments | `event_photos`, `photo_likes`, `photo_comments` | 2 streams | API GET + WebSocket |
| `Notifications` | `notifications` | 3 streams | API GET + WebSocket push |
| `PendingReviews` | `pending_reviews` | 3 streams | API GET + polling |
| `Reviews` | `reviews` | 3 streams | API GET |
| `blockedUsers` | `blocked_users` | 3 streams | API GET + cache local |
| `ProfileVisits` | `profile_visits` | 2 streams | API GET |
| `ProfileViews` | Unificado em `profile_visits` | — | — |
| `FaceVerifications` | `face_verifications` | — | API |
| `DiditSessions` | `didit_sessions` | 1 stream | API + polling |
| `AppInfo` | `app_config` | — | API GET + cache |
| `DeviceTokens` | `device_tokens` | — | API |
| `Users/{id}/followers` | `follows` | 1 stream | API GET |
| `Users/{id}/following` | Mesma tabela `follows` | — | — |
| `Users/{id}/private/location` | `users.location` (PostGIS, access via API) | — | Segurança na API |
| `Users/{id}/clients` | `user_devices` | — | API |
| `feeds/{uid}/items` | `feed_items` | — | API GET paginado |
| `ActivityFeed` | `activity_feed` | — | API GET |
| `reports` | `reports` | — | API |
| `ReferralInstalls` | `referral_installs` | — | API |
| `BlacklistDevices` | `blacklisted_devices` | — | API |
| `WeddingAnnouncements` | `announcements` | — | API |
| `userRanking` | **View SQL** sobre `users` + `events` | — | `SELECT` com aggregation |
| `locationRanking` | **View SQL** sobre `events` + `places` | — | `SELECT` com aggregation |
| `ranking_filters` | **Eliminada** | — | `SELECT DISTINCT state, city FROM users` |
| `Subscriptions` | `subscriptions` | — | API |
| `SubscriptionEvents` | `subscription_events` | — | API |

**Total eliminado: ~28 coleções Firestore, ~43 streams**

#### Cloud Functions que MORREM (absorvidas pela API)

| Função | Para onde vai | Motivo |
|--------|-------------|--------|
| `onEventCreated` | Lógica dentro de `POST /api/v1/events` | API cria evento + application + chat |
| `onApplicationApproved` | Dentro de `PATCH /api/v1/events/:id/applications/:appId` | Lógica de aprovação na API |
| `deleteEvent` | `DELETE /api/v1/events/:id` | CRUD na API |
| `removeUserApplication` | `DELETE /api/v1/events/:id/applications/:appId` | CRUD na API |
| `removeParticipant` | `DELETE /api/v1/events/:id/participants/:userId` | CRUD na API |
| `onEventWriteUpdateCardPreview` | **Eliminada** | PostgreSQL não precisa de denorm |
| `onUserProfileUpdateSyncEvents` | **Eliminada** | JOINs resolvem |
| `onUserAvatarUpdated` | **Eliminada** | JOINs resolvem |
| `onUserLocationUpdated` | **Eliminada** | UPDATE direto no PostgreSQL |
| `onUserWriteUpdatePreview` | **Eliminada** | views_preview não existe mais |
| `onUserLocationUpdateCopyToPrivate` | **Eliminada** | Coluna PostGIS na tabela users |
| `onEventPhotoWriteFanout` | Lógica dentro de `POST /api/v1/photos` | API faz fan-out ou pull model |
| `onActivityFeedWriteFanout` | **Eliminada** | Pull model com `SELECT` |
| `onNewFollowerBackfillFeed` | Dentro de `POST /api/v1/users/:id/follow` | JOIN na query do feed |
| `onUnfollowCleanupFeed` | Dentro de `DELETE /api/v1/users/:id/follow` | CASCADE ou cleanup |
| `getPeople` | `GET /api/v1/discover/people` | PostGIS `ST_DWithin()` |
| `followUser` | `POST /api/v1/users/:id/follow` | INSERT + increment |
| `unfollowUser` | `DELETE /api/v1/users/:id/follow` | DELETE + decrement |
| `deleteUserAccount` | `DELETE /api/v1/account` | CASCADE deletes |
| `checkDeviceBlacklist` | `POST /api/v1/devices/check` | SELECT |
| `registerDevice` | `POST /api/v1/devices/register` | UPSERT |
| `onActivityCreatedNotification` | Dentro de `POST /api/v1/events` | PostGIS radius query |
| `onActivityHeatingUp` | Dentro do endpoint de apply | COUNT + threshold check |
| `onJoinRequestNotification` | Dentro de `POST /api/v1/events/:id/apply` | INSERT notification |
| `onJoinDecisionNotification` | Dentro do endpoint de approve/reject | INSERT notification |
| `onActivityCanceledNotification` | Dentro do endpoint de cancel | INSERT notifications |
| `onActivityNotificationCreated` | Push service interno da API | FCM HTTP v1 |
| `updateUserRanking` | **View SQL** | `SELECT COUNT(*) FROM events WHERE creator_id = ?` |
| `updateLocationRanking` | **View SQL** | Aggregation query |
| `syncRankingFilters` | **Eliminada** | `SELECT DISTINCT` na query |
| `onPresenceConfirmed` | `POST /api/v1/reviews/:id/confirm` | INSERT |
| `onReviewCreated` | `POST /api/v1/reviews` | INSERT + push |
| `updateUserRatingOnReviewCreate` | Trigger PostgreSQL ou lógica no endpoint | `AVG(rating)` |
| `updateUserRatingOnReviewDelete` | Trigger PostgreSQL | `AVG(rating)` |
| `onUserStatusChange` | Lógica dentro do endpoint de moderação | UPDATE + blacklist |
| `onReportCreated` | `POST /api/v1/reports` | INSERT + moderação |
| `onUserCreatedReferral` | `POST /api/v1/referrals` | INSERT + threshold check |
| `processProfileViewNotifications` | Cron na API | SELECT aggregation |
| Todos os 9 cron jobs | Cloud Scheduler → API endpoints | — |
| Todas as 6 migrations/patches | CLI commands do NestJS | — |
| `diditWebhook` | `POST /api/v1/webhooks/didit` | — |
| `revenueCatWebhook` | `POST /api/v1/webhooks/revenuecat` | — |
| `cleanupOnEventDelete` | **Eliminada** | CASCADE DELETE |
| `backfillEventTombstones` | **Eliminada** | Soft delete nativo |
| `resyncUsersPreview` | **Eliminada** | Não existe mais preview |
| `migrateUserLocationToPrivate` | **Eliminada** | Coluna na tabela users |
| `debugCreateNotification` | **Eliminada** | Seed/test no NestJS |

**Total eliminado: ~60 Cloud Functions → sobram ~3 (chat triggers)**

---

### 2.3 Substituição dos 50 Real-Time Streams

O ponto mais crítico: **43 streams saem do Firestore**. Como substituir?

| Categoria | Streams atuais | Substituição | UX impactada? |
|-----------|---------------|-------------|---------------|
| **Chat (DM + Grupo)** | 7 | **Firestore (mantém)** | ❌ Nenhuma |
| **Perfil do usuário atual** | 9 | **WebSocket** `user:updated` event | ❌ Imperceptível |
| **Status do evento** | 4 | **WebSocket** `event:updated` event | ❌ Imperceptível |
| **Aplicações de evento** | 4 | **WebSocket** `application:updated` event | ❌ Mínima |
| **Notificações** | 3 | **WebSocket** `notification:new` event + badge | ❌ Imperceptível |
| **Reviews/PendingReviews** | 6 | **API polling** (a cada 30s na tela) | ⚠️ Delay de até 30s |
| **Block list** | 3 | **Cache local** (carrega no login, WebSocket invalida) | ❌ Nenhuma |
| **Profile visits** | 2 | **API polling** (ao abrir tela) | ⚠️ Não é real-time |
| **Followers count** | 1 | **API response** (vem no perfil) | ❌ Nenhuma |
| **Photo likes** | 2 | **WebSocket** `photo:liked` event | ❌ Mínima |
| **DiditSessions** | 1 | **API polling** (durante verificação) | ⚠️ Polling 3s |
| **Reports/outros** | 1 | **API** (web dashboard) | ❌ Nenhuma |

### Estratégia WebSocket expandida

O serviço WebSocket atual (`wedding-websocket`) já usa NestJS + Socket.IO. Será **absorvido na API principal** e expandido:

```
Canais WebSocket (Socket.IO rooms):

user:{userId}         → perfil, VIP status, verificação
event:{eventId}       → status, participantes, aplicações
notifications:{userId} → novas notificações, badge count
feed:{userId}         → novos items no feed
photo:{photoId}       → likes, comments
chat:{conversationId} → já existe (mantém no Firestore por enquanto)
```

**Fluxo:** API faz write no PostgreSQL → emite evento WebSocket → client atualiza UI.

---

## Parte 3 — Arquitetura Final v2

```
┌─────────────────────────────────────────────────────────────┐
│                       FLUTTER APP                            │
├──────────────┬────────────────┬──────────────────────────────┤
│  Firebase SDK │   Dio (REST)   │  Socket.IO Client            │
│  (Auth only) │   (API calls)  │  (Real-time events)          │
└──────┬───────┴──────┬─────────┴──────────┬───────────────────┘
       │              │                    │
       ▼              ▼                    ▼
┌──────────────┐ ┌──────────────────────────────────────────────┐
│ FIREBASE     │ │         API NestJS (Cloud Run)                │
│              │ │                                              │
│ • Auth       │ │  ┌─────────────┐  ┌───────────────────────┐ │
│   (JWT)      │ │  │ REST API    │  │ WebSocket Gateway     │ │
│              │ │  │             │  │ (Socket.IO)           │ │
│ • Firestore  │ │  │ /events     │  │                       │ │
│   SOMENTE:   │ │  │ /users      │  │ • user:updated        │ │
│   - Messages │ │  │ /discover   │  │ • event:updated       │ │
│   - EventChat│ │  │ /feed       │  │ • notification:new    │ │
│   - Convers. │ │  │ /reviews    │  │ • application:updated │ │
│              │ │  │ /webhooks   │  │ • photo:liked         │ │
│ • Storage    │ │  │ /jobs       │  │                       │ │
│   (fotos)    │ │  └──────┬──────┘  └───────────┬───────────┘ │
│              │ │         │                     │             │
│ • FCM token  │ │         ▼                     │             │
│              │ │  ┌──────────────┐              │             │
│              │ │  │ PostgreSQL   │◄─────────────┘             │
│              │ │  │ (Cloud SQL)  │                            │
│              │ │  │              │  ┌─────────────────┐       │
│              │ │  │ + PostGIS    │  │ Redis (opcional) │       │
│              │ │  │ + pgcron     │  │ Cache + sessions │       │
│              │ │  └──────────────┘  └─────────────────┘       │
│              │ │                                              │
│  3 triggers: │ │  Push: FCM HTTP v1 API                       │
│  onChatMsg   │ │  Cron: Cloud Scheduler → /api/v1/jobs/*     │
│  onDMMsg     │ │  Webhooks: Didit, RevenueCat                │
│  deleteMsg   │ └──────────────────────────────────────────────┘
└──────────────┘
```

### Fluxo de dados v2:
1. **Auth**: Firebase Auth → JWT → API valida via `admin.auth().verifyIdToken()`
2. **Chat real-time**: Client ↔ Firestore streams (Messages, EventChats, Conversations)
3. **Todas as queries**: Client → API REST → PostgreSQL → Response
4. **Real-time (não-chat)**: API escreve no PostgreSQL → emite WebSocket event → Client atualiza
5. **Push**: API → FCM HTTP v1 → Device
6. **Webhooks**: External → API → PostgreSQL
7. **Cron**: Cloud Scheduler → API endpoints autenticados
8. **Fotos**: Client → Cloud Storage (upload) + API → PostgreSQL (metadata)

---

## Parte 4 — Schema PostgreSQL

### 4.1 Tabelas Principais

```sql
-- Extensões necessárias
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- busca por texto
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- USERS
-- ============================================
CREATE TABLE users (
  id            UUID PRIMARY KEY,            -- mesmo UID do Firebase Auth
  name          VARCHAR(100) NOT NULL,
  email         VARCHAR(255),
  phone         VARCHAR(20),
  avatar_url    TEXT,
  bio           TEXT,
  gender        VARCHAR(20),
  birth_date    DATE,
  sexual_orientation VARCHAR(30),
  interests     TEXT[],                       -- array nativo PostgreSQL
  location      GEOGRAPHY(Point, 4326),      -- PostGIS
  city          VARCHAR(100),
  state         VARCHAR(50),
  country       VARCHAR(50) DEFAULT 'Brasil',
  flag          VARCHAR(10) DEFAULT '🇧🇷',
  is_verified   BOOLEAN DEFAULT FALSE,
  is_vip        BOOLEAN DEFAULT FALSE,
  vip_expires_at TIMESTAMPTZ,
  overall_rating DECIMAL(3,2) DEFAULT 0,
  status        VARCHAR(20) DEFAULT 'active', -- active, inactive, banned
  referrer_id   UUID REFERENCES users(id),
  follower_count  INTEGER DEFAULT 0,
  following_count INTEGER DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),
  deleted_at    TIMESTAMPTZ                   -- soft delete nativo
);

CREATE INDEX idx_users_location ON users USING GIST(location);
CREATE INDEX idx_users_interests ON users USING GIN(interests);
CREATE INDEX idx_users_status ON users(status) WHERE status = 'active';
CREATE INDEX idx_users_city_state ON users(state, city);
CREATE INDEX idx_users_gender ON users(gender) WHERE status = 'active';

-- ============================================
-- EVENTS (com PostGIS)
-- ============================================
CREATE TABLE events (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  creator_id    UUID NOT NULL REFERENCES users(id),
  title         VARCHAR(200) NOT NULL,
  description   TEXT,
  category      VARCHAR(50),
  location      GEOGRAPHY(Point, 4326),      -- PostGIS
  address       TEXT,
  city          VARCHAR(100),
  state         VARCHAR(50),
  place_id      VARCHAR(100),                -- Google Places ID
  place_name    VARCHAR(200),
  schedule_date TIMESTAMPTZ NOT NULL,
  max_participants INTEGER,
  is_active     BOOLEAN DEFAULT TRUE,
  status        VARCHAR(20) DEFAULT 'active', -- active, inactive, canceled
  photo_url     TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),
  deleted_at    TIMESTAMPTZ                   -- substitui tombstones
);

CREATE INDEX idx_events_location ON events USING GIST(location);
CREATE INDEX idx_events_active ON events(is_active, schedule_date) WHERE is_active = TRUE;
CREATE INDEX idx_events_creator ON events(creator_id);
CREATE INDEX idx_events_category ON events(category) WHERE is_active = TRUE;
CREATE INDEX idx_events_schedule ON events(schedule_date) WHERE is_active = TRUE;

-- ============================================
-- EVENT APPLICATIONS
-- ============================================
CREATE TABLE event_applications (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id      UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES users(id),
  status        VARCHAR(20) DEFAULT 'pending', -- pending, approved, rejected, autoApproved
  applied_at    TIMESTAMPTZ DEFAULT NOW(),
  decided_at    TIMESTAMPTZ,
  UNIQUE(event_id, user_id)
);

CREATE INDEX idx_applications_event ON event_applications(event_id, status);
CREATE INDEX idx_applications_user ON event_applications(user_id);

-- ============================================
-- FOLLOWS
-- ============================================
CREATE TABLE follows (
  follower_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  following_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (follower_id, following_id)
);

CREATE INDEX idx_follows_following ON follows(following_id);

-- ============================================
-- REVIEWS
-- ============================================
CREATE TABLE reviews (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reviewer_id   UUID NOT NULL REFERENCES users(id),
  reviewee_id   UUID NOT NULL REFERENCES users(id),
  event_id      UUID REFERENCES events(id),
  rating        SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment       TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_reviews_reviewee ON reviews(reviewee_id);

CREATE TABLE pending_reviews (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id      UUID NOT NULL REFERENCES events(id),
  reviewer_id   UUID NOT NULL REFERENCES users(id),
  reviewee_id   UUID NOT NULL REFERENCES users(id),
  type          VARCHAR(20), -- owner_to_participant, participant_to_owner
  presence_confirmed BOOLEAN DEFAULT FALSE,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  expires_at    TIMESTAMPTZ
);

-- ============================================
-- NOTIFICATIONS
-- ============================================
CREATE TABLE notifications (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type          VARCHAR(50) NOT NULL,
  title         TEXT,
  body          TEXT,
  data          JSONB,                        -- payload flexível
  is_read       BOOLEAN DEFAULT FALSE,
  push_sent     BOOLEAN DEFAULT FALSE,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_notifications_user ON notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_unread ON notifications(user_id) WHERE is_read = FALSE;

-- ============================================
-- PHOTOS & FEED
-- ============================================
CREATE TABLE event_photos (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id      UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES users(id),
  photo_url     TEXT NOT NULL,
  caption       TEXT,
  like_count    INTEGER DEFAULT 0,
  comment_count INTEGER DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE photo_likes (
  photo_id      UUID NOT NULL REFERENCES event_photos(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (photo_id, user_id)
);

CREATE TABLE photo_comments (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  photo_id      UUID NOT NULL REFERENCES event_photos(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES users(id),
  parent_id     UUID REFERENCES photo_comments(id) ON DELETE CASCADE,
  content       TEXT NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- PROFILE & DEVICES
-- ============================================
CREATE TABLE profile_visits (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  visitor_id    UUID NOT NULL REFERENCES users(id),
  visited_id    UUID NOT NULL REFERENCES users(id),
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_visits_visited ON profile_visits(visited_id, created_at DESC);

CREATE TABLE blocked_users (
  blocker_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason        TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (blocker_id, blocked_id)
);

CREATE TABLE device_tokens (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fcm_token     TEXT NOT NULL,
  device_hash   VARCHAR(64),
  platform      VARCHAR(10), -- ios, android
  updated_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, device_hash)
);

CREATE TABLE blacklisted_devices (
  device_hash   VARCHAR(64) PRIMARY KEY,
  reason        TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- SUBSCRIPTIONS
-- ============================================
CREATE TABLE subscriptions (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id),
  plan          VARCHAR(50),
  status        VARCHAR(20), -- active, expired, canceled
  provider      VARCHAR(20) DEFAULT 'revenuecat',
  starts_at     TIMESTAMPTZ,
  expires_at    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE subscription_events (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  subscription_id UUID REFERENCES subscriptions(id),
  user_id       UUID REFERENCES users(id),
  event_type    VARCHAR(50), -- INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION
  data          JSONB,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- MISC
-- ============================================
CREATE TABLE reports (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reporter_id   UUID NOT NULL REFERENCES users(id),
  target_type   VARCHAR(20), -- user, event
  target_id     UUID NOT NULL,
  reason        TEXT,
  status        VARCHAR(20) DEFAULT 'pending',
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE referral_installs (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  referrer_id   UUID NOT NULL REFERENCES users(id),
  referred_id   UUID NOT NULL REFERENCES users(id),
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE face_verifications (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id),
  provider      VARCHAR(20) DEFAULT 'didit',
  session_id    VARCHAR(100),
  status        VARCHAR(20), -- pending, approved, rejected
  data          JSONB,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE app_config (
  key           VARCHAR(100) PRIMARY KEY,
  value         JSONB NOT NULL,
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- VIEWS (substituem coleções de denormalização)
-- ============================================

-- Substitui users_preview
CREATE VIEW users_preview AS
SELECT id, name, avatar_url, city, state, is_verified, is_vip, location
FROM users WHERE status = 'active' AND deleted_at IS NULL;

-- Substitui ranking (nenhuma coleção separada precisa existir)
CREATE VIEW user_ranking AS
SELECT
  u.id, u.name, u.avatar_url, u.city, u.state,
  COUNT(e.id) AS total_events_created,
  u.overall_rating,
  u.follower_count
FROM users u
LEFT JOIN events e ON e.creator_id = u.id AND e.deleted_at IS NULL
WHERE u.status = 'active'
GROUP BY u.id;

-- Substitui ranking_filters (elimina cron de 30 min)
CREATE VIEW ranking_filters AS
SELECT DISTINCT state, city FROM users
WHERE status = 'active' AND state IS NOT NULL;

-- ============================================
-- TRIGGERS PostgreSQL (substituem Cloud Functions)
-- ============================================

-- Auto-update overall_rating quando review é criada/deletada
CREATE OR REPLACE FUNCTION update_user_rating()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE users SET overall_rating = (
    SELECT COALESCE(AVG(rating), 0) FROM reviews WHERE reviewee_id = COALESCE(NEW.reviewee_id, OLD.reviewee_id)
  ), updated_at = NOW()
  WHERE id = COALESCE(NEW.reviewee_id, OLD.reviewee_id);
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_review_rating_insert AFTER INSERT ON reviews
  FOR EACH ROW EXECUTE FUNCTION update_user_rating();
CREATE TRIGGER trg_review_rating_delete AFTER DELETE ON reviews
  FOR EACH ROW EXECUTE FUNCTION update_user_rating();

-- Auto-update follower counts
CREATE OR REPLACE FUNCTION update_follow_counts()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE users SET follower_count = follower_count + 1 WHERE id = NEW.following_id;
    UPDATE users SET following_count = following_count + 1 WHERE id = NEW.follower_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE users SET follower_count = GREATEST(follower_count - 1, 0) WHERE id = OLD.following_id;
    UPDATE users SET following_count = GREATEST(following_count - 1, 0) WHERE id = OLD.follower_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_follow_counts AFTER INSERT OR DELETE ON follows
  FOR EACH ROW EXECUTE FUNCTION update_follow_counts();

-- Auto-update photo like count
CREATE OR REPLACE FUNCTION update_photo_like_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE event_photos SET like_count = like_count + 1 WHERE id = NEW.photo_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE event_photos SET like_count = GREATEST(like_count - 1, 0) WHERE id = OLD.photo_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_photo_like_count AFTER INSERT OR DELETE ON photo_likes
  FOR EACH ROW EXECUTE FUNCTION update_photo_like_count();

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_events_updated BEFORE UPDATE ON events
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### 4.2 Queries que substituem a complexidade do Firestore

```sql
-- SUBSTITUI getPeople (Cloud Function complexa com geohash + grid + cache)
-- Uma query PostGIS faz tudo:
SELECT u.id, u.name, u.avatar_url, u.city, u.birth_date, u.interests, u.is_verified
FROM users u
WHERE u.status = 'active'
  AND u.deleted_at IS NULL
  AND u.id != $1  -- exclui o próprio usuário
  AND u.id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = $1)
  AND ST_DWithin(u.location, ST_Point($2, $3)::geography, $4) -- $4 = raio em metros
  AND ($5::text IS NULL OR u.gender = $5)
  AND ($6::int IS NULL OR EXTRACT(YEAR FROM AGE(u.birth_date)) BETWEEN $6 AND $7)
  AND ($8::text[] IS NULL OR u.interests && $8)  -- interseção de arrays
ORDER BY ST_Distance(u.location, ST_Point($2, $3)::geography)
LIMIT $9;

-- SUBSTITUI events no mapa (geohash queries complexas)
SELECT e.*, u.name AS creator_name, u.avatar_url AS creator_avatar,
       COUNT(ea.id) FILTER (WHERE ea.status IN ('approved','autoApproved')) AS participant_count
FROM events e
JOIN users u ON u.id = e.creator_id
LEFT JOIN event_applications ea ON ea.event_id = e.id
WHERE e.is_active = TRUE
  AND e.deleted_at IS NULL
  AND e.location && ST_MakeEnvelope($1, $2, $3, $4, 4326) -- bounding box do mapa
  AND e.schedule_date > NOW()
GROUP BY e.id, u.id;

-- SUBSTITUI feed (elimina toda a lógica de fanout)
-- Pull model: uma query com JOIN resolve
SELECT ep.*, u.name, u.avatar_url
FROM event_photos ep
JOIN users u ON u.id = ep.user_id
WHERE ep.user_id IN (SELECT following_id FROM follows WHERE follower_id = $1)
ORDER BY ep.created_at DESC
LIMIT 20 OFFSET $2;

-- SUBSTITUI ranking (elimina collection + cron de 30 min)
SELECT * FROM user_ranking
WHERE ($1::text IS NULL OR state = $1)
  AND ($2::text IS NULL OR city = $2)
ORDER BY total_events_created DESC, overall_rating DESC
LIMIT 50;

-- SUBSTITUI deactivateExpiredEvents (cron job)
UPDATE events SET is_active = FALSE, status = 'inactive'
WHERE is_active = TRUE AND schedule_date < NOW();
-- Pronto. Uma query. Sem batch processing, sem cursor pagination.

-- SUBSTITUI cleanupOldNotifications (cron job)
DELETE FROM notifications WHERE created_at < NOW() - INTERVAL '10 days';

-- SUBSTITUI cleanupOldProfileVisits (cron job)
DELETE FROM profile_visits WHERE created_at < NOW() - INTERVAL '7 days';
```

---

## Parte 5 — Plano de Migração por Fases (v2 — Agressivo)

### Fase 0 — Infraestrutura Base (2-3 semanas)
> **Setup do projeto NestJS + PostgreSQL + deploy pipeline**

- [ ] Criar projeto NestJS na pasta `api/`
- [ ] Configurar Dockerfile + cloudbuild.yaml (já tem referência do wedding-websocket)
- [ ] Provisionar **Cloud SQL PostgreSQL** (us-central1, mesma região)
  - Instância: `db-f1-micro` para dev (~$7/mês)
  - Habilitar extensão PostGIS
  - Configurar Cloud SQL Proxy para dev local
- [ ] Configurar **Prisma** como ORM (schema-first, migrations, type-safe)
- [ ] Implementar **Auth Guard** (Firebase Admin SDK `verifyIdToken()`)
- [ ] Configurar FCM module para push dispatch (FCM HTTP v1)
- [ ] Criar **ApiClient** centralizado no Flutter (Dio + interceptors)
  - `AuthInterceptor` (adiciona Firebase JWT)
  - `ErrorInterceptor` (retry, error handling)
  - `CacheInterceptor` (opcional)
- [ ] Setup CI/CD (Cloud Build → Cloud Run)
- [ ] Implementar **Feature Flag** no Flutter para toggle gradual Firebase↔API
- [ ] **Absorver** wedding-websocket na API principal (WebSocket gateway unificado)
- [ ] Script de **data migration** Firestore → PostgreSQL (one-time)

### Fase 1 — Users + Auth Sync (3-4 semanas) 🔴
> **Migra a coleção mais acessada (60+ referências)**

- [ ] Rodar migration script: `Users` → tabela `users` (com PostGIS location)
- [ ] Criar endpoints:
  - `GET /api/v1/users/me` (perfil próprio)
  - `PUT /api/v1/users/me` (atualizar perfil)
  - `GET /api/v1/users/:id` (perfil público)
  - `PUT /api/v1/users/me/location` (atualizar localização)
  - `GET /api/v1/users/me/blocked` (lista de bloqueios)
  - `POST /api/v1/users/:id/block` (bloquear)
  - `DELETE /api/v1/users/:id/block` (desbloquear)
- [ ] Configurar WebSocket `user:{userId}` para emitir mudanças de perfil
- [ ] **Flutter:** Substituir 9 streams de `Users` por:
  - API call no `initState()` / `onResume()`
  - WebSocket event `user:updated` para sync em background
  - Cache local (Hive/SharedPreferences) para offline
- [ ] Migrar `blockedUsers` → tabela `blocked_users` (cache local no app start)
- [ ] Migrar `FaceVerifications` + `DiditSessions` → tabela PostgreSQL
- [ ] Migrar `AppInfo` → tabela `app_config`
- [ ] **Eliminar coleções Firestore:** `Users` (exceto `Users/{uid}` para Auth sync mínimo), `users_preview`, `blockedUsers`, `FaceVerifications`, `DiditSessions`, `AppInfo`
- [ ] **Eliminar Cloud Functions:** `onUserWriteUpdatePreview`, `onUserAvatarUpdated`, `onUserLocationUpdated`, `onUserLocationUpdateCopyToPrivate`, `onUserProfileUpdateSyncEvents`, `onUserStatusChange`

### Fase 2 — Events + Discovery + Map (3-4 semanas) 🔴
> **Maior impacto em custo — PostGIS substitui geohash**

- [ ] Rodar migration: `events` + `events_card_preview` → tabela `events`
- [ ] Rodar migration: `EventApplications` → tabela `event_applications`
- [ ] Criar endpoints:
  - `POST /api/v1/events` (criar evento — absorve `onEventCreated` + `updateUserRanking` + `onActivityCreatedNotification`)
  - `GET /api/v1/events/:id` (com dados do criador via JOIN)
  - `GET /api/v1/events/map?neLat=&neLng=&swLat=&swLng=` (PostGIS bounding box)
  - `DELETE /api/v1/events/:id` (absorve `deleteEvent`)
  - `PATCH /api/v1/events/:id` (atualizar + cancel)
  - `POST /api/v1/events/:id/apply` (aplicar — absorve `onJoinRequestNotification`)
  - `PATCH /api/v1/events/:id/applications/:appId` (aprovar/rejeitar — absorve `onApplicationApproved` + `onJoinDecisionNotification`)
  - `DELETE /api/v1/events/:id/applications/:appId` (remover aplicação)
  - `DELETE /api/v1/events/:id/participants/:userId` (remover participante)
  - `GET /api/v1/events/:id/participants` (listar com perfis via JOIN)
  - `GET /api/v1/discover/people` (PostGIS `ST_DWithin()` — absorve `getPeople`)
- [ ] Configurar WebSocket `event:{eventId}` para emitir mudanças
- [ ] **Flutter:** Substituir 4 streams de `events` + 4 de `EventApplications` por API + WebSocket
- [ ] **Eliminar coleções Firestore:** `events`, `events_card_preview`, `event_tombstones`, `EventApplications`
- [ ] **Eliminar Cloud Functions:** `onEventCreated`, `onApplicationApproved`, `deleteEvent`, `removeUserApplication`, `removeParticipant`, `onEventWriteUpdateCardPreview`, `getPeople`, `deactivateExpiredEvents`, `processEventDeletions`, `cleanupOldTombstones`, `backfillEventTombstones`, `onActivityCreatedNotification`, `onActivityHeatingUp`, `onJoinRequestNotification`, `onJoinDecisionNotification`, `onActivityCanceledNotification`, `cleanupOnEventDelete`

### Fase 3 — Notifications + Webhooks + Devices (2-3 semanas) 🔴
> **Remove mais 3 cron jobs e 2 webhooks**

- [ ] Rodar migration: `Notifications` → tabela `notifications`
- [ ] Criar endpoints:
  - `GET /api/v1/notifications?cursor=...` (paginação cursor-based)
  - `PATCH /api/v1/notifications/:id/read` (marca como lida)
  - `PATCH /api/v1/notifications/read-all` (marca todas)
  - `POST /api/v1/webhooks/didit` (absorve `diditWebhook`)
  - `POST /api/v1/webhooks/revenuecat` (absorve `revenueCatWebhook`)
  - `POST /api/v1/devices/check` (absorve `checkDeviceBlacklist`)
  - `POST /api/v1/devices/register` (absorve `registerDevice`)
- [ ] Configurar WebSocket `notifications:{userId}`:
  - `notification:new` → nova notificação (substitui stream)
  - `notification:badge` → atualiza badge count
- [ ] Push dispatch via FCM HTTP v1 API (dentro dos endpoints que criam notificações)
- [ ] Cron jobs como scheduled endpoints:
  - `POST /api/v1/jobs/cleanup-notifications` (Cloud Scheduler diário)
  - `POST /api/v1/jobs/profile-view-notifications` (Cloud Scheduler 15 min)
- [ ] **Flutter:** Substituir 3 streams de `Notifications` por API + WebSocket
- [ ] **Eliminar coleções Firestore:** `Notifications`, `DeviceTokens`, `BlacklistDevices`
- [ ] **Eliminar Cloud Functions:** `onActivityNotificationCreated`, `cleanupOldNotifications`, `backfillMissingNotificationTimestamps`, `processProfileViewNotifications`, `checkDeviceBlacklist`, `registerDevice`, `diditWebhook`, `revenueCatWebhook`

### Fase 4 — Social: Follow + Feed + Photos (2-3 semanas) 🟡

- [ ] Rodar migration: `follows`, `event_photos`, `feeds`, `ActivityFeed`
- [ ] Criar endpoints:
  - `POST /api/v1/users/:id/follow` (absorve `followUser` — INSERT + update counts + notification + push)
  - `DELETE /api/v1/users/:id/follow` (absorve `unfollowUser`)
  - `GET /api/v1/users/:id/followers?page=1`
  - `GET /api/v1/users/:id/following?page=1`
  - `GET /api/v1/feed?cursor=...` (pull model — JOIN follows + event_photos)
  - `POST /api/v1/photos` (upload metadata)
  - `POST /api/v1/photos/:id/like`
  - `DELETE /api/v1/photos/:id/like`
  - `POST /api/v1/photos/:id/comments`
  - `GET /api/v1/photos/:id/comments`
- [ ] WebSocket `photo:{photoId}` para likes/comments em tempo real
- [ ] **Flutter:** Substituir streams de followers, likes, feed
- [ ] **Eliminar coleções Firestore:** `EventPhotos`, `feeds`, `ActivityFeed`, subcollections
- [ ] **Eliminar Cloud Functions:** `followUser`, `unfollowUser`, `onEventPhotoWriteFanout`, `onActivityFeedWriteFanout`, `onNewFollowerBackfillFeed`, `onUnfollowCleanupFeed`

### Fase 5 — Reviews + Profile Visits + Ranking (2 semanas) 🟡

- [ ] Rodar migration: `Reviews`, `PendingReviews`, `ProfileVisits`
- [ ] Criar endpoints:
  - `GET /api/v1/users/:id/reviews?page=1`
  - `POST /api/v1/reviews`
  - `GET /api/v1/reviews/pending` (lista de reviews pendentes)
  - `POST /api/v1/reviews/:id/confirm-presence`
  - `GET /api/v1/profile/visits` (com paginação)
  - `GET /api/v1/profile/visits/count`
  - `POST /api/v1/profile/:id/visit` (registrar visita)
  - `GET /api/v1/ranking?state=...&city=...`
  - `GET /api/v1/ranking/filters` (VIEW SQL — sem cron)
- [ ] Cron jobs:
  - `POST /api/v1/jobs/create-pending-reviews` (Cloud Scheduler 1h)
  - `POST /api/v1/jobs/cleanup-profile-visits` (Cloud Scheduler diário)
- [ ] **Flutter:** Substituir 6 streams de PendingReviews/Reviews por API polling (30s)
- [ ] **Eliminar coleções Firestore:** `Reviews`, `PendingReviews`, `ProfileVisits`, `ProfileViews`, `userRanking`, `locationRanking`, `ranking_filters`
- [ ] **Eliminar Cloud Functions:** `createPendingReviewsScheduled`, `onPresenceConfirmed`, `onReviewCreated`, `updateUserRatingOnReviewCreate`, `updateUserRatingOnReviewDelete`, `syncRankingFilters`, `updateUserRanking`, `updateLocationRanking`, `cleanupOldProfileVisits`, `processProfileViewNotificationsHttp`, `getProfileVisitsCount`

### Fase 6 — Subscriptions + Referrals + Reports + Account (1-2 semanas) 🟢

- [ ] Rodar migration: `Subscriptions`, `reports`, `ReferralInstalls`
- [ ] Criar endpoints:
  - `GET /api/v1/subscription/status`
  - `POST /api/v1/reports`
  - `DELETE /api/v1/account` (absorve `deleteUserAccount` — CASCADE deletes + Firebase Auth delete)
  - `POST /api/v1/referrals/validate`
- [ ] **Eliminar coleções Firestore:** `Subscriptions`, `SubscriptionEvents`, `reports`, `ReferralInstalls`, `WeddingAnnouncements`
- [ ] **Eliminar Cloud Functions:** `deleteUserAccount`, `onReportCreated`, `onUserCreatedReferral`

### Fase 7 — Cleanup Final (1-2 semanas) 🟢

- [ ] Remover todas as Cloud Functions exceto 3 (chat triggers)
- [ ] Limpar `functions/src/index.ts` — só exportar:
  - `onEventChatMessageCreated`
  - `onPrivateMessageCreated`
  - `deleteChatMessage`
- [ ] Remover Security Rules de coleções deletadas
- [ ] Atualizar `firestore.rules` — permitir apenas `Connections`, `EventChats`, `Messages`
- [ ] Remover `firestore.indexes.json` de coleções deletadas
- [ ] Deletar coleções vazias no Firestore Console
- [ ] **Flutter:** Remover todo código de Firestore direct access exceto chat
  - Remover `FirebaseFirestore.instance` de ~60 arquivos
  - Manter apenas em `chat_repository.dart` e `chat_service.dart`
- [ ] Remover `cloud_functions` package do pubspec.yaml (nenhum callable mais)
- [ ] Atualizar testes

### Fase 8 — Otimizações Pós-Migração (ongoing) 🟢

- [ ] Redis cache para hot data (users preview, app config, ranking)
- [ ] Connection pooling (PgBouncer ou Cloud SQL proxy com pool)
- [ ] Rate limiting por endpoint
- [ ] API versioning (`/api/v2/...` quando necessário)
- [ ] Monitoring (Cloud Monitoring + alertas)
- [ ] Avaliar migrar chat do Firestore para WebSocket + PostgreSQL (Fase futura)

---

## Parte 6 — O que NÃO muda (v2)

| Componente | Permanece em | Motivo |
|-----------|-------------|--------|
| Firebase Auth | Firebase | Core do auth, JWT |
| Chat streams (7) | Firestore | Real-time chat é insubstituível |
| 3 Chat triggers | Cloud Functions | Conversation sync + push |
| Cloud Storage | Firebase/GCS | Upload de fotos (barato) |

**Tudo o resto muda.**

---

## Parte 7 — Estimativa de Redução de Custos (v2)

| Componente | Antes (100% Firebase) | Depois (Auth+Chat only) | Redução |
|-----------|----------------------|------------------------|---------|
| Firestore Reads | 100% | ~10% (só chat) | **~90%** |
| Firestore Writes | 100% | ~10% (só chat) | **~90%** |
| Cloud Functions invocations | 100% | ~5% (3 triggers de chat) | **~95%** |
| Cloud Functions compute | 100% | ~5% | **~95%** |
| Cloud Storage | 100% | 100% (mantém) | 0% |
| **Novo: Cloud SQL PostgreSQL** | $0 | ~$7-25/mês | — |
| **Novo: Cloud Run (API)** | $0 | ~$15-40/mês | — |
| **Total estimado Firebase** | — | — | **~85-90% redução** |
| **Custo total infraestrutura** | — | — | **~60-70% redução** |

### Projeção de custos mensais (estimativa)

| Item | Antes | Depois |
|------|-------|--------|
| Firestore | $80-200 | $8-20 |
| Cloud Functions | $30-80 | $1-3 |
| Cloud Storage | $5-15 | $5-15 |
| Cloud SQL (PostgreSQL) | $0 | $7-25 |
| Cloud Run (API) | $0 | $15-40 |
| **Total** | **$115-295** | **$36-103** |

> Valores variam com o volume de usuários. PostgreSQL em `db-f1-micro` ($7/mês) com autoscale para `db-g1-small` ($25/mês) conforme cresce.

---

## Parte 8 — Riscos e Mitigações (v2)

| Risco | Probabilidade | Impacto | Mitigação |
|-------|--------------|---------|-----------|
| **UX de real-time degrada** (streams → polling/WS) | Média | Médio | WebSocket para dados críticos, polling 30s para rest |
| **Data migration falha/perde dados** | Baixa | Alto | Script idempotente, dry-run antes, backup Firestore, validação pós-import |
| **Cold start da API** | Baixa | Baixo | Min 1 instance Cloud Run ($7/mês) |
| **Complexidade de manter 2 DBs durante migração** | Alta | Médio | Feature flags no Flutter, migrar por fase, dual-write temporário |
| **WebSocket não escala** | Baixa | Alto | Cloud Run com múltiplas instâncias + Redis pub/sub para broadcast |
| **Chat break durante migração** | Baixa | Alto | Chat é a **última coisa tocada** — continua 100% Firestore |
| **Rollback necessário** | Média | Médio | Feature flags permitem voltar para Firestore a qualquer momento |
| **Latência aumenta para queries** | Baixa | Baixo | PostgreSQL + índices é mais rápido que Firestore + geohash |
| **Equipe precisa aprender Prisma/PostgreSQL** | Média | Baixo | Prisma é intuitivo, TS-first, migrations automáticas |

---

## Parte 9 — Data Migration Strategy

### Script de migração (Firestore → PostgreSQL)

Para cada fase, um script Node.js (TypeScript) que:
1. Lê todos os documentos da coleção Firestore
2. Transforma para o schema PostgreSQL
3. Insere via Prisma `createMany()` com `skipDuplicates: true`
4. Valida contagens (Firestore count === PostgreSQL count)

```typescript
// Exemplo: migrar Users
const usersSnapshot = await admin.firestore().collection('Users').get();
const users = usersSnapshot.docs.map(doc => ({
  id: doc.id,
  name: doc.data().name,
  email: doc.data().email,
  avatar_url: doc.data().avatarUrl,
  location: doc.data().lat && doc.data().lng
    ? `POINT(${doc.data().lng} ${doc.data().lat})`
    : null,
  interests: doc.data().interests || [],
  // ... map all fields
}));

await prisma.user.createMany({
  data: users,
  skipDuplicates: true,
});
```

### Estratégia de rollback por fase

Cada fase mantém:
- Feature flag no Flutter (`useApiForUsers`, `useApiForEvents`, etc.)
- Firestore data permanece read-only por 30 dias após migração
- Rollback = desliga feature flag → app volta a ler Firestore

---

## Conclusão (v2)

### O que sai do Firebase:
- **~60 Cloud Functions** → API NestJS + PostgreSQL triggers
- **9 Cron Jobs** → Cloud Scheduler + API endpoints
- **~28 coleções Firestore** → 20 tabelas PostgreSQL
- **~43 real-time streams** → WebSocket + API polling
- **5+ coleções de denormalização** → Eliminadas (JOINs e VIEWs)

### O que fica no Firebase:
- **Firebase Auth** (JWT, Phone, Apple Sign-In)
- **3 coleções Firestore** (Messages, EventChats, Conversations)
- **7 real-time streams** (chat only)
- **3 Cloud Functions** (chat triggers only)
- **Cloud Storage** (fotos)

### Stack final:
- **API:** NestJS (TypeScript) no Cloud Run
- **DB:** PostgreSQL + PostGIS no Cloud SQL
- **Auth:** Firebase Auth
- **Chat real-time:** Firestore
- **Real-time (não-chat):** WebSocket (Socket.IO)
- **Push:** FCM HTTP v1 via API
- **Storage:** Cloud Storage (Firebase/GCS)
- **ORM:** Prisma
- **Cache:** Redis (opcional, fase 8)

### Timeline total estimada:
**14-20 semanas** (Fase 0 a Fase 7), com Fase 8 contínua.

### Benefício principal:
De **$115-295/mês** para **$36-103/mês** — redução de **~65%** no custo total de infraestrutura, com arquitetura muito mais simples (sem denormalização, sem geohash, sem fan-out).
