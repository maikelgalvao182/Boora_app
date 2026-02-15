# Cloud Functions - Auditoria de Custos e Infraestrutura

**Data**: 15/02/2026  
**Projeto**: partiu-479902  
**Region padrão**: us-central1  
**Total de funções exportadas**: ~50+ (incluindo migrations)

---

## 1. Resumo Executivo

| Métrica | Valor |
|---------|-------|
| Funções Firestore Trigger | ~25 |
| Funções Scheduled (Cron) | 7 |
| Funções Callable (onCall) | 6 |
| Funções HTTP (onRequest) | 4 |
| Funções de Migração (one-time) | ~8 |
| App Engine | **Não encontrado** (nenhum app.yaml/app.json) |

---

## 2. Todas as Funções — Inventário Completo

### 2.1 Firestore Triggers (custo proporcional ao volume de writes)

| Função | Trigger Path | Tipo | Region | Memory | Timeout | Impacto de Custo |
|--------|-------------|------|--------|--------|---------|-----------------|
| `onEventCreated` | `events/{eventId}` onCreate | trigger | default | 256MB | 60s | **BAIXO** |
| `onApplicationApproved` | `EventApplications/{appId}` onWrite | trigger | default | 256MB | 60s | **ALTO** |
| `updateUserRanking` | `events/{eventId}` onCreate | trigger | default | 256MB | 60s | **BAIXO** |
| `updateLocationRanking` | `events/{eventId}` onCreate | trigger | default | 256MB | 60s | **MÉDIO-ALTO** |
| `onEventWriteUpdateCardPreview` | `events/{eventId}` onWrite | trigger | default | 256MB | 60s | **MÉDIO** |
| `onUserProfileUpdateSyncEvents` | `Users/{userId}` onWrite | trigger | default | 256MB | 60s | **MÉDIO** |
| `onUserWriteUpdatePreview` | `Users/{userId}` onWrite | trigger | default | 256MB | 60s | **MÉDIO** |
| `onUserAvatarUpdated` | `Users/{userId}` onUpdate | trigger | default | 256MB | 60s | **BAIXO** |
| `onUserLocationUpdated` | `Users/{userId}` onWrite | trigger | default | 256MB | 60s | **MÉDIO** |
| `onUserStatusChange` | `Users/{userId}` onWrite | trigger | default | 256MB | 60s | **BAIXO** |
| `syncRankingFilters` (trigger on Users) | cron (ver abaixo) | scheduled | us-central1 | 512MB | 540s | **ALTO** |
| `onActivityCreatedNotification` | `events/{eventId}` onCreate | trigger | default | 256MB | 60s | **ALTO** |
| `onActivityHeatingUp` | `EventApplications/{appId}` onWrite | trigger | default | 256MB | 60s | **ALTO** |
| `onJoinRequestNotification` | `EventApplications/{appId}` onCreate | trigger | default | 256MB | 60s | **MÉDIO** |
| `onJoinDecisionNotification` | `EventApplications/{appId}` onUpdate | trigger | default | 256MB | 60s | **BAIXO** |
| `onActivityCanceledNotification` | `events/{eventId}` onUpdate | trigger | default | 256MB | 60s | **MÉDIO** |
| `onActivityNotificationCreated` | `Notifications/{id}` onCreate | trigger | default | 256MB | 60s | **ALTO** |
| `onPrivateMessageCreated` | `Messages/{ownerId}/{partnerId}/{msgId}` onCreate | trigger | default | 256MB | 60s | **ALTO** |
| `onEventChatMessageCreated` | `EventChats/{eventId}/Messages/{msgId}` onCreate | trigger | default | 256MB | 60s | **ALTO** |
| `onEventPhotoWriteFanout` | `EventPhotos/{photoId}` onWrite | trigger | default | 256MB | 60s | **ALTO** |
| `onActivityFeedWriteFanout` | `ActivityFeed/{itemId}` onWrite | trigger | default | 256MB | 60s | **ALTO** |
| `onNewFollowerBackfillFeed` | `Users/{userId}/followers/{followerId}` onCreate | trigger | default | 256MB | 60s | **MÉDIO** |
| `onUnfollowCleanupFeed` | `Users/{userId}/followers/{followerId}` onDelete | trigger | default | 256MB | 60s | **MÉDIO** |
| `cleanupOnEventDelete` | `events/{eventId}` onDelete | trigger | default | 256MB | 60s | **BAIXO** |
| `onReportCreated` | `reports/{reportId}` onCreate | trigger | default | 256MB | 60s | **BAIXO** |
| `onUserCreatedReferral` | `Users/{userId}` onCreate | trigger | default | 256MB | 60s | **BAIXO** |
| `onReviewCreated` | `Reviews/{reviewId}` onCreate | trigger | default | 256MB | 60s | **BAIXO** |
| `updateUserRatingOnReviewCreate` | `Reviews/{reviewId}` onCreate | trigger | default | 256MB | 60s | **BAIXO** |
| `onPresenceConfirmed` | `PendingReviews/{reviewId}` onUpdate | trigger | us-central1 | 256MB | 60s | **BAIXO** |
| `deleteChatMessage` | Callable (onCall) | callable | default | 256MB | 60s | **MÉDIO** |

### 2.2 Scheduled Functions (Cron Jobs)

| Função | Schedule | Region | Memory | Timeout | Impacto de Custo |
|--------|----------|--------|--------|---------|-----------------|
| `deactivateExpiredEvents` | `0 0 * * *` (diário 00:00 BRT) | us-central1 | 512MB | 540s | **MÉDIO-ALTO** |
| `cleanupOldNotifications` | `10 3 * * *` (diário 03:10 BRT) | us-central1 | 512MB | 540s | **MÉDIO** |
| `cleanupOldProfileVisits` | `0 0 * * *` (diário 00:00 BRT) | default | 256MB | 60s | **BAIXO** |
| `cleanupOldTombstones` | `0 4 * * *` (diário 04:00 BRT) | us-central1 | 256MB | 300s | **BAIXO** |
| `processEventDeletions` | **every 5 minutes** | default | 256MB | 60s | **MÉDIO** |
| `processProfileViewNotifications` | **every 15 minutes** | default | 512MB | 540s | **MÉDIO-ALTO** |
| `syncRankingFilters` | **every 30 minutes** | us-central1 | 512MB | 540s | **ALTO** |
| `createPendingReviewsScheduled` | `every 1 hours` | us-central1 | 512MB | 540s | **MÉDIO** |
| `backfillMissingNotificationTimestamps` | `20 */2 * * *` (cada 2h) | us-central1 | 512MB | 540s | **BAIXO** |

### 2.3 Callable Functions (onCall)

| Função | Region | Memory | Timeout | Impacto de Custo |
|--------|--------|--------|---------|-----------------|
| `getPeople` | default | 256MB | 60s | **MUITO ALTO** |
| `followUser` | default | 256MB | 60s | **MÉDIO** |
| `unfollowUser` | default | 256MB | 60s | **MÉDIO** |
| `deleteEvent` | us-central1 | 256MB | 60s | **BAIXO** |
| `checkDeviceBlacklist` | us-central1 | 256MB | 60s | **MÉDIO** |
| `registerDevice` | us-central1 | 256MB | 60s | **BAIXO** |
| `getProfileVisitsCount` | default | 256MB | 60s | **MÉDIO** |
| `removeUserApplication` | default | 256MB | 60s | **BAIXO** |
| `removeParticipant` | default | 256MB | 60s | **BAIXO** |
| `deleteUserAccount` | default | 256MB | 60s | **BAIXO** (raro) |

### 2.4 HTTP Functions (onRequest)

| Função | Region | Memory | Impacto de Custo |
|--------|--------|--------|-----------------|
| `diditWebhook` | default | 256MB | **BAIXO** |
| `revenueCatWebhook` | default | 256MB (with secrets) | **BAIXO** |
| `debugCreateNotification` | default | 256MB | **BAIXO** (debug) |
| `backfillEventTombstones` | us-central1 | 512MB | **BAIXO** (one-time) |

### 2.5 Migration Functions (one-time, devem ser removidas após uso)

| Função | Tipo |
|--------|------|
| `backfillUserGeohash` | migration |
| `backfillEventCreatorData` | migration |
| `backfillEventPreviewsLocation` | migration |
| `backfillEventPreviewsCategory` | migration |
| `patchAddCountryFlag` | migration |
| `patchRemoveFormattedAddress` | migration |
| `migrateUserLocationToPrivate` | migration |
| `resyncUsersPreview` | migration |

---

## 3. App Engine

**Nenhuma configuração App Engine encontrada** (`app.yaml`, `app.json`). O projeto utiliza exclusivamente:
- Firebase Cloud Functions (v1)
- Firebase Hosting (configurado em `firebase.json` com `build/web`)
- Firestore
- Cloud Storage

---

## 4. Configuração firebase.json

```json
{
  "functions": [{
    "source": "functions",
    "codebase": "default",
    "predeploy": ["npm run lint", "npm run build"]
  }],
  "hosting": {
    "public": "build/web",
    "rewrites": [{"source": "**", "destination": "/index.html"}]
  }
}
```

**Observação**: Todas as funções estão na mesma codebase `default`. Não há separação por codebase, o que significa que um deploy atualiza TODAS as funções.

---

## 5. Ineficiências Críticas Identificadas

### 5.1 🔴 CRÍTICAS (Alto impacto no custo)

#### I1. `onApplicationApproved` — N+1 Reads em Participantes
- **Arquivo**: [index.ts](functions/src/index.ts#L200-L470)
- **Problema**: Quando uma application é aprovada, busca TODOS os participantes aprovados via query, depois faz `Promise.all()` para ler o documento de cada um individualmente.
- **Custo**: Se evento tem 20 participantes: 1 query + 20 reads + 20 writes (Conversations)
- **Impacto**: Cada aprovação gera ~40-60 operações Firestore
- **Solução**: Usar `users_preview` (500bytes) ao invés de ler `Users` completo (~5-10KB). Melhor ainda: manter `participantIds` já no EventChat e não requeriar toda vez.

#### I2. `onActivityCreatedNotification` — Geo Query na coleção Users INTEIRA
- **Arquivo**: [activityNotifications.ts](functions/src/activityNotifications.ts#L105-L185)
- **Problema**: `findUsersForEventNotification()` faz **2 queries paralelas** na coleção `Users` (displayLatitude + latitude legacy) com bounding box. Cada query pode retornar centenas de documentos.
- **Custo**: Até 1000 reads + 500 writes (notifications) por evento criado
- **Impacto**: **Cascata**: cada notification criada dispara `onActivityNotificationCreated` (push), que faz mais 1 read no Users para verificar preferências
- **Solução**: Usar geohash indexado em `users_preview` ao invés de bounding box em `Users`. Reduz reads em ~80%.

#### I3. `onActivityNotificationCreated` — Cascata de Push em CADA notificação
- **Arquivo**: [activityPushNotifications.ts](functions/src/activityPushNotifications.ts#L67)
- **Problema**: Dispara em `Notifications/{id}` onCreate. Cada notificação criada pelo I2 acima dispara esta função, que lê o `Users` doc para verificar preferências e buscar tokens FCM.
- **Custo**: Se I2 cria 200 notificações → 200 invocações desta função → 200 reads em Users
- **Impacto combinado I2+I3**: Criar 1 evento = ~400 reads Users + 200 writes Notifications + 200 reads pushDispatcher
- **Solução**: Batch de push via multicast FCM ou fila de processamento.

#### I4. `onEventChatMessageCreated` — Pre-fetch de Conversations + Update ALL
- **Arquivo**: [eventChatNotifications.ts](functions/src/eventChatNotifications.ts#L85-L130)
- **Problema**: Para cada mensagem no chat de grupo:
  1. Lê `EventChats/{eventId}` (1 read)
  2. Faz `Promise.all()` para ler Conversation de CADA participante (N reads)
  3. Atualiza Conversation de CADA participante (N writes no batch)
  4. Envia push para CADA participante (N invocações do pushDispatcher → N reads Users)
- **Custo**: Evento com 15 participantes: 1 + 15 + 15 + 15 = **46 operações por mensagem**
- **Solução**: Remover pre-fetch de leftEvent (usar subcoleção de participantes ativos). Usar FCM topic messaging ao invés de push individual.

#### I5. Feed Fanout — O(followers) writes por post
- **Arquivo**: [feedFanout.ts](functions/src/feed/feedFanout.ts#L85-L115)
- **Problema**: Cada EventPhoto ou ActivityFeed item gera 1 write por seguidor (fanout pattern).
- **Custo**: Usuário com 500 seguidores → 500 writes por post
- **Mitigação existente**: MAX_FOLLOWERS_FANOUT = 5000, BATCH_SIZE = 400
- **Nota**: Este é um trade-off arquitetural válido (write-heavy vs read-heavy). O custo é aceitável se o volume de posts for baixo e o volume de leituras do feed for alto.

#### I6. `getPeople` — Função mais chamada, sem configuração de memória/timeout otimizada
- **Arquivo**: [get_people.ts](functions/src/get_people.ts#L195)
- **Problema**: 
  1. Chamada a cada movimentação de mapa pelo usuário
  2. Faz read do doc `Users` completo para verificar VIP (poderia usar `users_preview`)
  3. Query em `users_preview` com fallback para `Users` (query dupla quando vazio)
  4. Sem região explícita — pode rodar longe do Firestore
  5. In-memory cache é por instância (perde eficácia com escalonamento)
- **Custo**: Possivelmente **a função mais cara do projeto** pelo volume de invocações
- **Solução**: Adicionar `.region("southamerica-east1")`, verificar VIP via claim no token ao invés de read, usar Firestore cache (TTL).

### 5.2 🟡 MÉDIAS (Custo relevante mas não crítico)

#### I7. `syncRankingFilters` — Lê TODA a coleção `users_preview` a cada 30 min
- **Arquivo**: [rankingFiltersSync.ts](functions/src/ranking/rankingFiltersSync.ts#L30-L90)
- **Problema**: Pagina por TODOS os documentos de `users_preview` usando `.select("state", "locality")` a cada 30 minutos.
- **Custo**: Se 10k usuários → 10k reads a cada 30min = **480k reads/dia**
- **Solução**: Executar 1x/dia ao invés de a cada 30min. Ou usar evento incremental (trigger em Users onWrite para adicionar ao set).

#### I8. `processEventDeletions` — Roda a **cada 5 minutos**
- **Arquivo**: [processEventDeletions.ts](functions/src/events/processEventDeletions.ts#L13)
- **Problema**: Mesmo sem jobs pendentes, faz 1 query no Firestore a cada 5 min.
- **Custo**: 288 invocações/dia × 1 read = 288 reads/dia (baixo), mas **288 execuções de function** (custo de compute)
- **Solução**: Aumentar intervalo para 15-30 min, ou usar Firestore trigger em `eventdeletions` onCreate.

#### I9. `processProfileViewNotifications` — Roda a cada 15 min
- **Arquivo**: [profileViewNotifications.ts](functions/src/profileViewNotifications.ts#L60)
- **Problema**: Query de até 1000 ProfileViews + para cada usuário agrupado, faz query de deduplicação em Notifications. MemÓria 512MB + timeout 540s para uma tarefa que normalmente processa poucos docs.
- **Custo**: Over-provisioned em memória
- **Solução**: Pode rodar a cada 30min-1h sem impacto na UX.

#### I10. `updateLocationRanking` — Query ALL events por placeId + N reads individuais
- **Arquivo**: [ranking/updateRanking.ts](functions/src/ranking/updateRanking.ts#L165-L230)
- **Problema**: A cada evento criado, faz query de TODOS os eventos ativos no mesmo local, depois lê User docs individualmente para os top 3 visitantes.
- **Custo**: Se local popular tem 50 eventos → 50 docs lidos + 3 User reads
- **Solução**: Usar `FieldValue.increment()` para totalVisitors sem recontagem.

#### I11. `getProfileVisitsCount` — Lê TODA a subcoleção sem limite
- **Arquivo**: [profileVisitsCount.ts](functions/src/profileVisitsCount.ts#L24-L35)
- **Problema**: `where("visitedUserId", "==", authUserId).get()` sem `.limit()`. Se usuário tem 5000 visitas, lê 5000 documentos.
- **Solução**: Usar contador agregado (FieldValue.increment) no doc do usuário.

#### I12. `deleteEventNotifications` — 3 queries paralelas na coleção Notifications
- **Arquivo**: [events/deleteEvent.ts](functions/src/events/deleteEvent.ts#L30-L45)
- **Problema**: Busca por `eventId`, `n_params.activityId`, e `n_related_id` em 3 queries paralelas com deduplicação manual.
- **Solução**: Usar 1 campo canônico + índice único.

### 5.3 🟢 BAIXAS (Bem implementadas ou baixo volume)

| Função | Por que é OK |
|--------|-------------|
| `onUserWriteUpdatePreview` | 1 write por trigger, merge eficiente |
| `onUserAvatarUpdated` | Early-exit se avatar não mudou |
| `onUserLocationUpdated` | Early-exit se coords não mudaram |
| `cleanupOldTombstones` | 1x/dia, 256MB, bem paginado |
| `cleanupOldProfileVisits` | 1x/dia, paginado |
| `onPresenceConfirmed` | 256MB, 60s timeout (dimensionado corretamente) |
| `followUser/unfollowUser` | Transaction atômica, poucas operações |

---

## 6. Triggers Empilhados no mesmo path (custo multiplicado)

### `events/{eventId}` onCreate — **4 triggers simultâneos**:
1. `onEventCreated` (index.ts) — cria application + chat + conversation
2. `updateUserRanking` (ranking) — atualiza ranking do usuário
3. `updateLocationRanking` (ranking) — atualiza ranking do local
4. `onActivityCreatedNotification` — geo query + batch notifications

**Custo combinado por evento criado**: ~500-1000+ Firestore operations

### `events/{eventId}` onWrite/onUpdate — **3 triggers**:
1. `onEventWriteUpdateCardPreview` — sync para events_card_preview
2. `onActivityCanceledNotification` — notifica participantes
3. (+ tombstone logic embutida no preview sync)

### `Users/{userId}` onWrite — **4 triggers simultâneos**:
1. `onUserWriteUpdatePreview` — sync para users_preview
2. `onUserLocationUpdated` — atualiza gridId/geohash
3. `onUserAvatarUpdated` — sync avatar
4. `onUserStatusChange` — blacklist devices

### `EventApplications/{id}` onWrite/onCreate — **3 triggers**:
1. `onApplicationApproved` — chat + conversations + push
2. `onActivityHeatingUp` — geo query + notifications
3. `onJoinRequestNotification` — notification para criador

---

## 7. Estimativa de Custo por Área

| Área | Invocações/dia (estimada) | Reads/dia | Writes/dia | Prioridade de otimização |
|------|--------------------------|-----------|------------|--------------------------|
| **getPeople** | Alta (cada interação de mapa) | 2-5 per call × N calls | 0 | 🔴 **P0** |
| **Notification Cascade** (I2+I3) | Per evento criado × ~300 | ~600 per evento | ~300 per evento | 🔴 **P0** |
| **EventChat Messages** (I4) | Per mensagem × participantes | ~3N per msg | ~N per msg | 🔴 **P1** |
| **Feed Fanout** (I5) | Per post × followers | ~N per post | ~N per post | 🟡 **P1** |
| **syncRankingFilters** (I7) | 48/dia | ~480k/dia (10k users) | 1 | 🔴 **P0** |
| **processEventDeletions** (I8) | 288/dia | ~288/dia | varies | 🟡 **P2** |
| **Users onWrite triggers** (4x) | Per user update × 4 | ~4 per update | ~4 per update | 🟡 **P2** |

---

## 8. Configurações Ausentes ou Sub-ótimas

### 8.1 Region
- **Problema**: A maioria das funções não especifica `region()`, rodando em `us-central1` (default).
- **Firestore location**: Provavelmente `us-central1` (ok se sim).
- **Recomendação**: Se os usuários são predominantemente do Brasil, considerar `southamerica-east1` para Firestore + Functions para reduzir latência. Mas cuidado: Firestore e Functions devem estar na mesma região.

### 8.2 Memory
- **Problema**: Funções leves como `onReportCreated`, `onReviewCreated` usam 256MB default (ok).
- **Problema**: `getPeople` (potencialmente a mais pesada por volume) não tem configuração explícita de memória.
- **Recomendação**: `getPeople` deveria ter `.runWith({memory: "512MB"})` pelo volume de dados processados.

### 8.3 Concurrency & Min Instances
- **Nenhuma função** configura `minInstances` (cold starts possíveis).
- **Nenhuma função** usa Gen2 (`firebase-functions/v2`) que oferece concurrency nativo.
- **Recomendação**: `getPeople` e `onPrivateMessageCreated` seriam fortes candidatas para `minInstances: 1` (se custo de idle justificar).

---

## 9. Funções de Migração que Devem Ser Removidas

As seguintes funções são one-time migrations e **continuam deployadas**, consumindo slots de deploy e cold-start pool:

1. `patchAddCountryFlag`
2. `patchRemoveFormattedAddress`
3. `backfillUserGeohash`
4. `backfillEventCreatorData`
5. `backfillEventPreviewsLocation`
6. `backfillEventPreviewsCategory`
7. `migrateUserLocationToPrivate`
8. `resyncUsersPreview`
9. `backfillEventTombstones`
10. `backfillMissingNotificationTimestamps` (cron a cada 2h — deveria ser removido se backlog zerado)
11. `debugCreateNotification` (debug — não deveria estar em produção)

**Recomendação**: Remover do `index.ts` após confirmar que migrações foram concluídas. Cada função deployada consome recursos no container pool.

---

## 10. Top 5 Ações de Maior Impacto em Redução de Custo

| # | Ação | Redução Estimada | Esforço |
|---|------|-----------------|---------|
| 1 | **Reduzir frequência do `syncRankingFilters`** de 30min → 1x/dia | ~90% reads desta função (~430k reads/dia) | Baixo |
| 2 | **Otimizar `getPeople`**: VIP check via custom claim, region explícita, `users_preview` only | ~50% reads desta função | Médio |
| 3 | **Batch notification push**: ao invés de 1 function invocation por notification, agrupar em multicast FCM | ~80% das invocações de `onActivityNotificationCreated` | Alto |
| 4 | **`onApplicationApproved`**: usar `users_preview` ao invés de N reads em `Users` | ~70% reads por aprovação | Baixo |
| 5 | **Remover ~11 migration/debug functions** do deploy | Reduz cold-start pool e deploy time | Trivial |
