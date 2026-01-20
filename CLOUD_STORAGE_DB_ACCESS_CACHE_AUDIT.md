# Auditoria de acesso ao Firestore (direto vs cache) — Boora_app

Data: 19/01/2026

> Objetivo: identificar **todas as telas** (screens/widgets de UI) que fazem leitura direta do Firestore e classificar o que **deveria ser cacheado** vs o que **precisa ser direto** (tempo real/consistência forte), com recomendações práticas.

## Checklist (requisitos)
- [x] Mapear telas (screens) e widgets relevantes.
- [x] Identificar leituras diretas ao Firestore (ex.: `.get()`, `.snapshots()` e `FirebaseFirestore.instance`).
- [x] Identificar caches existentes no app (UserCacheService, GlobalCacheService, ConversationCacheService etc).
- [x] Classificar por tela: **Deveria usar cache** vs **Deve consumir direto**.
- [ ] Implementar correções (fora do escopo deste documento; pode virar PR por prioridade).

## Escopo e metodologia

### O que foi analisado
- Arquivos em `lib/**/screens/**.dart`, `lib/**/presentation/screens/**.dart` e widgets de UI.
- Padrões de acesso ao Firestore:
  - Leitura pontual: `collection(...).doc(...).get()`, `where(...).get()`.
  - Tempo real: `collection(...).snapshots()`, `doc(...).snapshots()`.

### Observação importante
Este relatório classifica **comportamento ideal** do ponto de vista de **custo/performance/UX**, mas a decisão final depende de:
- necessidade de tempo real,
- risco de inconsistência temporária,
- criticidade do dado,
- e impacto no produto.

## Inventário de cache existente (base para recomendações)

### 1) `UserCacheService` (TTL 10 min)
Arquivo: `lib/core/services/cache/user_cache_service.dart`
- Cache em memória de documentos da coleção `Users`.
- Ideal para:
  - exibir nome/foto/tipo de usuário em várias telas,
  - evitar múltiplos `Users/{id}.get()` repetidos,
  - batch fetch (`fetchUsers`) com `whereIn` (chunks de 10).

### 2) `GlobalCacheService` (TTL por key)
Arquivo: `lib/core/services/global_cache_service.dart`
- Cache em memória genérico com TTL.
- Ideal para:
  - listas (feeds) com TTL curto,
  - dados calculados/compostos,
  - resultados de queries que não precisam ser tempo real.

### 3) `ConversationCacheService`
Arquivo: `lib/features/conversations/services/conversation_cache_service.dart`
- Cache de *display data* (processamento/formatadores) para conversas.
- Observação: não substitui o Firestore; reduz reprocessamento e flicker.

### 4) `CacheManager`
Arquivo: `lib/core/services/cache/cache_manager.dart`
- Coordena caches e limpeza em foreground/logouts.

## Classificação: quando cachear vs quando ler direto

### Heurística usada (regra de bolso)
- **Deveria ser cache**:
  - perfil de usuário (nome, foto, badges),
  - detalhes de evento estáticos a médio prazo (título, capa, criador),
  - listas que podem tolerar *stale* de 2–10 minutos,
  - dados agregados/contadores que não precisam ser 100% em tempo real.

- **Deve ser direto**:
  - chat/mensagens (tempo real),
  - presença/confirm presence (tempo real ou quase real),
  - moderação/segurança (bloqueio, status banido),
  - dados que impactam transação/consistência (ex.: aplicação em evento, pagamento) — pode usar cache apenas como otimização cuidadosa.

## Auditoria por tela (screens) e widgets críticos

> Nota: muitos acessos “diretos” estão em widgets auxiliares que são usados dentro de telas. Aqui eu listo **o ponto de UI** e as operações mais relevantes.

### Web Dashboard (admin)

#### `lib/features/web_dashboard/screens/users_table_screen.dart`
- Acesso: `FirebaseFirestore.instance.collection('Users').snapshots()`
- Classificação: **Deve consumir direto** (dashboard/admin precisa refletir dados atuais; também é um ambiente de menor volume de usuários do que app mobile).
- Risco/custo: alto em coleções grandes (stream de coleção inteira). Sugestão: paginação/filtros e limites.

#### `lib/features/web_dashboard/screens/events_table_screen.dart`
- Acesso: `FirebaseFirestore.instance.collection('events').snapshots()`
- Classificação: **Deve consumir direto** (admin).
- Sugestão: paginação/filters.

#### `lib/features/web_dashboard/screens/reports_table_screen.dart`
- Acesso: `collection('reports').orderBy(...).snapshots()`
- Classificação: **Deve consumir direto** (admin/moderação).

### Profile

#### `lib/features/profile/presentation/screens/blocked_users_screen.dart`
- Acesso: `FirebaseFirestore.instance.collection('Users')...get()`
- Classificação: **Deveria usar cache (parcial)**.
  - A lista de IDs bloqueados deve vir do estado do usuário logado (provavelmente já existe localmente).
  - Para resolver detalhes (nome/foto) de cada id bloqueado, deveria usar `UserCacheService.fetchUsers([...])`.
- Problema típico: loop de N reads (um por usuário) se a tela resolver usuário a usuário.

#### `lib/features/profile/presentation/widgets/user_images_grid.dart`
- Acesso: `Users/{userId}.snapshots()`
- Classificação: **Depende**.
  - Se a galeria muda raramente: **cache** com TTL + refresh manual.
  - Se a galeria é editada frequentemente na mesma sessão: **direto**.
- Melhor prática: cache de lista de URLs (já existe uso de `GlobalCacheService` em `gallery_profile_section.dart`). Ideal é padronizar.

#### `lib/features/profile/presentation/widgets/app_section_card.dart`
- Acesso: `FirebaseFirestore.instance.collection('Users').doc(userId)...` (leituras)
- Classificação: **Deveria usar cache**.
  - Dados de seção de perfil (ex.: campos do perfil) normalmente toleram TTL ou cache local.
  - Recomendação: `UserCacheService.getOrFetchUser(userId)` para perfil e `CacheManager.invalidateUser(...)` após updates.

### Chat

#### `lib/screens/chat/widgets/chat_app_bar_widget.dart`
- Acesso: `events/{eventId}.get()`
- Classificação: **Deveria usar cache**.
  - Título/nome do evento raramente muda durante a sessão.
  - Sugestão: `GlobalCacheService` com key `event_${eventId}` (TTL 5–10 min) OU repositório de evento.

#### `lib/screens/chat/widgets/presence_drawer.dart`
- Acesso: `EventApplications...snapshots()`
- Classificação: **Deve consumir direto** (presença/participação é dado dinâmico e sensível).
- Sugestão: reduzir payload (selecionar campos, limitar, indexar) e garantir unsubscribe correto.

#### `lib/screens/chat/widgets/user_presence_status_widget.dart`
- Acesso: `events/{eventId}.snapshots()`
- Classificação: **Provavelmente direto** (status/presença pode mudar).
  - Se for apenas dados estáticos do evento, migrar para cache.

#### `lib/screens/chat/widgets/user_location_time_widget.dart`
- Acesso: `Users/{userId}.snapshots()`
- Classificação: **Direto ou híbrido**.
  - Se mostra “última localização/última atualização” em tempo real: direto.
  - Se for só campos de perfil: migrar para `UserCacheService`.

#### `lib/screens/chat/widgets/confirm_presence_widget.dart`
- Acesso: `EventApplications/{applicationId}.get()` e update
- Classificação: **Deve consumir direto**.

### Home / Discover

## 🧭 Telas principais (alto volume) — leitura por tela e decisão cache vs direto

Esta seção foca nas telas que você listou como as que mais geram leituras.

> Convenção usada:
> - **Direto (ok)**: stream/consulta necessária por tempo real/consistência.
> - **Cache (recom.)**: deveria usar `UserCacheService` ou `GlobalCacheService` (TTL) para evitar re-leituras.
> - **Híbrido**: manter direto para o “core” e cachear partes estáticas (ex.: perfil/metadata).

### 1) `discover_screen` → `lib/features/home/presentation/screens/discover_screen.dart`

**O que a tela faz**
- Renderiza `GoogleMapView` e dispara `mapViewModel.initialize()` (lazy init).

**Leituras/streams (indiretas via ViewModel/repository)**
- `MapViewModel` → `EventMapRepository.getEventsStream()`
  - Arquivo: `lib/features/home/data/repositories/event_map_repository.dart`
  - Operação: `collection('events') ... .snapshots(includeMetadataChanges: true)`
  - Observação: o repositório declara que **não aplica filtro de raio** (stream retorna “todos ativos”).

**Classificação**
- **Direto (ok), mas precisa ser enxugado**.
  - Mapa tende a ser uma experiência “ao vivo”, mas stream de “todos eventos ativos” pode ser o maior gerador de tráfego.

**Recomendação (alto impacto)**
- Transformar a descoberta do mapa em **query por viewport (bounds) + raio** (server-side) em vez de stream global.
  - Preferir:
    - query paginada/limitada por bounding box (geohash) e filtros, ou
    - refresh por evento de UI (mudança de câmera/raio) com debounce.
- Se tempo real for indispensável, usar um “direto controlado”:
  - `snapshots()` apenas para uma shortlist (ex.: eventos no viewport), não para a coleção inteira.

---

## 🖼️ Auditoria de custo de Storage (imagens) — por tela principal

> Contexto: “Storage caro” quase sempre vem de **downloads repetidos de imagens** (egress) por falta de cache em disco, URL variando (cache miss) ou UI que reconstrói e força reload.

### Regra rápida de classificação
- **OK (cache em disco)**: usa `CachedNetworkImage`/`CachedNetworkImageProvider` (normalmente via `flutter_cache_manager`) ou `StableAvatar`.
- **Risco (sem cache em disco)**: usa `Image.network`/`NetworkImage` diretamente (pode rebaixar para cache só em memória do ImageCache do Flutter, que é volátil e tende a causar redownload em listas/tabs).

### Achado crítico (alto impacto)
Arquivo: `lib/shared/stores/avatar_store.dart`
- Encontrado: `final provider = NetworkImage(imageUrl);`
- Isso é um **ponto de risco** para egress, se esse store estiver sendo usado em lists/tabs.
- Observação: o app também tem `UserStore`/`StableAvatar` que já usa `CachedNetworkImageProvider` + `AvatarImageCache` + dedupe, o que é o caminho ideal.

Recomendação:
- Evitar `AvatarStore` para produção (ou migrar internamente para `CachedNetworkImageProvider` + cacheManager), e padronizar uso de `StableAvatar`/`UserStore`.

---

### 1) `discover_screen`

**Imagens na UI**
- A tela em si não renderiza imagem diretamente, mas o mapa/markers podem usar bitmaps.

**Risco de Storage**
- Depende do que `GoogleMapView`/markers renderizam.
- Existe infraestrutura de cache para markers no repo (`flutter_cache_manager` aparece no projeto), então o risco aqui tende a ser **menor**, desde que todos os markers usem essa pipeline.

**Recomendação**
- Garantir que qualquer imagem usada para marker seja carregada via cache manager (nunca `NetworkImage` cru).

---

### 2) `action_tab` → cards (Approve/Review)

Arquivos principais:
- `lib/features/home/presentation/widgets/approve_card.dart`
- `lib/features/reviews/presentation/widgets/review_card.dart`

**Imagens na UI**
- Ambos delegam visual para `ActionCard`, passando `userId` + `userPhotoUrl`.

**Classificação (Storage)**
- **Provavelmente OK**, se `ActionCard` usar `StableAvatar` (ou `CachedNetworkImage`) para renderizar `userPhotoUrl`.

**Ponto de atenção**
- Se `ActionCard` estiver usando `NetworkImage`/`Image.network`, esta tab vira hotspot (lista com vários cards).

---

### 3) `ranking_tab` → `PeopleRankingCard`

Arquivo: `lib/features/home/presentation/widgets/people_ranking_card.dart`

**Imagens na UI**
- Usa `StableAvatar(userId: ..., size: 58, ...)`.

**Classificação (Storage)**
- **OK (cache em disco)** ✅

---

### 4) `conversation_tab`

**Imagens na UI**
- A aba em si exibe tiles de conversas; normalmente avatar.

**Classificação (Storage)**
- **Tende a ser OK** se os tiles usarem `StableAvatar`.

**Ponto de atenção**
- Conversas/chat (fora desta tab) pode exibir mídia (imagens) — mas o projeto já usa `CachedNetworkImage` em widgets de chat.

---

### 5) `simplified_notifications` → `NotificationItemWidget`

Arquivo: `lib/features/notifications/widgets/notification_item_widget.dart`

**Imagens na UI**
- Renderiza avatar com `StableAvatar(userId: senderId, ...)`.
- O payload (`n_sender_photo_link`) é ignorado intencionalmente.

**Classificação (Storage)**
- **OK (cache em disco)** ✅

---

### 6) `profile_tab`

Arquivo: `lib/features/home/presentation/screens/profile_tab.dart`

**Imagens na UI**
- Faz preload de avatar: `UserStore.instance.preloadAvatar(user.userId, user.photoUrl!)`.
- Renderiza com `StableAvatar`.

**Classificação (Storage)**
- **OK (cache em disco + warm-up + dedupe)** ✅

---

### 7) `Profile_screen` (`profile_screen_optimized.dart`)

**Imagens na UI**
- A tela usa `ProfileContentBuilderV2`/componentes do perfil; o repo contém uso de `CachedNetworkImage` em partes de galeria.

**Classificação (Storage)**
- **Provavelmente OK**, mas pode virar caro se:
  - houver grids/headers usando `NetworkImage` direto,
  - ou URLs mudarem frequentemente (cache miss).

**Recomendação**
- Padronizar tudo que for foto (avatar/galeria/capa) em `CachedNetworkImage`/`StableAvatar` e garantir cacheKey estável.

---

### 8) Fluxo do `create_drawer.dart`

Arquivo: `lib/features/home/presentation/widgets/create_drawer.dart`

**Imagens na UI**
- Não renderiza imagens remotas.

**Classificação (Storage)**
- **Sem impacto direto de egress nesta etapa** ✅

### 2) `action_tab` → `lib/features/home/presentation/screens/actions_tab.dart`

**Leituras/streams**
- `PendingApplicationsRepository.getPendingApplicationsStream()`
  - Arquivo: `lib/features/home/data/repositories/pending_applications_repository.dart`
  - Streams:
    - `collection('events').where(createdBy == me) ... .snapshots()`
    - `collection('EventApplications').where(eventId in [...]) ... .snapshots()`
  - Leitura pontual adicional (por snapshot de aplicações):
    - `collection('Users').where(documentId in userIds).get()`
- `ReviewRepository.getPendingReviewsStream()`
  - Arquivo: `lib/features/reviews/data/repositories/review_repository.dart`
  - Stream:
    - `collection('PendingReviews') ... .snapshots()`
  - Enriquecimento: busca dados/owners por evento (depende de `_actionsRepo.getMultipleEventOwnersData(eventIds)`).

**Classificação**
- **Direto (ok)** para pendências: ações precisam refletir rápido (aprovação/review expira, etc.).
- **Cache (recom.)** para enriquecimento de usuários.
  - Hoje o repo faz `Users whereIn ... get()` a cada update do stream de aplicações.

**Recomendação**
- Trocar enriquecimento `Users whereIn ... get()` por `UserCacheService.fetchUsers(userIds)` (TTL 10 min).
  - Mantém o stream de `EventApplications` direto, mas reduz o custo de “join” com Users.
- Se a lista de pendências não precisa ser 100% em tempo real, adicionar debounce/throttle no stream (ex.: aguardar 300–800ms antes de recompor UI quando receber bursts).

---

### 3) `ranking_tab` → `lib/features/home/presentation/screens/ranking_tab.dart`

**Leituras/streams (via ViewModel/service)**
- `PeopleRankingViewModel` usa `GlobalCacheService`.
  - TTL atual: 10 minutos (cache key por filtros state/city).
- `PeopleRankingService.getPeopleRanking()`
  - Arquivo: `lib/features/home/data/services/people_ranking_service.dart`
  - Leituras pontuais pesadas:
    - `collection('Reviews').orderBy(...).limit(500).get()`
    - depois cruza com `collection('Users') ... .get()` (whereIn por chunks)

**Classificação**
- **Cache (já implementado na UI/VM)** ✅
- **Direto (evitar)** para o service: a forma de calcular ranking (varrendo Reviews + join com Users) é cara e escala mal.

**Recomendação (alto impacto)**
- Migrar ranking para **dados agregados**:
  - Cloud Function (ou backend) que mantém coleção `UserRanking`/`RankingPeople` pré-calculada.
  - A tela passa a fazer 1 query simples (com filtros) + cache TTL.
- Enquanto não migrar:
  - reduzir `limit(500)` dinamicamente,
  - armazenar resultado agregado em cache e persistir (ex.: cache local/hive) para não recalcular em cold start.

---

### 4) `conversation_tab` → `lib/features/conversations/ui/conversations_tab.dart`

**Leituras/streams**
- `ConversationsViewModel._initFirestoreStream()`
  - Arquivo: `lib/features/conversations/state/conversations_viewmodel.dart`
  - Stream:
    - `Connections/{userId}/Conversations` ordered by `timestamp` limit 50 `.snapshots()`
- Paginação:
  - Arquivo: `lib/features/conversations/widgets/conversation_stream_widget.dart`
  - Leitura pontual:
    - `Connections/{userId}/Conversations ... startAfterDocument ... .get()`

**Classificação**
- **Direto (ok)**.
  - Conversas/unread/última mensagem normalmente precisa ser reativo.

**Ponto de atenção**
- No `_handleFirestoreSnapshot`, há:
  - `_cacheService.clearAll();` “para garantir dados em tempo real”.
  - Se esse `_cacheService` for `ConversationCacheService`, tudo bem. Se for `GlobalCacheService`, isso pode piorar leituras em outros lugares.
  - Recom.: limpar apenas o que é da aba de conversas, não um cache global.

---

### 5) `simplified_notifications` → `lib/features/notifications/widgets/simplified_notification_screen.dart`

**Leituras/streams**
- A view usa `SimplifiedNotificationController` (singleton).
- Controller usa `NotificationsRepository.getNotificationsPaginated()` (paginação) e também expõe stream no repo.
  - Arquivo: `lib/features/notifications/repositories/notifications_repository.dart`
  - Leitura pontual (paginada): collection raiz `Notifications` filtrando por `userId` e filtro por tipo.
- Controller já usa `GlobalCacheService` por filtro:
  - cache key: `CacheKeys.notificationsFilter(filterKey)`
  - faz cache hit + `_silentRefresh()`.

**Classificação**
- **Híbrido** ✅
  - Paginação direta é correta.
  - Cache TTL por filtro é correto para reduzir “voltar na tela = refazer primeira página”.

**Recomendação**
- Garantir TTL curto (ex.: 1–3 min) para “All” e um pouco maior para filtros específicos, se necessário.
- Se o volume for muito alto, adicionar `limit` menor na primeira página (ex.: 10) e carregar progressivamente.

---

### 6) `profile_tab` → `lib/features/home/presentation/screens/profile_tab.dart`

**Leituras/streams**
- `ProfileTabViewModel` (arquivo `lib/features/profile/presentation/viewmodels/profile_tab_view_model.dart`) não faz Firestore direto; consome `AppState.currentUser`.

**Classificação**
- **Cache/local (ok)** ✅

**Risco**
- Se `AppState.currentUser` estiver sendo atualizado via streams em outros lugares, o custo pode estar “fora” da tab.

---

### 7) `Profile_screen` → `lib/features/profile/presentation/screens/profile_screen_optimized.dart`

**Leituras/streams (via `ProfileController`)**
- `Users/{targetUserId}.snapshots()`
- `Reviews` do usuário:
  - `collection('Reviews').where(reviewee_id == targetUserId).orderBy(created_at).limit(50).snapshots()`
- Side-effect:
  - `registerVisit()` → `ProfileVisitsService.instance.recordVisit(...)` (provável write)

**Classificação**
- **Híbrido**
  - **Direto (ok)** para:
    - tela de perfil de terceiros (mudanças de estado, bloqueio, updates de avatar, reviews chegando).
  - **Cache (recom.)** para:
    - `Users/{id}` quando for apenas nome/foto/etc. (principalmente quando navega repetidamente em perfis).

**Recomendação (prática e segura)**
- Trocar `Users/{id}.snapshots()` por **fetch inicial via `UserCacheService.getOrFetchUser()`** + refresh manual/pull-to-refresh.
  - Para “meu perfil” (onde o usuário edita coisas), dá para manter stream, mas com debounce e escopo bem definido.
- Para reviews:
  - em vez de stream de 50 docs, considerar paginação (`get` + load more) e refresh manual.
  - se precisa de tempo real, limitar a 10–20 e carregar histórico sob demanda.

---

### 8) Fluxo do `create_drawer.dart` → `lib/features/home/presentation/widgets/create_drawer.dart`

**Leituras/streams**
- No arquivo do drawer em si: **nenhuma leitura Firestore**.
- O impacto de custo está mais adiante no fluxo (coordinator / criação do evento / upload / gravação em `events`, possivelmente `EventApplications`).

**Classificação**
- **Sem leituras diretas nesta etapa** ✅

**Próximo ponto para auditar (onde costuma ter custo)**
- `CreateFlowCoordinator` e os passos que persistem draft → Firestore.
  - Objetivo: garantir que não há reads redundantes (ex.: reconsultar usuário/evento a cada step) e que uploads (imagens) são deduplicados.

#### `lib/features/home/presentation/widgets/referral_debug_screen.dart`
- Acesso: `Users/{userId}.get()` e `ReferralInstalls...get()`
- Classificação: **Pode ser cache** (é debug/admin-like, não precisa ser real-time).

#### `lib/features/home/presentation/widgets/invite_drawer.dart`
- Acesso: `Users/{uid}.get()` e `ReferralInstalls...get()` e `Users/{invitedUserId}.get()`
- Classificação: **Deveria usar cache (forte)**.
  - Vários reads repetitivos de `Users`.
  - Recomendação: `UserCacheService` para todos esses userIds.
  - Para `ReferralInstalls`: `GlobalCacheService` com TTL curto (ex.: 5 min).

#### `lib/features/home/presentation/widgets/event_card/widgets/participants_counter.dart`
- Acesso: `EventApplications ... snapshots()` (contador)
- Classificação: **Híbrido (preferencialmente cache/derivado)**.
  - Em card de feed, stream por card costuma ser caro.
  - Melhor: gravar contador agregado no doc do evento (ou coleção de stats) e atualizar via Cloud Function / transação.
  - Alternativa: cache local por TTL e atualizar em background.

## Lacunas encontradas (alto impacto)

1) **Muitos acessos a `Users/{id}` ainda são diretos** em widgets e drawers.
   - Existe `UserCacheService`, mas não está sendo usado consistentemente.

2) **Streams em feed/cards** (ex.: contadores por evento) podem multiplicar consumo.
   - Ideal: desnormalização controlada (contador no doc do evento) + TTL.

3) **Admins/dashboard**: streams em coleções inteiras.
   - Pode ser aceitável para web dashboard, mas precisa paginação para escala.

## Recomendações padronizadas (contrato de dados)

### Para perfis de usuário (`Users/{id}`)
- Sempre acessar via `UserCacheService.getOrFetchUser(userId)`.
- Após update de perfil/foto: `CacheManager.instance.invalidateUser(userId)`.

### Para detalhes de evento (`events/{id}`)
- Criar `EventCacheService` (ou usar `GlobalCacheService` com TTL curto).
- Widgets como app bar do chat devem usar cache.

### Para contadores (participantes, likes, etc.)
- Evitar `snapshots()` por card.
- Preferir:
  - campo agregado no doc do evento
  - + atualização via Cloud Function
  - + fallback com TTL.

## Próximos passos (para virar ação)
1) Prioridade 1: substituir reads diretas de `Users` (invite drawer, blocked users, widgets de perfil) por `UserCacheService`.
2) Prioridade 2: revisar streams em cards (participants counter) e migrar para agregados.
3) Prioridade 3: revisar chat app bar (cache de evento).

---

## Apêndice: arquivos com acesso direto detectado (amostra relevante)
- `lib/features/profile/presentation/screens/blocked_users_screen.dart`
- `lib/screens/chat/widgets/chat_app_bar_widget.dart`
- `lib/screens/chat/widgets/presence_drawer.dart`
- `lib/screens/chat/widgets/user_location_time_widget.dart`
- `lib/features/home/presentation/widgets/invite_drawer.dart`
- `lib/features/home/presentation/widgets/referral_debug_screen.dart`
- `lib/features/home/presentation/widgets/event_card/widgets/participants_counter.dart`
- `lib/features/web_dashboard/screens/users_table_screen.dart`
- `lib/features/web_dashboard/screens/events_table_screen.dart`
- `lib/features/web_dashboard/screens/reports_table_screen.dart`
