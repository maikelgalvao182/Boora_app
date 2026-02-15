# Auditoria Completa — Redução de Custos Cloud Storage + App Engine / Cloud Functions

> **Data:** 15/02/2026  
> **Projeto:** Partiu (partiu-479902)  
> **Escopo:** Cloud Storage, Cloud Functions (Firebase), Cloud Run, Firestore (impacto indireto em App Engine billing)  
> **Status:** Diagnóstico completo com recomendações priorizadas

---

## Sumário Executivo

A infraestrutura do Partiu **não possui App Engine explícito** — o custo rotulado como "App Engine" no billing do GCP corresponde provavelmente a:

1. **Cloud Functions v1** (63 funções deployadas) — executam na infraestrutura App Engine internamente
2. **Instância default do App Engine** criada automaticamente pelo GCP ao ativar Cloud Functions v1
3. **Cloud Run** (`partiu-websocket`) — serviço NestJS WebSocket com 1 CPU / 512Mi

> **Importante:** Cloud Functions v1 do Firebase são executadas internamente no App Engine Flex/Standard. No billing do GCP, elas aparecem como custo de "App Engine" e não como "Cloud Functions". Isso explica por que "App Engine" é o maior custo mesmo sem app.yaml no repositório.

### Resumo de Impacto Estimado

| Categoria | Economia Estimada | Esforço | Prioridade |
|-----------|-------------------|---------|------------|
| Eliminar funções desnecessárias (11 migrations/debug) | 5-8% do custo Functions | Baixo | 🔴 Imediata |
| Otimizar cron jobs (reduzir frequência) | 10-15% do custo Functions | Baixo | 🔴 Imediata |
| Corrigir listeners Firestore no client (custo indireto) | 20-30% das leituras | Médio | 🔴 Alta |
| Eliminar streams sem `.limit()` | 15-20% das leituras | Médio | 🔴 Alta |
| Otimizar Feed Fanout (N writes per follower) | 10-15% das escritas | Alto | 🟡 Média |
| Gerar thumbnails server-side (reduz egress Storage) | 15-25% do egress | Médio | 🟡 Média |
| Migrar para Cloud Functions v2 (gen2) | 15-30% do custo Functions | Médio | 🟡 Média |
| Migrar para API própria (PostgreSQL) | 85-90% do Firestore | Muito Alto | 🟢 Longo prazo |

---

## Parte 1 — App Engine / Cloud Functions: Diagnóstico Detalhado

### 1.1 Por que "App Engine" aparece como maior custo

Cloud Functions v1 do Firebase são **executadas internamente na infraestrutura App Engine**. No console de billing do GCP:

- **Compute** das Cloud Functions → aparece como "App Engine"
- **Invocações** → aparecem como "Cloud Functions"
- **Memória/CPU** alocada por função → contabilizada como App Engine instance hours

**O projeto tem 63 Cloud Functions deployadas**, sendo que pelo menos **11 são migrations/debug que deveriam ser removidas** e **9 cron jobs** que executam em intervalos variados (5 min a diário).

### 1.2 Funções para Remoção Imediata (custo zero útil)

Estas funções são de migração/debug e **não deveriam estar deployadas em produção**:

| Função | Tipo | Por que remover |
|--------|------|-----------------|
| `backfillUserGeohash` | HTTP | Migração pontual já executada |
| `backfillEventCreatorData` | HTTP | Migração pontual já executada |
| `backfillEventPreviewsLocation` | HTTP | Migração pontual já executada |
| `backfillEventPreviewsCategory` | HTTP | Migração pontual já executada |
| `backfillMissingNotificationTimestamps` | Cron (2h) | Backfill — deveria ser one-shot |
| `migrateUserLocationToPrivate` | HTTP | Migração pontual já executada |
| `resyncUsersPreview` | HTTP | Manutenção pontual |
| `patchAddCountryFlag` | HTTP | Patch pontual já executado |
| `patchRemoveFormattedAddress` | HTTP | Patch pontual já executado |
| `debugCreateNotification` | HTTP | Debug — nunca deveria estar em produção |
| `backfillMissingNotificationTimestamps` | Cron | Correção que roda a cada 2h desnecessariamente |

**Ação:** Remover exports do `index.ts` e re-deploy. Economia estimada: **~$5-15/mês** em instance hours ociosas + eliminação de execuções desnecessárias do cron.

### 1.3 Cron Jobs — Otimização de Frequência

| Job | Frequência Atual | Frequência Recomendada | Economia |
|-----|------------------|------------------------|----------|
| `processEventDeletions` | **A cada 5 min** | A cada 1 hora ou Firestore trigger | **~288 → 24 execuções/dia** (92% menos) |
| `syncRankingFilters` | **A cada 30 min** | 1x/dia (03:00) | **~48 → 1 execução/dia** (98% menos) |
| `processProfileViewNotifications` | A cada 15 min | A cada 1 hora | **~96 → 24 execuções/dia** (75% menos) |
| `createPendingReviewsScheduled` | A cada 1 hora | A cada 6 horas | **~24 → 4 execuções/dia** (83% menos) |

**Detalhamento de `syncRankingFilters`:**
- Lê a **coleção `users_preview` INTEIRA** (paginada em blocos de 500)
- Com 10.000 usuários = ~20 reads de página + 10.000 reads de documentos = **~10.020 leituras por execução**
- A cada 30 min = **~480.960 leituras/dia** só para extrair `DISTINCT state, city`
- Configuração: 512MB memória, 540s timeout
- **Solução:** Reduzir para 1x/dia → ~10.020 leituras/dia (economia de ~470k leituras/dia)

**Detalhamento de `processEventDeletions`:**
- Roda a cada 5 minutos e lê todos os eventos marcados como "pending deletion"
- Multi-fase: messages → applications → notifications → feedItems → finalize
- **Solução:** Trocar cron de 5 min por Firestore trigger `onUpdate` no campo `deletionStatus`

### 1.4 Cloud Functions com Custo Operacional Alto

#### 🔴 `onActivityCreatedNotification` — Geo-query + N writes por evento

**O que faz:** Quando um evento é criado, busca todos os usuários num raio geográfico e cria 1 notificação por usuário.

**Custo por execução:**
- 1 read do criador (`Users`)
- 1 query geográfica na coleção `Users` (até 500 docs)
- **Até 500 writes** na coleção `Notifications`
- Total: **~502 operações Firestore por evento criado**

**Recomendação:**
- Limitar resultados do geo-query (`.limit(100)` em vez de 500)
- Usar `users_preview` em vez de `Users` (documento menor = menor egress)
- Considerar batch notification com document-array em vez de 1 doc por notificação

#### 🔴 `onApplicationApproved` — N+1 reads por aprovação

**O que faz:** Quando uma application é aprovada, busca dados do evento, do usuário, de TODAS as applications aprovadas, e depois busca o doc completo `Users` de **cada participante individualmente**.

**Custo por execução (evento com 15 participantes):**
- 2 reads paralelas (`events` + `Users`)
- 1 query em `EventApplications` (~15 docs)
- **15 reads individuais** em `Users` (N+1 pattern)
- 15+ writes em `Connections/Conversations`
- 1 write de mensagem em `EventChats/Messages`
- Total: **~50 operações por aprovação**

**Recomendação:**
- Usar `users_preview` em vez de `Users` completo
- Usar `getAll()` (batch read) em vez de `Promise.all(map(doc.get()))` individual
- Guardar dados mínimos dos participantes no `EventChat.participantIds` para evitar re-fetch

#### 🔴 Feed Fanout System — N writes por post

**O que faz:** Para cada foto/atividade postada, cria 1 entrada no feed de **cada seguidor**.

**Custo por execução:**
- `onEventPhotoWriteFanout`: até **5.000 writes** (1 por seguidor)
- `onActivityFeedWriteFanout`: até **5.000 writes** (1 por seguidor)
- `onNewFollowerBackfillFeed`: lê últimos 20 EventPhotos + 20 ActivityFeed do autor, escreve tudo no feed do novo seguidor
- `onUnfollowCleanupFeed`: query all items by author + delete in batches

**Recomendação:**
- Migrar para **pull model** (o feed é montado no momento da leitura via query, não por fan-out de escrita)
- Alternativa: limitar fan-out para os primeiros 500 seguidores mais recentes

#### 🟡 `onEventWriteUpdateCardPreview` — Denormalização por write

**O que faz:** A cada write na coleção `events`, lê o criador de `Users` e escreve/atualiza `events_card_preview`.

**Custo:** 2 operações Firestore extras **por cada update no evento**.

**Recomendação:** Eliminar `events_card_preview` e fazer JOIN no client (ou migrar para API com PostgreSQL).

#### 🟡 `onUserProfileUpdateSyncEvents` — Cascata de updates

**O que faz:** Quando o perfil do usuário muda, lê TODOS os `events_card_preview` daquele usuário e batch-update em todos.

**Custo:** Se um usuário criou 50 eventos → 51 reads + 50 writes por update de perfil.

#### 🟡 `updateLocationRanking` — Query unbounded por evento

**O que faz:** Na criação de evento, faz query de TODOS os eventos ativos no mesmo `placeId` + reads individuais de usuários.

**Recomendação:** Usar counter incremental em vez de reagregar tudo a cada evento.

### 1.5 Migração para Cloud Functions v2 (gen2)

Cloud Functions v2 usa **Cloud Run** internamente (não App Engine), com billing diferente:

| Aspecto | v1 (atual) | v2 (gen2) |
|---------|-----------|-----------|
| Runtime | App Engine | Cloud Run |
| Billing | Instance-hours (idle cobra) | Por request (concurrency-aware) |
| Concurrency | 1 request por instância | Até 1000 por instância |
| Cold starts | ~500ms-2s | ~200ms-1s |
| Min instances | Não configurável facilmente | Configurável (0 = sem custo idle) |
| Custo típico | Mais caro para funções leves | **30-50% mais barato** |

**Ação recomendada:** Migrar as funções mais invocadas (`getPeople`, `onEventChatMessageCreated`, `activityPushNotifications`) para v2 primeiro.

```typescript
// v1 (atual)
import * as functions from "firebase-functions/v1";
export const getPeople = functions.https.onCall(async (data, context) => { ... });

// v2 (recomendado)
import { onCall } from "firebase-functions/v2/https";
export const getPeople = onCall({ 
  region: "southamerica-east1", // São Paulo
  memory: "256MiB",
  concurrency: 80,
  minInstances: 0, // Zero custo idle
}, async (request) => { ... });
```

---

## Parte 2 — Cloud Storage: Diagnóstico e Otimizações

### 2.1 Estrutura Atual de Storage

| Path | Max Size | Uso |
|------|----------|-----|
| `users/{uid}/profile/**` | 15 MB | Avatares de perfil |
| `users/{uid}/gallery/**` | 15 MB | Galeria do usuário |
| `users/{uid}/videos/**` | 200 MB | Vídeos do usuário |
| `events/{eventId}/cover/**` | 15 MB | Capas de eventos |
| `events/{eventId}/photos/{uid}/**` | 10 MB | Fotos de participantes |
| `event_photos/{eventId}/{fileName}` | 15 MB | Event Photo Feed |
| `messages/{uid}/**` | 15 MB | Arquivos de chat |
| `chat_images/**` | 15 MB | Imagens de chat |

### 2.2 Compressão Client-Side (já implementada)

| Contexto | Dimensão Máx | Qualidade | Observação |
|----------|--------------|-----------|------------|
| Picker geral | 1920×1920 | 85 | ✅ Bom |
| Avatar | 800×800 | 80 | ✅ Bom |
| Event Photo Feed | 1080×1080 | 82 | ✅ Bom |
| Thumb Event Photo | 420×420 | 70 | ✅ Bom |
| Chat images | 1080×1080 | 75 | ✅ Bom |
| Gallery (upload) | 1080×1080 | 75 | ⚠️ Picker em 1920 depois comprime para 1080 — etapa desnecessária |

### 2.3 Problemas Identificados em Cloud Storage

#### 🔴 PROBLEMA 1: Sem Thumbnails Server-Side

Apenas o Event Photo Feed gera thumbnail client-side (420px). **Perfil, galeria e chat não têm thumbnails.**

**Impacto:**
- Listas que mostram avatares/previews baixam a imagem completa (1080px, ~200-500KB)
- Em uma lista de 50 usuários, são **~25MB de download** quando 50 thumbnails de 100px seriam ~500KB
- **Egress de Storage é o principal custo de Cloud Storage**

**Recomendação:**
- Instalar a extensão Firebase **"Resize Images"** (`storage-resize-images`)
- Configurar para gerar thumbnails automáticos: 150px (avatar list), 400px (preview), original
- Path: `users/{uid}/profile/` → gera `thumb_150x150_`, `thumb_400x400_`
- Custo da extensão: ~$0.01 por 1000 imagens processadas (Cloud Functions)
- **Economia estimada: 60-80% do egress de Storage para imagens de perfil**

#### 🔴 PROBLEMA 2: `AvatarStore` usa `NetworkImage` (sem cache em disco)

**Arquivo:** `lib/shared/stores/avatar_store.dart`

```dart
final provider = NetworkImage(imageUrl);
```

`NetworkImage` usa apenas o `ImageCache` do Flutter (cache em memória) que é **volátil** — imagens são re-baixadas quando o cache de memória é limpo (troca de tab, scroll longo, etc.).

**Impacto:** Cada vez que um avatar some do cache de memória, ele é baixado novamente do Cloud Storage (egress pago).

**Recomendação:** Migrar para `CachedNetworkImageProvider` (mesmo que o app já use em `StableAvatar`):

```dart
// ❌ Atual:
final provider = NetworkImage(imageUrl);

// ✅ Recomendado:
final provider = CachedNetworkImageProvider(imageUrl, cacheManager: avatarCacheManager);
```

#### 🟡 PROBLEMA 3: Comentários do Feed usam `NetworkImage`

Imagens de comentaristas em Event Photo Feed usam `NetworkImage` direto — sem cache em disco.
- Cada scroll no feed re-baixa os avatares dos comentaristas
- volume menor que AvatarStore, mas ainda gera egress desnecessário

#### 🟡 PROBLEMA 4: Compressão dupla em Gallery Upload

O picker captura em 1920×1920/q85, e depois o ViewModel comprime para 1080×1080/q75.

**Recomendação:** Configurar o picker diretamente para 1080×1080 (elimina processamento intermediário e uso de memória).

#### 🟡 PROBLEMA 5: Sem lifecycle policies no Cloud Storage

Não há lifecycle rules configuradas para:
- Deletar automaticamente imagens de eventos expirados
- Mover imagens antigas para Nearline/Coldline storage
- Limpar uploads órfãos (usuários deletados)

**Recomendação:**
```json
// gsutil lifecycle set:
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 180, "matchesPrefix": ["events/"]}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"age": 365, "matchesPrefix": ["events/"]}
    }
  ]
}
```

### 2.4 CDN / Cache Headers

**Verificar se os objetos do Cloud Storage estão sendo servidos com headers de cache adequados:**

```bash
# Verificar headers atuais
gsutil stat gs://partiu-479902.appspot.com/users/test/profile/photo.jpg

# Configurar cache para avatares (cache público de 24h)
gsutil -m setmeta -h "Cache-Control:public, max-age=86400" gs://partiu-479902.appspot.com/users/**

# Configurar cache para event photos (cache público de 7 dias)
gsutil -m setmeta -h "Cache-Control:public, max-age=604800" gs://partiu-479902.appspot.com/events/**
```

**Se os headers não estiverem configurados, cada acesso a `getDownloadURL()` paga egress sem cache intermediário.**

---

## Parte 3 — Firestore (Client-Side): Maiores Gargalos de Custo

O custo de Firestore é **leitura-dominante** e impacta indiretamente o billing de App Engine (via Cloud Functions triggers).

### 3.1 Top 10 Problemas de Custo no Client Flutter

#### 🔴 #1 — Mapa carrega TODOS os eventos do mundo

**Arquivo:** `lib/features/home/data/repositories/event_map_repository.dart`

```dart
.collection('events')
.where('isActive', isEqualTo: true)
.where('status', isEqualTo: 'active')
.snapshots(includeMetadataChanges: true) // TODOS os eventos, sem filtro geo, sem limit
```

**Impacto:**
- Com 1.000 eventos ativos → 1.000 reads no primeiro load + websocket contínuo
- `includeMetadataChanges: true` → **dobra o número de snapshots** (local + server)
- Cada novo evento criado por qualquer usuário → snapshot para TODOS os clients conectados
- **Estimativa: 50-70% de todas as leituras Firestore da aplicação**

**Recomendação:**
- Implementar filtro por geohash prefix (já existem índices)
- Adicionar `.limit(100)` ou `.limit(200)`
- Remover `includeMetadataChanges: true`
- Usar debounce de viewport para queries por bounds

#### 🔴 #2 — 3 listeners por Event Card visível

**Arquivo:** `lib/features/home/presentation/widgets/event_card/event_card_controller.dart`

Cada card aberto cria 3 streams Firestore:
1. `EventApplications` (application do usuário) — `.limit(1)` ✅  
2. `events/{eventId}` (documento do evento) — doc listener
3. `EventApplications` approved (participantes) — **SEM `.limit()`** ❌

**Impacto:** 10 cards visíveis = **30 listeners simultâneos** + getter `participantsCountStream` pode criar duplicata = **40 listeners**.

**Recomendação:**
- Substituir listener #3 por counter field no documento do evento (`participantCount`)
- Substituir listener #2 por dados já carregados do mapa (não precisa ser real-time)
- Resultado: **de 30-40 listeners para 10** (só application status)

#### 🔴 #3 — AvatarStore + UserStore = 2-3 listeners por usuário

**Arquivos:** `lib/shared/stores/avatar_store.dart` + `lib/shared/stores/user_store.dart`

Para cada usuário visto no app:
- `AvatarStore` → 1 listener em `Users/{uid}.snapshots()` (permanente)
- `UserStore` → 1 listener em `users_preview/{uid}.snapshots()` (permanente)
- `UserStore` (full) → 1 listener adicional em `Users/{uid}.snapshots()`

**Impacto:** Após navigar por 50 perfis → **100-150 listeners Firestore simultâneos** que nunca são cancelados.

**Recomendação:**
- Substituir `.snapshots()` por `.get()` + cache TTL (10 min) no `UserCacheService`
- Manter listener APENAS para o usuário logado
- Implementar LRU cache com hard cap (ex: máx 30 listeners ativos)

#### 🔴 #4 — Counter Service streams 1000 docs para contar um inteiro

**Arquivo:** `lib/common/services/notifications_counter_service.dart`

```dart
// Stream 1: 1000 docs de Conversations para contar unread
.limit(1000).snapshots()

// Stream 2: 1000 docs de Notifications para contar n_read==false  
.limit(1000).snapshots()
```

**Impacto:** Transmite até **2.000 documentos completos** a cada mudança, apenas para contar badges.

**Recomendação:**
- Usar **Firestore Aggregation Query** (`count()`) — disponível desde 2023
- Ou manter counter field atômico com `FieldValue.increment(1)` nas Cloud Functions
- Resultado: de 2.000 reads para **2 reads** por atualização

#### 🔴 #5 — Notifications stream sem `.limit()`

**Arquivo:** `lib/features/notifications/repositories/notifications_repository.dart`

```dart
query.orderBy(_fieldTimestamp, descending: true).snapshots() // SEM LIMIT
```

**Impacto:** Usuário com 500 notificações → 500 docs transmitidos a cada nova notificação (stream atualiza com snapshot completo).

**Recomendação:** Trocar para `getNotificationsPaginatedStream()` que já existe com `.limit(20)`.

#### 🟡 #6 — Block Service: 2 streams sem limit

**Arquivo:** `lib/core/services/block_service.dart`

2 streams permanentes sem `.limit()` na coleção `blockedUsers`. Cresce linearmente com número de blocks.

#### 🟡 #7 — List Drawer: stream de todos os eventos do criador

**Arquivo:** `lib/features/home/presentation/widgets/list_drawer/list_drawer_controller.dart`

```dart
.collection('events')
.where('createdBy', isEqualTo: userId)
.orderBy('createdAt', descending: true)
.snapshots() // SEM LIMIT — criador prolífico com 200+ eventos = 200 docs
```

**Recomendação:** Adicionar `.limit(20)` com paginação sob demanda.

#### 🟡 #8 — Pending Applications: nested streams (N+1)

**Arquivo:** `lib/features/home/data/repositories/pending_applications_repository.dart`

Stream dentro de stream: outer stream sem limit cancela/recria inner stream a cada emissão.

#### 🟡 #9 — Profile Completeness como stream

**Arquivo:** `lib/features/profile/data/services/profile_completeness_prompt_service.dart`

Listener permanente em `Users/{uid}` para calcular % de completude — muda 1x/semana. Deveria ser `.get()`.

#### 🟢 #10 — `collectionGroup('likes')` (controlado)

Tem `.limit()` e é one-time read. Baixo custo, mas monitorar em escala.

### 3.2 Índices Firestore — Inconsistências

| Problema | Impacto |
|----------|---------|
| Coleção `Events` (maiúsculo) vs `events` (minúsculo) — ambas com índices | Possível duplicação de coleções ou índices ociosos |
| Chat collections sem nenhum índice composto | Queries compostas no chat fazem full collection scan |
| `Notifications` sem índice `userId + n_read` | Query de "não lidos" faz full scan com filtro client-side |
| `users_preview` sem índice de geohash | Geo-queries em users fazem range scan por latitude |

---

## Parte 4 — Cloud Run (`partiu-websocket`): Diagnóstico

### 4.1 Configuração Atual

| Detalhe | Valor |
|---------|-------|
| Serviço | `partiu-websocket` |
| Framework | NestJS 11 + Socket.IO |
| CPU | 1 |
| Memória | 512Mi |
| Região | `us-central1` (longe dos usuários BR) |
| Auth | `--allow-unauthenticated` |
| Timeout | 300s |
| Projeto Firebase | `partiu-app` (**diferente do Flutter: `partiu-479902`**) |

### 4.2 Problemas Identificados

#### 🔴 Região errada
Serviço em `us-central1` mas usuários estão no Brasil. Latência adicional de ~150ms por request.

**Recomendação:** Migrar para `southamerica-east1` (São Paulo).

#### 🟡 Possível instância ociosa
WebSocket connections mantêm instância ativa. Se poucos usuários usam WebSocket, a instância pode ficar ociosa pagando CPU/memória.

**Verificar no GCP Console:**
- Métricas de conexões ativas por hora
- Instance count vs requests/connections
- Se < 10 conexões/hora → considerar desligar e usar polling HTTP

#### 🟡 Projeto Firebase diferente
Cloud Run aponta para `partiu-app` enquanto o Flutter usa `partiu-479902`. Verificar se são o mesmo projeto ou se há duplicação de custos Firestore.

---

## Parte 5 — Plano de Ação Priorizado

### Fase 1 — Quick Wins (1-2 dias, economia imediata)

| # | Ação | Economia Estimada | Arquivo(s) |
|---|------|-------------------|------------|
| 1.1 | Remover 11 functions de migration/debug do deploy | $5-15/mês | `functions/src/index.ts` |
| 1.2 | Reduzir `syncRankingFilters` para 1x/dia | ~470k reads/dia | `functions/src/ranking/rankingFiltersSync.ts` |
| 1.3 | Reduzir `processEventDeletions` para 1x/hora | ~276 execuções/dia a menos | `functions/src/events/processEventDeletions.ts` |
| 1.4 | Remover `includeMetadataChanges: true` do mapa | ~50% dos snapshots do mapa | `lib/features/home/data/repositories/event_map_repository.dart` |
| 1.5 | Adicionar `.limit()` nos 5 streams sem limit | Reduz payload de cada snapshot | Vários (listados na Parte 3) |
| 1.6 | Configurar Cache-Control headers no Storage | Reduz egress em revisitas | `gsutil` command |

### Fase 2 — Otimizações Importantes (1-2 semanas)

| # | Ação | Economia Estimada | Arquivo(s) |
|---|------|-------------------|------------|
| 2.1 | Substituir `NetworkImage` por `CachedNetworkImageProvider` no AvatarStore | 30-50% do egress de avatares | `lib/shared/stores/avatar_store.dart` |
| 2.2 | Converter AvatarStore/UserStore de `.snapshots()` para `.get()` + cache | 100+ listeners permanentes eliminados | `avatar_store.dart`, `user_store.dart` |
| 2.3 | Substituir counter service streams por aggregation query ou counter field | 2.000 → 2 reads por badge update | `notifications_counter_service.dart` |
| 2.4 | Reduzir listeners do Event Card de 3 para 1 | 20+ listeners eliminados na tela principal | `event_card_controller.dart` |
| 2.5 | Instalar extensão Firebase "Resize Images" | 60-80% do egress de perfil | Firebase Console |
| 2.6 | Otimizar `onApplicationApproved` (batch read + users_preview) | 50% das reads por aprovação | `functions/src/index.ts` |
| 2.7 | Corrigir `onActivityCreatedNotification` (limitar geo-query) | 500 → 100 writes por evento | `functions/src/activityNotifications.ts` |
| 2.8 | Mover Cloud Run para `southamerica-east1` | Latência -150ms | `wedding-websocket/cloudbuild.yaml` |

### Fase 3 — Refatorações Estruturais (1-2 meses)

| # | Ação | Economia Estimada | Complexidade |
|---|------|-------------------|--------------|
| 3.1 | Migrar mapa para query por geohash/viewport | 50-70% das leituras totais | Alta |
| 3.2 | Migrar feed de fan-out (push) para pull model | 5.000 writes/post → 0 | Alta |
| 3.3 | Eliminar `events_card_preview` e `users_preview` (usar projections no read) | 2 coleções inteiras + triggers | Média |
| 3.4 | Migrar Cloud Functions v1 → v2 (gen2) | 15-30% do custo Functions | Média |
| 3.5 | Configurar lifecycle policies no Cloud Storage | Reduz storage em GB | Baixa |

### Fase 4 — Migração para API Própria (3-6 meses)

Conforme documentado em `PLANO_MIGRACAO_API_PROPRIA.md`:
- Manter no Firebase: **apenas Auth + Chat** (3 coleções, ~7 streams)
- Migrar tudo para: **API NestJS + PostgreSQL (PostGIS)**
- Economia estimada: **85-90% do custo Firestore**
- Eliminação de **~60 Cloud Functions** (restam apenas 3 de chat)

---

## Parte 6 — Métricas para Monitoramento

### Dashboard Recomendado (GCP Monitoring)

```
Métricas essenciais:
1. Firestore reads/writes por coleção por hora
2. Cloud Functions invocations por função por hora
3. Cloud Functions execution time (p99) por função
4. Cloud Storage egress (bytes) por bucket/path
5. Cloud Run instance count e billable time
6. Cloud Functions active instances (App Engine billing)
```

### Comandos de Verificação

```bash
# Verificar se há App Engine default service ativo
gcloud app versions list --project=partiu-479902

# Verificar custos por serviço
gcloud billing accounts list
gcloud alpha billing budgets list

# Verificar Cloud Functions deployadas
firebase functions:list --project=partiu-479902

# Verificar storage lifecycle rules
gsutil lifecycle get gs://partiu-479902.appspot.com

# Verificar Cloud Run instances  
gcloud run services describe partiu-websocket --region=us-central1

# Ver métricas de Firestore
gcloud firestore operations list --project=partiu-479902
```

---

## Conclusão

O custo rotulado como "App Engine" vem quase inteiramente das **63 Cloud Functions v1** que executam na infraestrutura App Engine. As ações de maior impacto imediato são:

1. **Remover 11 funções de migration/debug** do deploy
2. **Reduzir frequência dos cron jobs** (especialmente `syncRankingFilters`)
3. **Corrigir streams sem `.limit()`** no Flutter (especialmente mapa e notifications)
4. **Migrar para Cloud Functions v2** (billing por request, não por instance-hour)

A soma dessas 4 ações pode reduzir **30-50% do custo atual de "App Engine/Functions"** antes de qualquer migração para API própria.

Para Cloud Storage, instalar **"Resize Images"** no Firebase + corrigir `NetworkImage` → `CachedNetworkImage` pode reduzir **50-70% do custo de egress**.
