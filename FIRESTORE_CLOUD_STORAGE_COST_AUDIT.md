# Auditoria de Custos: Firestore & Cloud Storage

**Data:** 15/02/2026  
**Escopo:** `lib/` — Flutter app source code only

---

## 1. RESUMO EXECUTIVO

| Métrica | Contagem |
|---------|----------|
| `FirebaseFirestore.instance` em `lib/` | **168 ocorrências** em ~60 arquivos |
| `.snapshots()` (listeners real-time) | **50 ocorrências** em ~25 arquivos |
| `.get()` (leituras one-time) | **~100+ ocorrências** (somente em `lib/`) |
| `FirebaseStorage` usage points | **8 arquivos** |
| Upload operations (`putFile`/`putData`) | **8 upload points** |
| `getDownloadURL` calls | **7 pontos** |
| `NetworkImage` sem cache (uncached) | **4 pontos** |
| N+1 query patterns | **3 padrões críticos** |
| Repositories sem cache | **10+** |

---

## 2. FIRESTORE: STREAMS (real-time) vs ONE-TIME READS

### 2.1 Real-time Listeners (`.snapshots()`) — 50 ocorrências

Cada `.snapshots()` mantém um websocket aberto e gera cobrança por leitura a cada documento modificado.

#### CRÍTICOS (alto volume / abertos para toda sessão):

| # | Arquivo | Linha | Descrição | Risco |
|---|---------|-------|-----------|-------|
| 1 | [event_card_controller.dart](lib/features/home/presentation/widgets/event_card/event_card_controller.dart#L671) | 671 | Stream de `EventApplications` por card (1 por card visível) | **ALTO** — N cards = N listeners |
| 2 | [event_card_controller.dart](lib/features/home/presentation/widgets/event_card/event_card_controller.dart#L695) | 695 | Stream do evento inteiro `.doc(eventId).snapshots()` por card | **ALTO** — N cards = N listeners |
| 3 | [event_card_controller.dart](lib/features/home/presentation/widgets/event_card/event_card_controller.dart#L766) | 766 | Stream de participantes aprovados por card | **ALTO** — N cards = N listeners |
| 4 | [event_card_controller.dart](lib/features/home/presentation/widgets/event_card/event_card_controller.dart#L508) | 508 | Stream de `EventFees` por card | **ALTO** — N cards = N listeners |
| 5 | [conversations_viewmodel.dart](lib/features/conversations/state/conversations_viewmodel.dart#L248) | 248 | Stream de conversas inteiras do usuário | **MÉDIO** — 1 por sessão mas pode ser grande |
| 6 | [notifications_repository.dart](lib/features/notifications/repositories/notifications_repository.dart#L70) | 70 | Stream de notificações **sem limit** | **ALTO** — cresce infinitamente |
| 7 | [notifications_repository.dart](lib/features/notifications/repositories/notifications_repository.dart#L246) | 246 | Stream paginado de notificações (com limit) | **MÉDIO** |
| 8 | [block_service.dart](lib/core/services/block_service.dart#L69) | 69 | Stream de `blockedByMe` | **BAIXO** — 1 por sessão, poucos docs |
| 9 | [block_service.dart](lib/core/services/block_service.dart#L94) | 94 | Stream de `blockedMe` | **BAIXO** — 1 por sessão |
| 10 | [user_store.dart](lib/shared/stores/user_store.dart#L970) | 970 | Stream de `UsersPreview` por user visualizado | **ALTO** — abre para cada perfil visto |
| 11 | [user_store.dart](lib/shared/stores/user_store.dart#L1010) | 1010 | Stream de `Users` (full doc) por user | **ALTO** — abre para cada perfil |
| 12 | [avatar_store.dart](lib/shared/stores/avatar_store.dart#L68) | 68 | Stream de avatar por user | **ALTO** — abre para cada avatar visível |
| 13 | [user_repository.dart](lib/shared/repositories/user_repository.dart#L212) | 212 | Stream de dados do user atual | **BAIXO** — 1 por sessão |
| 14 | [chat_repository.dart](lib/core/repositories/chat_repository.dart#L45) | 45 | Stream de mensagens do chat | **MÉDIO** — 1 por chat aberto |
| 15 | [chat_repository.dart](lib/core/repositories/chat_repository.dart#L79) | 79 | Stream de mensagens (outro tipo) | **MÉDIO** |
| 16 | [chat_repository.dart](lib/core/repositories/chat_repository.dart#L544) | 544 | Stream de typing indicator | **BAIXO** — 1 doc |
| 17 | [chat_service.dart](lib/screens/chat/services/chat_service.dart#L56) | 56 | Stream de chat | **MÉDIO** |
| 18 | [chat_service.dart](lib/screens/chat/services/chat_service.dart#L107) | 107 | Stream de chat | **MÉDIO** |
| 19 | [chat_service.dart](lib/screens/chat/services/chat_service.dart#L176) | 176 | Stream de presence | **MÉDIO** |
| 20 | [user_presence_status_widget.dart](lib/screens/chat/widgets/user_presence_status_widget.dart#L81) | 81 | Stream de presence inline no widget | **MÉDIO** |
| 21 | [notifications_counter_service.dart](lib/common/services/notifications_counter_service.dart#L139) | 139 | Stream de notificações não lidas | **MÉDIO** |
| 22 | [notifications_counter_service.dart](lib/common/services/notifications_counter_service.dart#L202) | 202 | Stream de notificações | **MÉDIO** |
| 23 | [pending_reviews_listener_service.dart](lib/features/reviews/presentation/services/pending_reviews_listener_service.dart#L61) | 61 | Stream de pending reviews | **BAIXO** |
| 24 | [review_repository.dart](lib/features/reviews/data/repositories/review_repository.dart#L106) | 106 | Stream de reviews | **MÉDIO** |
| 25 | [review_repository.dart](lib/features/reviews/data/repositories/review_repository.dart#L541) | 541 | Stream de reviews | **MÉDIO** |
| 26 | [review_repository.dart](lib/features/reviews/data/repositories/review_repository.dart#L575) | 575 | `await for` em query.snapshots() — stream consumido como async | **MÉDIO** |
| 27 | [review_repository.dart](lib/features/reviews/data/repositories/review_repository.dart#L625) | 625 | `await for` em query.snapshots() | **MÉDIO** |
| 28 | [event_photo_like_service.dart](lib/features/event_photo_feed/domain/services/event_photo_like_service.dart#L35) | 35 | Stream de likes por foto | **ALTO** — 1 por foto visível |
| 29 | [event_photo_like_service.dart](lib/features/event_photo_feed/domain/services/event_photo_like_service.dart#L65) | 65 | Stream de likes do user | **MÉDIO** |
| 30 | [profile_controller.dart](lib/features/profile/presentation/controllers/profile_controller.dart#L84) | 84 | Stream de dados do perfil | **MÉDIO** |
| 31 | [profile_controller.dart](lib/features/profile/presentation/controllers/profile_controller.dart#L174) | 174 | Stream de dados do perfil | **MÉDIO** |
| 32 | [profile_completeness_prompt_service.dart](lib/features/profile/data/services/profile_completeness_prompt_service.dart#L187) | 187 | Stream de completude do perfil | **BAIXO** |
| 33 | [follow_remote_datasource.dart](lib/features/profile/data/datasources/follow_remote_datasource.dart#L30) | 30 | Stream de follows | **MÉDIO** |
| 34 | [profile_visits_service.dart](lib/features/profile/data/services/profile_visits_service.dart#L174) | 174 | Stream de `ProfileVisits` **limit(200)** | **ALTO** — 200 docs em realtime |
| 35 | [visits_service.dart](lib/features/profile/data/services/visits_service.dart#L152) | 152 | Stream de visits limit(1) | **BAIXO** |
| 36 | [auth_sync_service.dart](lib/core/services/auth_sync_service.dart#L233) | 233 | Stream do usuário actual | **BAIXO** — 1 doc |
| 37 | [face_verification_service.dart](lib/core/services/face_verification_service.dart#L140) | 140 | Stream de verificação facial | **BAIXO** |
| 38 | [didit_verification_service.dart](lib/core/services/didit_verification_service.dart#L283) | 283 | Stream de verificação Didit | **BAIXO** |
| 39 | [event_repository.dart](lib/features/home/data/repositories/event_repository.dart#L292) | 292 | Stream de eventos | **MÉDIO** |
| 40 | [pending_applications_repository.dart](lib/features/home/data/repositories/pending_applications_repository.dart#L42) | 42 | Stream de aplicações pendentes | **MÉDIO** |
| 41 | [pending_applications_repository.dart](lib/features/home/data/repositories/pending_applications_repository.dart#L68) | 68 | Stream de aplicações pendentes | **MÉDIO** |
| 42 | [list_drawer_controller.dart](lib/features/home/presentation/widgets/list_drawer/list_drawer_controller.dart#L77) | 77 | Stream no drawer | **MÉDIO** |
| 43 | [reports_table_screen.dart](lib/features/web_dashboard/screens/reports_table_screen.dart#L143) | 143 | Stream de reports (dashboard web) | **BAIXO** |
| 44 | [reports_table_screen.dart](lib/features/web_dashboard/screens/reports_table_screen.dart#L149) | 149 | Stream de reports | **BAIXO** |

### 2.2 One-time reads (`.get()`) — 100+ ocorrências em `lib/`

Leituras pontuais: menores custos individuais, mas se repetidas sem cache, somam.

---

## 3. PADRÕES N+1 ENCONTRADOS (CRÍTICOS)

### 3.1 `invite_drawer.dart` — Loop de leituras individuais
**Arquivo:** [invite_drawer.dart](lib/features/home/presentation/widgets/invite_drawer.dart#L66-L85)  
**Problema:** Faz `.get()` individual para cada usuário em um `for` loop:
```dart
for (final doc in referralInstalls.docs) {
  final invitedUserDoc = await FirebaseFirestore.instance
      .collection('Users').doc(userId).get();  // ❌ N+1
}
```
**Impacto:** Se há 20 referrals = 20 leituras individuais (vs 2 leituras batch com `whereIn`).

### 3.2 `referral_debug_screen.dart` — Mesmo padrão
**Arquivo:** [referral_debug_screen.dart](lib/features/home/presentation/widgets/referral_debug_screen.dart#L163-L175)  
**Problema:** Mesmo padrão N+1 com ReferralInstalls → Users.

### 3.3 `user_data_service.dart` — Individual reads em loop (parcialmente mitigado)
**Arquivo:** [user_data_service.dart](lib/shared/services/user_data_service.dart#L139-L155)  
**Problema:** Usa `Future.wait()` para paralelizar, mas cada chamada é uma leitura individual ao Firestore:
```dart
final futures = uncachedUserIds.map((userId) async {
  final userData = await _userRepository.getUserById(userId);  // ❌ individual
}).toList();
```
**Mitigação existente:** Tem cache in-memory, mas IDs não cacheados fazem N requests individuais.
**Solução:** Usar `whereIn` com batches de 10 (limite do Firestore).

### 3.4 `getRatingsByUserIds` — Correto!
**Arquivo:** [user_data_service.dart](lib/shared/services/user_data_service.dart#L275-L282)  
✅ Este método já usa `whereIn` com batches de 10 — padrão correto.

---

## 4. CLOUD STORAGE — UPLOADS & DOWNLOADS

### 4.1 Upload Points (8 pontos)

| # | Arquivo | Linha | Operação | Compressão? |
|---|---------|-------|----------|-------------|
| 1 | [auth_repository.dart](lib/shared/repositories/auth_repository.dart#L377) | 377 | `ref.putFile()` — foto perfil | ✅ Sim (`ImageCompressService`) |
| 2 | [auth_repository.dart](lib/shared/repositories/auth_repository.dart#L434) | 434 | `ref.putFile()` — foto perfil | ❓ Não claro |
| 3 | [image_upload_view_model.dart](lib/features/profile/presentation/viewmodels/image_upload_view_model.dart#L91) | 91 | `imageRef.putFile()` — gallery | ✅ Comprimido antes |
| 4 | [image_upload_service.dart](lib/features/profile/data/services/image_upload_service.dart#L134) | 134 | `ref.putFile()` — profile images | ✅ Compressão |
| 5 | [image_upload_service.dart](lib/features/profile/data/services/image_upload_service.dart#L229) | 229 | `ref.putData()` — bytes comprimidos | ✅ Compressão |
| 6 | [event_photo_composer_service.dart](lib/features/event_photo_feed/domain/services/event_photo_composer_service.dart#L93) | 93 | `photoRef.putData()` — foto evento | ✅ Presumível |
| 7 | [event_photo_composer_service.dart](lib/features/event_photo_feed/domain/services/event_photo_composer_service.dart#L108) | 108 | `thumbRef.putData()` — thumbnail | ✅ Thumb |
| 8 | [chat_repository.dart](lib/core/repositories/chat_repository.dart#L449) | 449 | `ref.putFile()` — chat image | ✅ Comprimido |

### 4.2 Download URL Points (7 pontos)

| # | Arquivo | Linha |
|---|---------|-------|
| 1 | [auth_repository.dart](lib/shared/repositories/auth_repository.dart#L381) | 381 |
| 2 | [auth_repository.dart](lib/shared/repositories/auth_repository.dart#L438) | 438 |
| 3 | [image_upload_view_model.dart](lib/features/profile/presentation/viewmodels/image_upload_view_model.dart#L93) | 93 |
| 4 | [image_upload_service.dart](lib/features/profile/data/services/image_upload_service.dart#L146) | 146 |
| 5 | [image_upload_service.dart](lib/features/profile/data/services/image_upload_service.dart#L243) | 243 |
| 6 | [event_photo_composer_service.dart](lib/features/event_photo_feed/domain/services/event_photo_composer_service.dart#L104) | 104 |
| 7 | [chat_repository.dart](lib/core/repositories/chat_repository.dart#L452) | 452 |

---

## 5. IMAGENS SEM CACHE (NetworkImage cru)

| # | Arquivo | Linha | Problema |
|---|---------|-------|----------|
| 1 | [event_photo_comment_thread_sheet.dart](lib/features/event_photo_feed/presentation/widgets/event_photo_comment_thread_sheet.dart#L274) | 274 | `NetworkImage(comment.userPhotoUrl)` — sem cache em disco |
| 2 | [event_photo_comment_thread_sheet.dart](lib/features/event_photo_feed/presentation/widgets/event_photo_comment_thread_sheet.dart#L332) | 332 | `NetworkImage(reply.userPhotoUrl)` — sem cache em disco |
| 3 | [event_photo_comments_sheet.dart](lib/features/event_photo_feed/presentation/widgets/event_photo_comments_sheet.dart#L317) | 317 | `NetworkImage(comment.userPhotoUrl)` — sem cache em disco |
| 4 | [event_photo_comments_sheet.dart](lib/features/event_photo_feed/presentation/widgets/event_photo_comments_sheet.dart#L439) | 439 | `NetworkImage(reply.userPhotoUrl)` — sem cache em disco |

**Impacto:** Cada vez que o usuário abre a sheet de comentários, baixa todas as fotos novamente do Cloud Storage. Se há 50 comentários com avatares, são 50 downloads repetidos (sem cache em disco).

**Solução:** Trocar `NetworkImage(url)` por `CachedNetworkImageProvider(url)`.

---

## 6. ANÁLISE DE CACHE POR IMAGENS

### 6.1 Pontos com cache correto ✅
- `CachedNetworkImage` com `cacheManager` definido: ~15 pontos
- `CachedNetworkImageProvider` com cache manager: ~10 pontos
- `MediaCacheManager`, `AvatarImageCache`, `ChatMediaImageCache`, `AppCacheService.instance.galleryCacheManager` — bem configurados

### 6.2 Pontos sem cacheManager explícito ⚠️
Vários `CachedNetworkImage(imageUrl: ...)` sem `cacheManager:` explícito usam o cache default que pode não ter TTL configurado. Estes funcionam mas não são otimizados:
- [image_lightbox.dart](lib/screens/chat/widgets/image_lightbox.dart#L35) L35
- [reply_bubble_widget.dart](lib/screens/chat/widgets/reply_bubble_widget.dart#L196) L196
- [glimpse_chat_bubble.dart](lib/screens/chat/widgets/glimpse_chat_bubble.dart#L452) L452
- [media_viewer_screen.dart](lib/shared/screens/media_viewer_screen.dart#L161) L161

---

## 7. REPOSITORIES — ANÁLISE DE CACHING

### 7.1 Repositories COM cache ✅

| Repository | Tipo de Cache |
|-----------|--------------|
| `event_cache_repository.dart` | Cache dedicado |
| `message_persistent_cache_repository.dart` | Persistent cache (SQLite/SharedPrefs) |
| `notification_persistent_cache_repository.dart` | Persistent cache |
| `conversation_persistent_cache_repository.dart` | Persistent cache |
| `last_known_location_cache_repository.dart` | Local cache |
| `user_preferences_cache_repository.dart` | Local cache |
| `user_session_cache_repository.dart` | Local cache |
| `user_data_service.dart` | In-memory TTL cache |
| `review_repository.dart` | ReviewPageCacheService (6h TTL) |

### 7.2 Repositories SEM cache ❌

| Repository | Acessa Firestore? | Beneficiaria de Cache? |
|-----------|-------------------|----------------------|
| [notifications_repository.dart](lib/features/notifications/repositories/notifications_repository.dart) | ✅ Direto | ✅ Sim — streams pesados |
| [event_application_repository.dart](lib/features/home/data/repositories/event_application_repository.dart) | ✅ Direto | ✅ Sim — leituras frequentes |
| [event_map_repository.dart](lib/features/home/data/repositories/event_map_repository.dart) | ✅ Direto | ✅ Sim — queries geo |
| [follow_repository.dart](lib/features/profile/data/repositories/follow_repository.dart) | ✅ Via datasource | ✅ Sim — listas de seguidores |
| [profile_repository.dart](lib/features/profile/data/repositories/profile_repository.dart) | ✅ Direto | ✅ Sim — dados de perfil |
| [activity_feed_repository.dart](lib/features/feed/data/repositories/activity_feed_repository.dart) | ✅ Direto | ✅ Sim — feed |
| [activity_repository.dart](lib/features/home/create_flow/activity_repository.dart) | ✅ Direto | ⚠️ Parcial |
| [event_repository.dart](lib/features/home/data/repositories/event_repository.dart) | ✅ Direto | ✅ Sim |
| [location_repository.dart](lib/features/location/data/repositories/location_repository.dart) | ✅ Direto | ✅ Sim — dados geo |
| [actions_repository.dart](lib/features/reviews/data/repositories/actions_repository.dart) | ✅ Direto | ⚠️ Parcial |

---

## 8. STREAMS QUE PODERIAM SER ONE-TIME READS

| # | Arquivo | Linha | Justificativa |
|---|---------|-------|---------------|
| 1 | [profile_visits_service.dart](lib/features/profile/data/services/profile_visits_service.dart#L174) | 174 | Stream de **200 docs** de ProfileVisits — apenas para detectar mudanças e recontar. Poderia usar polling periódico + `.get()` |
| 2 | [face_verification_service.dart](lib/core/services/face_verification_service.dart#L140) | 140 | Verificação facial raramente muda — poderia ser `.get()` com retry |
| 3 | [didit_verification_service.dart](lib/core/services/didit_verification_service.dart#L283) | 283 | Verificação DIDIT raramente muda — poderia ser `.get()` com retry |
| 4 | [profile_completeness_prompt_service.dart](lib/features/profile/data/services/profile_completeness_prompt_service.dart#L187) | 187 | Completude do perfil — muda raramente, poderia cachear local |
| 5 | [reports_table_screen.dart](lib/features/web_dashboard/screens/reports_table_screen.dart#L143) | 143 | Dashboard Web — polling seria suficiente |

---

## 9. STREAMS MULTIPLICADOS POR CARD (MAIOR IMPACTO DE CUSTO)

**O maior problema de custo identificado** está no `event_card_controller.dart`. Para **cada card de evento visível na tela**, são abertos **4 listeners Firestore**:

1. `EventApplications.where(eventId).where(userId).snapshots()` — L671
2. `events.doc(eventId).snapshots()` — L695
3. `EventApplications.where(eventId).where(status, whereIn: [...]).snapshots()` — L766
4. `EventFees` stream — L508

Se o mapa/lista mostra 15 eventos simultâneos = **60 listeners Firestore abertos**.

### Recomendações:
1. **Usar `.get()` para carga inicial** e só abrir `.snapshots()` quando o card é expandido/focado
2. **Compartilhar listeners** — cachear snapshots por `eventId` e reutilizar
3. **Lazy listeners** — só abrir quando o card está visível no viewport

---

## 10. ACESSO DIRETO AO FIRESTORE FORA DE REPOSITORIES

Muitos controllers/widgets/services acessam `FirebaseFirestore.instance` diretamente, quebrando a separação de responsabilidades:

| Arquivo | Contagem |
|---------|----------|
| [group_info_controller.dart](lib/features/events/presentation/screens/group_info/group_info_controller.dart) | **12 acessos diretos** |
| [event_card_controller.dart](lib/features/home/presentation/widgets/event_card/event_card_controller.dart) | **9 acessos diretos** |
| [app_notifications.dart](lib/features/notifications/helpers/app_notifications.dart) | **6 acessos diretos** |
| [app_section_card.dart](lib/features/profile/presentation/widgets/app_section_card.dart) | **6 acessos diretos** |
| [advanced_filters_controller.dart](lib/services/location/advanced_filters_controller.dart) | **5 acessos diretos** |
| [location_query_service.dart](lib/services/location/location_query_service.dart) | **4 acessos diretos** |
| [report_event_button.dart](lib/shared/widgets/report_event_button.dart) | **3 acessos diretos** |
| [invite_drawer.dart](lib/features/home/presentation/widgets/invite_drawer.dart) | **3 acessos diretos** |
| [feed_reminder_service.dart](lib/features/event_photo_feed/presentation/services/feed_reminder_service.dart) | **3 acessos diretos** |

---

## 11. PRIORIDADES DE OTIMIZAÇÃO (por impacto de custo)

### 🔴 ALTA PRIORIDADE

1. **`event_card_controller.dart` — 4 listeners por card** → Converter carga inicial para `.get()`, lazy listeners, ou agregar em snapshot único
2. **`notifications_repository.dart` — stream sem limit no `getNotifications()`** → Adicionar `.limit()` ao stream principal
3. **`avatar_store.dart` + `user_store.dart` — listeners por user** → Pool de listeners com cap máximo, cleanup agressivo
4. **4 `NetworkImage` uncached em comments** → Trocar por `CachedNetworkImageProvider`

### 🟡 MÉDIA PRIORIDADE

5. **N+1 em `invite_drawer.dart`** → Batch com `whereIn`
6. **N+1 em `user_data_service.dart` (uncached users)** → Batch com `whereIn`
7. **`profile_visits_service.dart` — stream de 200 docs** → Reduzir para limit(1) + count aggregation
8. **Repositories sem cache** (`event_application_repository`, `profile_repository`, `follow_repository`) → Adicionar in-memory cache com TTL

### 🟢 BAIXA PRIORIDADE

9. **Streams de verificação (face/didit)** → Trocar por `.get()` + retry
10. **Dashboard web streams** → Trocar por polling
11. **Acesso direto ao Firestore em widgets** → Refatorar para usar repositories

---

## 12. ESTIMATIVA DE ECONOMIA

| Otimização | Leituras/dia estimadas salvas |
|-----------|-------------------------------|
| Event card lazy listeners (15 cards × 4 listeners) | **~50k-200k reads/dia** |
| Cache de avatares (NetworkImage → Cached) | **~10k-50k reads/dia** (Storage bandwidth) |
| N+1 → batch reads | **~5k-20k reads/dia** |
| Notifications stream + limit | **~10k-50k reads/dia** |
| Profile visits limit reduzido | **~5k-10k reads/dia** |
| **TOTAL ESTIMADO** | **~80k-330k reads/dia** |

---

*Relatório gerado via auditoria automatizada do código fonte.*
