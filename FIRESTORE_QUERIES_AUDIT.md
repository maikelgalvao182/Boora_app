# Auditoria de Queries Firestore

Data: 02/02/2026

## Escopo analisado
Arquivos:
- lib/features/home/data/services/map_discovery_service.dart
- lib/core/services/user_status_service.dart
- lib/services/location/radius_controller.dart
- lib/services/location/advanced_filters_controller.dart
- lib/services/location/location_query_service.dart
- lib/screens/chat/chat_screen_refactored.dart
- lib/screens/chat/widgets/chat_app_bar_widget.dart
- lib/screens/chat/controllers/chat_app_bar_controller.dart
- lib/screens/chat/widgets/presence_drawer.dart
- lib/screens/chat/widgets/user_presence_status_widget.dart
- lib/screens/chat/widgets/user_location_time_widget.dart
- lib/screens/chat/widgets/confirm_presence_widget.dart
- lib/screens/chat/services/chat_service.dart
- lib/screens/chat/services/fee_auto_heal_service.dart
- lib/common/services/notifications_counter_service.dart
- lib/features/home/data/repositories/pending_applications_repository.dart
- lib/features/reviews/data/repositories/review_repository.dart
- lib/shared/repositories/user_repository.dart
- lib/screens/chat/widgets/chat_avatar_widget.dart
- lib/screens/chat/widgets/event_name_text.dart
- lib/screens/chat/widgets/event_info_row.dart

---

# Questionário por feature/query

## Feature/Tela: Mapa de eventos (Discovery)

### Query 1 — Buscar eventos por bounding box
0) Identificação
- Feature / Tela: Mapa (Discover)
- Arquivo(s) / caminho(s): lib/features/home/data/services/map_discovery_service.dart
- Função/método onde a query nasce: `_queryFirestore()`
- Tipo de operação: (x) get ( ) stream/onSnapshot ( ) aggregate/count ( ) transaction/batch
- Coleção alvo: `events`
- Ambiente: (x) todos

1) Gatilho e frequência
- O que dispara a query? ( ) initState / onAppear ( ) build / widget rebuild ( ) onScroll ( ) pull-to-refresh (x) onCameraMove / onCameraIdle ( ) onChanged (busca digitando) ( ) timer/polling ( ) listener de auth/session (x) outro: `loadEventsInBounds()`
- Com que frequência ela pode rodar no pior caso? (x) a cada interação (move/pan/zoom)
- Tem debounce/throttle? (x) Sim → 600ms
- Tem dedupe? (x) Sim → cache em memória/Hive + seq de requests
- Tem cancelamento de requisições em voo? ( ) Sim (x) Não → usa “ignore result” via requestSeq

2) Escopo e volume
- A query usa limit()? (x) Sim → 1500
- Tem paginação? ( ) Sim (x) Não
- Qual o tamanho esperado do resultado? ( ) 1–10 docs ( ) 10–50 ( ) 50–200 (x) 200+
- A coleção é grande? (x) 100k–1M (estimado) / ( ) N/D
- Existe filtro forte? (x) Sim → `isActive == true` + range de latitude
- ⚠️ Observação: range por latitude pode trazer muitos docs e filtra longitude no client.

3) Forma da query
- wheres: `isActive == true`, `location.latitude >= minLat`, `location.latitude <= maxLat`
- orderBy? ( ) Sim (x) Não
- Índice composto? (x) Sim (provável para isActive + latitude)
- Já teve erro de índice? N/D
- Range em quantos campos? (x) 1
- in / array-contains-any? ( ) Sim (x) Não

4) Real-time (streams/listeners)
- É stream/onSnapshot? ( ) Sim (x) Não

5) Repetição e N+1
- N+1? ( ) Sim (x) Não

6) Cache e persistência
- Cache em memória? (x) Sim → TTL 90s
- Cache persistente? (x) Sim → Hive TTL 2–10 min
- Offline persistence Firestore: N/D

7) Segurança e custo indireto
- Permissão de ler mais do que deveria? N/D
- Risco de scraping? N/D
- Rate limit/back-end gate? (x) Sim → cache + debounce

---

## Feature/Tela: Status de usuários

### Query 1 — Buscar status de um usuário
0) Identificação
- Feature / Tela: Status usuário (anti-inativo)
- Arquivo(s): lib/core/services/user_status_service.dart
- Função/método: `fetchUserStatus()`
- Tipo de operação: (x) get
- Coleção alvo: `users_preview`
- Ambiente: (x) todos

1) Gatilho e frequência
- Disparo: (x) outro: `isUserActive()` / `isUserInactive()`
- Frequência: ( ) 1x por abertura (x) múltiplas vezes por minuto (dependente de uso)
- Debounce: ( ) Sim (x) Não
- Dedupe: (x) Sim → cache TTL 5 min
- Cancelamento: ( ) Sim (x) Não

2) Escopo e volume
- limit: ( ) Sim (x) Não
- Paginação: ( ) Sim (x) Não
- Tamanho esperado: (x) 1–10 docs
- Coleção grande: (x) 100k–1M (estimado)
- Filtro forte: (x) Sim → docId

3) Forma da query
- wheres: docId
- orderBy: Não
- Range: 0
- in/array-contains-any: Não

4) Real-time
- Stream? Não

6) Cache
- Memória: Sim (TTL 5 min)

### Query 2 — Buscar status em batch (whereIn)
0) Identificação
- Função/método: `fetchUsersStatus()`
- Tipo: (x) get
- Coleção: `users_preview`

1) Gatilho e frequência
- Disparo: (x) outro: chamada por lista de usuários
- Frequência: N/D
- Debounce: ( ) Sim (x) Não
- Dedupe: (x) Sim → cache TTL

2) Escopo e volume
- limit: ( ) Sim (x) Não (whereIn <= 10 por chunk)
- Tamanho esperado: 1–10 docs por chunk
- Filtro forte: (x) Sim → docId in [<=10]

3) Forma da query
- wheres: `documentId in [...]`
- in/array-contains-any: (x) Sim → até 10

---

## Feature/Tela: Ajuste de Raio

### Query 1 — Carregar raio do usuário
0) Identificação
- Arquivo(s): lib/services/location/radius_controller.dart
- Função: `loadFromFirestore()`
- Tipo: (x) get
- Coleção: `Users`

1) Gatilho e frequência
- Disparo: (x) initState / onAppear (telas de filtro)
- Frequência: 1x por abertura
- Debounce: N/A
- Dedupe: (x) Sim → cache local (UserPreferencesCacheRepository)

2) Escopo
- limit: N/A
- Tamanho esperado: 1 doc

### Query 2 — Salvar raio (debounced)
0) Identificação
- Função: `_saveToFirestore()`
- Tipo: (x) update
- Coleção: `Users`

1) Gatilho e frequência
- Disparo: (x) onChanged (slider)
- Frequência: a cada interação (com debounce 500ms)
- Debounce: (x) Sim → 500ms
- Dedupe: (x) Sim → `_isUpdating`

---

## Feature/Tela: Filtros Avançados

### Query 1 — Carregar filtros
0) Identificação
- Arquivo(s): lib/services/location/advanced_filters_controller.dart
- Função: `loadFromFirestore()`
- Tipo: (x) get
- Coleção: `Users`

1) Gatilho e frequência
- Disparo: initState/onAppear
- Frequência: 1x por abertura

### Query 2 — Salvar filtros
0) Identificação
- Função: `saveToFirestore()`
- Tipo: (x) update
- Coleção: `Users`

1) Gatilho e frequência
- Disparo: botão “Salvar”
- Frequência: eventual

### Query 3 — Verificar documento salvo
- Função: `saveToFirestore()` → `verifyDoc = userRef.get()`
- Tipo: (x) get
- Coleção: `Users`

### Query 4 — Adicionar interesse / Remover interesse
- Função: `addInterest()` / `removeInterest()`
- Tipo: (x) update
- Coleção: `Users`
- Disparo: onChanged / tap (pode ser frequente)
- Debounce: ( ) Sim (x) Não

### Query 5 — Limpar filtros
- Função: `clearAllFilters()`
- Tipo: (x) update
- Coleção: `Users`

---

## Feature/Tela: Pessoas próximas (LocationQueryService)

### Query 1 — Localização privada do usuário
0) Identificação
- Arquivo(s): lib/services/location/location_query_service.dart
- Função: `_getUserLocation()`
- Tipo: (x) get
- Coleção: `Users/{userId}/private/location`

1) Gatilho e frequência
- Disparo: (x) initState / onAppear (find_people_screen) / reload
- Frequência: múltiplas vezes por minuto (cache TTL 30s)
- Dedupe: (x) Sim → cache TTL 30s

### Query 2 — Fallback de localização (doc Users)
- Função: `_getUserLocation()` fallback
- Tipo: (x) get
- Coleção: `Users`

### Query 3 — Obter raio do usuário
- Função: `_getUserRadius()`
- Tipo: (x) get
- Coleção: `Users`

### Query 4 — Inicializar localização
- Função: `initializeUserLocation()`
- Tipo: (x) set (merge)
- Coleção: `Users`

---

## Feature/Tela: Chat (tela principal)

### Query 1 — Carregar metadata da conversa (get único)
0) Identificação
- Arquivo(s): lib/screens/chat/chat_screen_refactored.dart
- Função: `_loadConversationData()` → `ChatService.getConversationOnce()`
- Tipo: (x) get
- Coleção alvo: `Connections/{currentUserId}/Conversations/{conversationId}`

1) Gatilho e frequência
- Disparo: (x) initState
- Frequência: 1x por abertura

### Query 2 — Buscar applicationId do usuário no evento
0) Identificação
- Função: `_loadApplicationId()`
- Tipo: (x) get
- Coleção: `EventApplications`

1) Forma da query
- wheres: `eventId ==`, `userId ==`
- limit: 1

---

## Feature/Tela: Chat App Bar / Informações de evento

### Query 1 — Buscar nome do evento antes de excluir
0) Identificação
- Arquivo(s): lib/screens/chat/widgets/chat_app_bar_widget.dart
- Função: `_handleDeleteEvent()`
- Tipo: (x) get
- Coleção: `events`

### Query 2 — Verificar criador do evento
0) Identificação
- Arquivo(s): lib/screens/chat/controllers/chat_app_bar_controller.dart
- Função: `isEventCreator()`
- Tipo: (x) get
- Coleção: `events`
- Dedupe: (x) Sim → cache interno

### Query 3 — Stream do resumo de conversa (AppBar)
0) Identificação
- Arquivo(s):
  - lib/screens/chat/widgets/chat_avatar_widget.dart
  - lib/screens/chat/widgets/event_name_text.dart
  - lib/screens/chat/widgets/event_info_row.dart
- Função: `chatService.getConversationSummary()` → stream
- Tipo: ( ) get (x) stream/onSnapshot
- Coleção: `Connections/{currentUserId}/Conversations/{conversationId}`

1) Gatilho e frequência
- Disparo: (x) build / widget rebuild (StreamBuilder)
- Frequência: contínua (stream)
- Debounce: ( ) Sim (x) Não
- ⚠️ Red flag: stream em widgets da AppBar para dados pouco críticos.

---

## Feature/Tela: Presença em evento

### Query 1 — Carregar participantes confirmados
0) Identificação
- Arquivo(s): lib/screens/chat/widgets/presence_drawer.dart
- Função: `_loadParticipants()`
- Tipo: (x) get
- Coleção: `EventApplications`
- wheres: `eventId ==`, `status in ['approved','autoApproved']`

1) Gatilho e frequência
- Disparo: initState
- Frequência: 1x por abertura
- in/array-contains-any: (x) Sim → 2 itens

### Query 2 — Carregar presença atual
0) Identificação
- Arquivo(s): lib/screens/chat/widgets/confirm_presence_widget.dart
- Função: `_loadCurrentPresence()`
- Tipo: (x) get
- Coleção: `EventApplications/{applicationId}`

### Query 3 — Atualizar presença
- Função: `_updatePresence()`
- Tipo: (x) update
- Coleção: `EventApplications/{applicationId}`

---

## Feature/Tela: Presença do usuário (Chat)

### Query 1 — Presença por polling (get)
0) Identificação
- Arquivo(s): lib/screens/chat/widgets/user_presence_status_widget.dart
- Função: `_loadPresence()` → `ChatService.getUserOnce()`
- Tipo: (x) get
- Coleção: `Users/{userId}`

1) Gatilho e frequência
- Disparo: initState + timer
- Frequência: 1x por minuto
- Cache: (x) Sim → TTL 60s

### Query 2 — Stream do evento (activityText)
0) Identificação
- Arquivo(s): lib/screens/chat/widgets/user_presence_status_widget.dart
- Função: StreamBuilder
- Tipo: (x) stream/onSnapshot
- Coleção: `events/{eventId}`

---

## Feature/Tela: Localização e last message (Chat App Bar)

### Query 1 — Stream de dados do usuário
0) Identificação
- Arquivo(s): lib/screens/chat/widgets/user_location_time_widget.dart
- Tipo: (x) stream/onSnapshot
- Coleção: `Users` (where `userId ==`, limit 1)

1) Gatilho e frequência
- Disparo: build / StreamBuilder
- Frequência: contínua
- ⚠️ Red flag: stream para dados pouco voláteis (locality/state)

### Query 2 — Stream de resumo da conversa
0) Identificação
- Função: `chatService.getConversationSummary()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Connections/{currentUserId}/Conversations/{conversationId}`

---

## Feature/Tela: Notificações e badges

### Query 1 — Stream de conversas (unread)
0) Identificação
- Arquivo(s): lib/common/services/notifications_counter_service.dart
- Função: `_listenToUnreadConversations()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Connections/{currentUserId}/Conversations`

### Query 2 — Stream de notificações não lidas
0) Identificação
- Função: `_listenToUnreadNotifications()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Notifications`
- wheres: `n_receiver_id == currentUserId`, `n_read == false`

---

## Feature/Tela: Pending Applications (Actions)

### Query 1 — Eventos do usuário (stream)
0) Identificação
- Arquivo(s): lib/features/home/data/repositories/pending_applications_repository.dart
- Função: `getPendingApplicationsStream()`
- Tipo: (x) stream/onSnapshot
- Coleção: `events`
- wheres: `createdBy == userId`, `isActive == true`, `isCanceled == false`
- limit: Não

### Query 2 — Applications pendentes (stream)
- Coleção: `EventApplications`
- wheres: `eventId in [<=10]`, `status == pending`
- ⚠️ Red flag: uso de whereIn + stream pode escalar com frequência.

### Query 3 — Enriquecer usuários (get)
- Coleção: `Users`
- where: `documentId in userIds`
- Tipo: (x) get
- ⚠️ Red flag: padrão N+1 (para cada snapshot, faz get de usuários).

---

## Feature/Tela: Reviews

### Query 1 — Pending reviews (get)
0) Identificação
- Arquivo(s): lib/features/reviews/data/repositories/review_repository.dart
- Função: `getPendingReviews()`
- Tipo: (x) get
- Coleção: `PendingReviews`
- wheres: `reviewer_id ==`, `dismissed == false`, `expires_at > now`
- orderBy: `expires_at`, `created_at desc`
- limit: 20

### Query 2 — Pending reviews (stream)
- Função: `getPendingReviewsStream()` / `watchPendingReviews()`
- Tipo: (x) stream/onSnapshot
- Coleção: `PendingReviews`
- orderBy + limit 20
- ⚠️ Red flag: `watchPendingReviews()` faz query extra em `Reviews` para cada doc (N+1).

### Query 3 — Contagem de pending reviews (get)
- Função: `getPendingReviewsCount()`
- Tipo: (x) get
- Coleção: `PendingReviews`

### Query 4 — Atualizações de pending review
- Funções: `dismissPendingReview()`, `updatePendingReview()`
- Tipo: (x) update
- Coleção: `PendingReviews`

### Query 5 — ConfirmedParticipants (write)
- Funções: `saveConfirmedParticipant()`, `markParticipantAsReviewed()`
- Tipo: (x) set / update
- Coleção: `events/{eventId}/ConfirmedParticipants/{participantId}`

### Query 6 — Criar PendingReview (write)
- Função: `createParticipantPendingReview()`
- Tipo: (x) set
- Coleção: `PendingReviews/{pendingReviewId}`

### Query 7 — Remover PendingReview (delete)
- Funções: `deletePendingReview()`, `_removePendingReview()` / `_removePendingReviewById()`
- Tipo: (x) delete / get+delete

### Query 8 — Criar review (duplicata + user data + add)
- Função: `createReview()`
- Tipo: (x) get + (x) add
- Coleções:
  - `Reviews` (where reviewer_id, reviewee_id, event_id, limit 1)
  - `Users/{userId}` (get)
  - `Reviews` (add)

### Query 9 — Listar reviews do usuário (get)
- Função: `getUserReviews()`
- Tipo: (x) get
- Coleção: `Reviews`
- where: `reviewee_id == userId`
- orderBy: `created_at desc`
- limit: variável (+ `startAfterDocument` para paginação)

### Query 10 — Estatísticas (get)
- Função: `getReviewStats()`
- Tipo: (x) get
- Coleção: `Reviews`
- where: `reviewee_id == userId`

### Query 11 — Stream de reviews
- Funções: `watchUserReviews()` / `watchUserStats()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Reviews`
- where: `reviewee_id == userId`, orderBy `created_at desc`

---

## Feature/Tela: User Repository (usuários)

### Query 1 — Buscar usuário por ID
0) Identificação
- Arquivo(s): lib/shared/repositories/user_repository.dart
- Função: `getUserById()`
- Tipo: (x) get
- Coleção: `Users`

### Query 2 — Buscar usuários por IDs (batch)
- Função: `getUsersByIds()`
- Tipo: (x) get
- Coleções: `users_preview` (where docId in chunk), `Users` (where docId in missingIds)
- in/array-contains-any: (x) Sim → até 10

### Query 3 — Buscar info básica
- Função: `getUserBasicInfo()`
- Tipo: (x) get
- Coleções: `users_preview` doc, fallback `Users` doc

### Query 4 — Stream do usuário
- Função: `watchUser()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Users/{userId}`

### Query 5 — Atualizar/criar usuário
- Funções: `updateUser()` / `createUser()`
- Tipo: (x) update / set
- Coleção: `Users/{userId}`

### Query 6 — Verificar existência
- Função: `userExists()`
- Tipo: (x) get
- Coleção: `Users/{userId}`

### Query 7 — Usuário mais recente
- Função: `getMostRecentUser()`
- Tipo: (x) get
- Coleção: `Users` (orderBy createdAt desc, limit 1)

### Query 8 — Dados do usuário atual (cache)
- Função: `getCurrentUserData()`
- Tipo: (x) get
- Coleção: `Users/{currentUserId}`

---

## Feature/Tela: Auto-heal de fee

### Query 1 — Buscar WeddingAnnouncement
0) Identificação
- Arquivo(s): lib/screens/chat/services/fee_auto_heal_service.dart
- Função: `_calculateFee()`
- Tipo: (x) get
- Coleção: `WeddingAnnouncements/{announcementId}`

### Query 2 — Aplicar fee_lock nas conversas
- Função: `_applyFeeLock()`
- Tipo: (x) set (merge)
- Coleção: `Connections/{userId}/Conversations/{otherUserId}` (2 docs)
- ⚠️ Red flag: Future.wait em duas gravações (ok, mas atenção em falhas parciais)

---

## Observações gerais (red flags)
- Streams em widgets de AppBar para dados pouco críticos (ex.: resumo de conversa e localização) podem gerar custo alto.
- `UserLocationTimeWidget` usa stream + filtro `where('userId')` em vez de doc direto — potencialmente mais caro.
- `PendingApplicationsRepository` faz `get` de usuários a cada snapshot (padrão N+1).
- `watchPendingReviews()` faz uma query extra em `Reviews` para cada doc de pending review (N+1).
- `MapDiscoveryService` usa limite alto (1500) e range por latitude com filtragem de longitude no client.

---

## Pendências / Itens para validação manual
- Tamanho real das coleções (events, Users, Reviews, PendingReviews).
- Índices compostos necessários (especialmente em `events`, `PendingReviews`, `Reviews`).
- Necessidade real de streams em AppBar/Chat (reduzir para get + polling se possível).

---

# Aprofundamento — queries adicionais (app)

## Feature/Tela: Deleção de eventos (admin/owner)

### Query 1 — Buscar aplicações do evento
0) Identificação
- Feature / Tela: Deletar evento
- Arquivo(s): lib/screens/chat/services/event_deletion_service.dart
- Função/método: `deleteEvent()`
- Tipo de operação: (x) get
- Coleção alvo: `EventApplications`
- Ambiente: (x) todos

1) Gatilho e frequência
- Disparo: ação explícita do usuário (delete)
- Frequência: eventual

2) Escopo e volume
- limit: ( ) Sim (x) Não
- Resultado esperado: 10–200+ (depende do evento)
- Filtro forte: (x) Sim → `eventId ==`

3) Forma da query
- wheres: `eventId ==`
- orderBy: Não
- Range: 0

4) Real-time
- Stream? Não

### Query 2 — Deletar mensagens do EventChat
0) Identificação
- Função: `deleteEvent()`
- Tipo: (x) get + (x) delete (loop)
- Coleção: `EventChats/{eventId}/Messages`

1) Gatilho
- Disparo: delete event
- Frequência: eventual

2) Escopo
- Sem limit (varre toda subcoleção)
- ⚠️ Red flag: deleção item a item pode ser lenta em chats grandes.

### Query 3 — Deletar conversas, aplicações e evento (batch)
0) Identificação
- Função: `deleteEvent()`
- Tipo: (x) batch delete
- Coleções:
  - `Connections/{participantId}/Conversations/event_{eventId}`
  - `EventApplications/{docId}`
  - `events/{eventId}`

### Query 4 — Limpeza de notificações do evento
0) Identificação
- Função: `_deleteEventNotifications()`
- Tipo: (x) get + (x) batch delete
- Coleção: `Notifications`
- wheres: `eventId ==` OR `n_params.activityId ==` OR `n_related_id ==`

1) Escopo
- Possível volume alto (notificações históricas)
- ⚠️ Red flag: 3 queries + batch delete em loop.

---

## Feature/Tela: Remoção de aplicação (WeddingAnnouncements)

### Query 1 — Buscar anúncios do usuário (bride)
0) Identificação
- Arquivo(s): lib/screens/chat/services/application_removal_service.dart
- Função: `_getCandidateApplications()`
- Tipo: (x) get
- Coleção: `WeddingAnnouncements`
- wheres: `brideId ==` ou `bride_id ==`

### Query 2 — Buscar anúncios com aplicações (vendor)
0) Identificação
- Função: `_getCandidateApplications()`
- Tipo: (x) get
- Coleção: `WeddingAnnouncements`
- wheres: `applications != null`

2) Escopo
- ⚠️ Red flag: `applications != null` pode ler muitos docs.

### Query 3 — Remover aplicação (arrayRemove)
0) Identificação
- Função: `_rejectCandidate()`
- Tipo: (x) update
- Coleção: `WeddingAnnouncements/{id}`

---

## Feature/Tela: Remover aplicação em evento (EventApplications)

### Query 1 — Buscar aplicação do usuário
0) Identificação
- Arquivo(s): lib/screens/chat/services/event_application_removal_service.dart
- Função: `handleRemoveUserApplication()` / `handleLeaveEvent()`
- Tipo: (x) get
- Coleção: `EventApplications`
- wheres: `eventId ==`, `userId ==`, limit 1

### Query 2 — Buscar evento
0) Identificação
- Função: `handleRemoveUserApplication()` / `handleLeaveEvent()`
- Tipo: (x) get
- Coleção: `events/{eventId}`

---

## Feature/Tela: User Store e Avatar Store (realtime)

### Query 1 — Users Preview (get único)
0) Identificação
- Arquivo(s): lib/shared/stores/user_store.dart
- Função: `_performFetch()`
- Tipo: (x) get
- Coleção: `users_preview/{userId}`

### Query 2 — Users Preview (stream)
0) Identificação
- Função: `_startPreviewListener()`
- Tipo: (x) stream/onSnapshot
- Coleção: `users_preview/{userId}`
- Frequência: contínua

### Query 3 — Users completo (stream)
0) Identificação
- Função: `_startFullListener()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Users/{userId}`

### Query 4 — Avatar realtime
0) Identificação
- Arquivo(s): lib/shared/stores/avatar_store.dart
- Função: `_loadAvatar()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Users/{userId}`
- ⚠️ Red flag: listener por usuário para avatar (pode escalar em listas).

---

## Feature/Tela: UserDataService (ratings)

### Query 1 — Ratings de usuário
0) Identificação
- Arquivo(s): lib/shared/services/user_data_service.dart
- Função: `getRatingByUserId()`
- Tipo: (x) get
- Coleção: `Reviews`
- where: `reviewee_id == userId`

### Query 2 — Ratings em batch (whereIn)
0) Identificação
- Função: `getRatingsByUserIds()`
- Tipo: (x) get
- Coleção: `Reviews`
- where: `reviewee_id in [<=10]`
- ⚠️ Red flag: N+1 se usado repetidamente sem cache.

---

## Feature/Tela: Denúncia de evento

### Query 1 — Buscar dados do evento
0) Identificação
- Arquivo(s): lib/shared/widgets/report_event_button.dart
- Função: `_submitReport()`
- Tipo: (x) get
- Coleção: `events/{eventId}`

### Query 2 — Criar report
0) Identificação
- Função: `_submitReport()`
- Tipo: (x) add
- Coleção: `reports`

---

## Feature/Tela: Reviews (listener + batch)

### Query 1 — Listener realtime de PendingReviews
0) Identificação
- Arquivo(s): lib/features/reviews/presentation/services/pending_reviews_listener_service.dart
- Função: `startListening()`
- Tipo: (x) stream/onSnapshot
- Coleção: `PendingReviews`
- wheres: `reviewer_id == userId`, `dismissed == false`, orderBy `created_at desc`

### Query 2 — Batch de reviews
0) Identificação
- Arquivo(s): lib/features/reviews/presentation/dialogs/controller/review_batch_service.dart
- Funções: `createReviewBatch()`, `createPendingReviewBatch()`
- Tipo: (x) batch set
- Coleções: `Reviews`, `PendingReviews`

### Query 3 — ConfirmedParticipants (batch)
0) Identificação
- Função: `markParticipantReviewedBatch()`
- Tipo: (x) batch set
- Coleção: `Events/{eventId}/ConfirmedParticipants/{participantId}`

### Query 4 — Buscar dados do owner
0) Identificação
- Função: `prepareOwnerData()`
- Tipo: (x) get
- Coleção: `Users/{reviewerId}`

---

## Feature/Tela: Actions Repository (enriquecimento)

### Query 1 — Buscar owner do evento
0) Identificação
- Arquivo(s): lib/features/reviews/data/repositories/actions_repository.dart
- Função: `getEventOwnerData()`
- Tipo: (x) get
- Coleção: `events/{eventId}` + `users_preview/Users` via UserRepository

### Query 2 — Buscar owners em batch
0) Identificação
- Função: `getMultipleEventOwnersData()`
- Tipo: (x) get (whereIn)
- Coleção: `events` (docId in chunk) + `users_preview` (whereIn)

---

## Feature/Tela: Conversas (lista + paginação)

### Query 1 — Stream principal de conversas
0) Identificação
- Arquivo(s): lib/features/conversations/state/conversations_viewmodel.dart
- Função: `_initFirestoreStream()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Connections/{userId}/Conversations`
- orderBy: `timestamp desc`, limit 30

1) Frequência
- Contínua (stream)
- ⚠️ Red flag: stream + listas longas (avaliar limite e cache).

### Query 2 — Paginação (loadMore)
0) Identificação
- Arquivo(s): lib/features/conversations/widgets/conversation_stream_widget.dart
- Função: `_handleEndReached()`
- Tipo: (x) get
- Coleção: `Connections/{userId}/Conversations`
- orderBy `timestamp desc`, startAfterDocument, limit N

### Query 3 — Stream por tile (resumo de conversa)
0) Identificação
- Arquivo(s): lib/features/conversations/widgets/conversation_tile.dart
- Função: `StreamBuilder` → `getConversationSummaryById()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Connections/{userId}/Conversations/{conversationId}`
- ⚠️ Red flag: stream por item (pode multiplicar listeners).

---

## Feature/Tela: Notificações (in-app)

### Query 1 — Stream de notificações
0) Identificação
- Arquivo(s): lib/features/notifications/repositories/notifications_repository.dart
- Função: `getNotifications()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Notifications`
- wheres: `userId ==` + filtro por `n_type` (whereIn)
- orderBy: `timestamp desc` (com fallback sem orderBy)

### Query 2 — Paginação de notificações
0) Identificação
- Função: `getNotificationsPaginated()`
- Tipo: (x) get
- Coleção: `Notifications`
- where `userId ==` + filtros, startAfterDocument, limit
- Fallback legado: `n_receiver_id ==`

### Query 3 — Stream paginado (limitado)
0) Identificação
- Função: `getNotificationsPaginatedStream()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Notifications`, limit 20

---

## Feature/Tela: FCM Tokens

### Query 1 — Buscar tokens do usuário
0) Identificação
- Arquivo(s): lib/features/notifications/services/fcm_token_service.dart
- Função: `clearTokens()`
- Tipo: (x) get
- Coleção: `DeviceTokens` (where userId ==)

### Query 2 — Salvar/atualizar token
0) Identificação
- Função: `_saveToken()`
- Tipo: (x) get + (x) update/set
- Coleção: `DeviceTokens/{userId_deviceId}`

---

## Feature/Tela: Notificações de atividades

### Query 1 — Targeting (owner/participants)
0) Identificação
- Arquivo(s): lib/features/notifications/services/notification_targeting_service.dart
- Funções: `_getOwner()`, `_getParticipants()`
- Tipo: (x) get
- Coleção: `events/{eventId}`

### Query 2 — Criação de notificações (batch)
0) Identificação
- Arquivo(s): lib/features/notifications/services/notification_orchestrator.dart
- Função: `_sendBatchNotifications()`
- Tipo: (x) batch set
- Coleção: `Notifications`

---

## Feature/Tela: Event Photo Feed

### Query 1 — Feed principal (active + under_review)
0) Identificação
- Arquivo(s): lib/features/event_photo_feed/data/repositories/event_photo_repository.dart
- Função: `fetchFeedPageWithOwnPending()`
- Tipo: (x) get (2 queries em paralelo)
- Coleção: `EventPhotos`
- where: `status == active` + `status == under_review AND userId ==`
- orderBy: `createdAt desc`, limit N

### Query 2 — Following via fanout
0) Identificação
- Função: `_fetchFollowingPageViaFanout()`
- Tipo: (x) get
- Coleções:
  - `feeds/{userId}/items` (sourceType == event_photo)
  - `EventPhotos` (where docId in chunk)

### Query 3 — Following via Users/following
0) Identificação
- Função: `_fetchFollowingIds()`
- Tipo: (x) get
- Coleção: `Users/{userId}/following` (orderBy createdAt, limit 200)

### Query 4 — Feed simples (global/cidade/evento/user)
0) Identificação
- Função: `fetchFeedPage()` / `fetchFeedPageNewerThan()` / `fetchPendingPageNewerThan()`
- Tipo: (x) get
- Coleção: `EventPhotos`
- where por scope (eventCityId, eventId, userId) + status
- orderBy createdAt desc, limit, startAfterDocument

### Query 5 — CRUD de fotos
0) Identificação
- Funções: `createPhoto()`, `updatePhotoStatus()`, `updatePhotoCounts()`
- Tipo: (x) set/update
- Coleção: `EventPhotos/{photoId}`

### Query 6 — Comentários e replies
0) Identificação
- Funções: `fetchComments()`, `addComment()`, `deleteComment()`, `fetchReplies()`, `addReply()`
- Tipo: (x) get/add/delete + update counts
- Coleções:
  - `EventPhotos/{photoId}/comments`
  - `EventPhotos/{photoId}/comments/{commentId}/replies`

### Query 7 — Likes
0) Identificação
- Arquivo(s): lib/features/event_photo_feed/domain/services/event_photo_like_service.dart
- Funções: `watchLikesCount()` (stream), `toggleLike()` (transaction)
- Coleções:
  - `EventPhotos/{photoId}`
  - `EventPhotos/{photoId}/likes/{userId}`
- ⚠️ Red flag: stream por item se usado em listas grandes.

---

## Feature/Tela: Eventos recentes (composer)

### Query 1 — Buscar aplicações aprovadas
0) Identificação
- Arquivo(s): lib/features/event_photo_feed/domain/services/recent_events_service.dart
- Função: `fetchRecentEligibleEvents()`
- Tipo: (x) get
- Coleção: `EventApplications`
- where: `userId ==`, `status in [approved, autoApproved]`
- orderBy `appliedAt desc`, limit N

### Query 2 — Buscar eventos (whereIn)
0) Identificação
- Função: `fetchRecentEligibleEvents()`
- Tipo: (x) get
- Coleção: `events` (docId in chunk)

### Query 3 — Buscar eventos do owner
0) Identificação
- Função: `fetchRecentEligibleEvents()`
- Tipo: (x) get
- Coleção: `events` (where createdBy ==, orderBy createdAt)

---

## Feature/Tela: Perfil e seguidores

### Query 1 — Buscar perfil
0) Identificação
- Arquivo(s): lib/features/profile/data/repositories/profile_repository.dart
- Função: `fetchProfileData()`
- Tipo: (x) get
- Coleção: `Users/{userId}`

### Query 2 — Atualizar perfil
0) Identificação
- Funções: `updateProfile()`, `updateProfilePhoto()`, `updateLocation()`
- Tipo: (x) update
- Coleção: `Users/{userId}` (+ subcoleção `private/location`)

### Query 3 — Seguir/Deixar de seguir
0) Identificação
- Arquivo(s): lib/features/profile/data/datasources/follow_remote_datasource.dart
- Função: `isFollowing()`
- Tipo: (x) stream/onSnapshot
- Coleção: `Users/{myUid}/following/{targetUid}`

### Query 4 — Followers/Following com paginação
0) Identificação
- Arquivo(s): lib/features/profile/presentation/controllers/followers_controller.dart
- Funções: `_loadFollowersFromFirestore()`, `_loadFollowingFromFirestore()`, `loadMoreFollowers()`
- Tipo: (x) get
- Coleções:
  - `Users/{userId}/followers` (orderBy createdAt, limit, startAfter)
  - `Users/{userId}/following` (orderBy createdAt, limit, startAfter)
- Enriquecimento: `UserRepository.getUsersByIds()` (users_preview whereIn)

---

## Feature/Tela: Visitas ao perfil

### Query 1 — Stream de visitas
0) Identificação
- Arquivo(s): lib/features/profile/data/services/profile_visits_service.dart
- Função: `watchUser()`
- Tipo: (x) stream/onSnapshot
- Coleção: `ProfileVisits`
- where: `visitedUserId ==`, orderBy `visitedAt desc`, limit 200

### Query 2 — Carregar visitas (get)
- Função: `getVisitsOnce()`
- Tipo: (x) get
- Coleção: `ProfileVisits`
- where: `visitedUserId ==`, `visitedAt > cutoff`, orderBy `visitedAt desc`, limit 1000
- Enriquecimento: `UserDataService.getUsersByIds()` + `getRatingsByUserIds()`
- ⚠️ Red flag: múltiplas queries adicionais por visita (mitigado por cache).

### Query 3 — Registrar visita
- Função: `recordVisit()`
- Tipo: (x) set (merge) + (x) add
- Coleções: `ProfileVisits`, `ProfileViews`

### Query 4 — Count de visitas (aggregate)
- Arquivo(s): lib/features/profile/data/services/visits_service.dart
- Função: `getUserVisitsCount()`
- Tipo: (x) aggregate/count
- Coleção: `ProfileVisits` (where visitedUserId ==, visitedAt > cutoff)

### Query 5 — Stream do count (limit 1)
- Função: `watchUserVisitsCount()`
- Tipo: (x) stream/onSnapshot
- Coleção: `ProfileVisits` (orderBy visitedAt desc, limit 1)

---

## Feature/Tela: Group Info

### Query 1 — Preferências do usuário
0) Identificação
- Arquivo(s): lib/features/events/presentation/screens/group_info/group_info_controller.dart
- Função: `_loadUserPreferences()`
- Tipo: (x) get
- Coleção: `Users/{userId}`

### Query 2 — Dados do evento
0) Identificação
- Função: `_loadEventData()`
- Tipo: (x) get
- Coleção: `events/{eventId}`

---

## Feature/Tela: Web Dashboard

### Query 1 — Eventos (paginação)
0) Identificação
- Arquivo(s): lib/features/web_dashboard/screens/events_table_screen.dart
- Tipo: (x) get
- Coleção: `events` (orderBy createdAt desc, limit, startAfter)

### Query 2 — Total de usuários (count)
0) Identificação
- Arquivo(s): lib/features/web_dashboard/screens/users_table_screen.dart
- Tipo: (x) aggregate/count
- Coleção: `Users`

### Query 3 — Reports (stream)
0) Identificação
- Arquivo(s): lib/features/web_dashboard/screens/reports_table_screen.dart
- Tipo: (x) stream/onSnapshot
- Coleção: `reports`
- where: `type ==` (opcional), orderBy createdAt desc

---

## Feature/Tela: Localização (update)

### Query 1 — Update localização
0) Identificação
- Arquivo(s): lib/features/location/data/repositories/location_repository.dart
- Função: `updateUserLocation()`
- Tipo: (x) set (merge) + (x) update
- Coleções:
  - `Users/{userId}/private/location`
  - `Users/{userId}` (display fields)

---

## Feature/Tela: Social Auth

### Query 1 — Buscar nome no Firestore (fallback)
0) Identificação
- Arquivo(s): lib/shared/services/auth/social_auth.dart
- Função: `signInWithApple()`
- Tipo: (x) get
- Coleção: `Users/{userId}`

---

## Feature/Tela: RevenueCat

### Query 1 — Buscar config/API key
0) Identificação
- Arquivo(s): lib/features/subscription/services/simple_revenue_cat_service.dart
- Funções: `_getApiKey()`, `_loadConfiguration()`
- Tipo: (x) get
- Coleção: `AppInfo/revenue_cat`

---

# Aprofundamento — Cloud Functions (backend)

## Function: GeoService (findUsersInRadius)
0) Identificação
- Arquivo(s): functions/lib/services/geoService.js
- Tipo: (x) get
- Coleção: `Users` (displayLatitude/latitude/lastLocation)
- where: range latitude, limit N

1) Escopo
- ⚠️ Red flag: range latitude + filtro de longitude em memória.

## Function: GeoService (findUsersForEventNotification)
- Coleção: `Users` (displayLatitude/latitude)
- where: range latitude, limit * 2

## Function: GeoService (getEventParticipants)
- Coleção: `EventApplications`
- where: `eventId ==`, `status in [approved, autoApproved]`

---

## Function: createPendingReviewsScheduled
0) Identificação
- Arquivo(s): functions/lib/reviews/createPendingReviews.js
- Tipo: (x) get + (x) batch set/update
- Coleções:
  - `events` (orderBy schedule.date, where <=, limit 100)
  - `EventApplications` (eventId ==, presence == Vou, status in...)
  - `Users` (docId in chunk)
  - `PendingReviews` (batch set)
  - `events/{eventId}` (batch update)

⚠️ Red flag: múltiplas queries + batch grande por execução.

---

## Function: onPresenceConfirmed
0) Identificação
- Arquivo(s): functions/lib/reviews/onPresenceConfirmed.js
- Tipo: (x) get + (x) batch set
- Coleções:
  - `Users/{ownerId}` (get)
  - `PendingReviews/{participantReviewId}` (get + batch set)

---

## Function: deviceBlacklist
0) Identificação
- Arquivo(s): functions/lib/devices/deviceBlacklist.js
- Tipo: (x) get + (x) transaction + (x) batch set
- Coleções:
  - `BlacklistDevices/{deviceIdHash}` (get)
  - `Users/{uid}/clients/{deviceIdHash}` (transaction)
  - `Users/{userId}/clients` (get)
  - `BlacklistDevices` (batch set)

---

## Function: pushDispatcher
0) Identificação
- Arquivo(s): functions/lib/services/pushDispatcher.js
- Tipo: (x) get + (x) transaction + (x) batch
- Coleções:
  - `Users/{userId}` (get preferências)
  - `DeviceTokens` (where userId ==)
  - `push_receipts/{idempotencyKey}` (transaction)

---

## Function: chatMessageDeletion
0) Identificação
- Arquivo(s): functions/lib/chatMessageDeletion.js
- Tipo: (x) get + (x) update/set + (x) query paginada
- Coleções:
  - `EventChats/{eventId}` (get)
  - `events/{eventId}` (get fallback)
  - `EventChats/{eventId}/Messages` (get doc, query orderBy timestamp desc limit 200, where is_deleted == false)

---

## Function: cleanupOldNotifications
0) Identificação
- Arquivo(s): functions/lib/notifications/cleanupOldNotifications.js
- Tipo: (x) get + (x) batch delete
- Coleção: `Notifications` (where timestamp < cutoff, orderBy asc, limit 500)

---

## Function: chatPushNotifications
0) Identificação
- Arquivo(s): functions/lib/chatPushNotifications.js
- Tipo: (x) get
- Coleção: `Users/{senderId}` (fetch nome)

---

## Function: diditWebhook
0) Identificação
- Arquivo(s): functions/lib/didit-webhook.js
- Tipo: (x) get + (x) set
- Coleções:
  - `AppInfo/didio` (get config)
  - `Users/{userId}` (set merge)
  - `FaceVerifications/{userId}` (set merge)

---

## Function: faceioWebhook
0) Identificação
- Arquivo(s): functions/lib/webhooks/faceio-webhook.js
- Tipo: (x) batch set/update + (x) get
- Coleções:
  - `FaceVerifications` (set/update)
  - `Users/{userId}` (set/update)
  - `FaceVerificationLogs` (add)
  - `FaceVerifications` (where facialId ==, limit 1)

---

## Function: backfillMissingNotificationTimestamps
0) Identificação
- Arquivo(s): functions/lib/notifications/backfillMissingNotificationTimestamps.js
- Tipo: (x) get + (x) batch update
- Coleção: `Notifications` (where createdAt >= cutoff OR n_created_at >= cutoff, orderBy desc, limit 500)

---

## Function: cleanupOldProfileVisits
0) Identificação
- Arquivo(s): functions/lib/profileVisitsCleanup.js
- Tipo: (x) get + (x) batch delete
- Coleção: `ProfileVisits` (where visitedAt < cutoff, limit 500)
