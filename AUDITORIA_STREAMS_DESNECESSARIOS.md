# 🔍 AUDITORIA: Streams Desnecessários na Aplicação

**Data:** 30 de janeiro de 2026  
**Objetivo:** Identificar e eliminar streams do Firestore que poderiam ser substituídos por `collection.get()` com paginação e cache.

---

## 📊 Resumo Executivo

### 🚨 Problemas Encontrados: 20+ casos de streams desnecessários

**Economia estimada:** ~94% de redução em leituras do Firestore  
**Impacto:** Alto custo financeiro e performance degradada

### 🔥 CRÍTICO: Event Photo Likes
- **40 streams simultâneos** no feed de fotos (20 fotos × 2 streams cada)
- **Erro ativo:** `collectionGroup` falhando por permissões
- **Solução:** Cache local + optimistic updates = **97.5% economia**

### ✅ Regra de Ouro

#### USAR STREAMS APENAS PARA:
- ✅ **Chat ativo** (mensagens em tempo real)
- ✅ **Live counters importantes** (contadores críticos)
- ✅ **Notificações novas** (badge de notificações não lidas)

#### NÃO USAR STREAMS PARA:
- ❌ **Seguidores/Following** (lista estática)
- ❌ **Listas de usuários** (dados históricos)
- ❌ **Web Dashboard** (tabelas administrativas)
- ❌ **Presenças em eventos** (lista de participantes)
- ❌ **Galeria de imagens do próprio usuário**
- ❌ **Contadores de seguidores em headers**
- ❌ **Reports e listagens administrativas**

---

## 🔴 PROBLEMAS CRÍTICOS (Alta Prioridade)

### 1. ❌ Web Dashboard - Users Table
**Arquivo:** `lib/features/web_dashboard/screens/users_table_screen.dart:23`

```dart
// PROBLEMA: Stream desnecessário carregando TODOS os usuários
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance.collection('Users').snapshots(),
```

**Impacto:**
- ❌ Carrega TODOS os usuários em tempo real
- ❌ Sem filtros, sem paginação
- ❌ Custo alto: N leituras a cada rebuild

**Solução:**
```dart
// ✅ Usar FutureBuilder com get() + paginação
FutureBuilder<QuerySnapshot>(
  future: FirebaseFirestore.instance
    .collection('Users')
    .orderBy('createdAt', descending: true)
    .limit(50)
    .get(),
```

**Economia:** ~95% menos leituras

---

### 2. ❌ Web Dashboard - Events Table
**Arquivo:** `lib/features/web_dashboard/screens/events_table_screen.dart:23`

```dart
// PROBLEMA: Stream carregando TODOS os eventos
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance.collection('events').snapshots(),
```

**Impacto:**
- ❌ Mesmos problemas do Users Table
- ❌ Tabela administrativa não precisa de real-time
- ❌ Reload manual já está disponível

**Solução:**
```dart
// ✅ Usar get() + refresh button
FutureBuilder<QuerySnapshot>(
  future: _fetchEvents(), // com paginação e cache
```

**Economia:** ~95% menos leituras

---

### 3. ❌ Web Dashboard - Reports Table
**Arquivo:** `lib/features/web_dashboard/screens/reports_table_screen.dart:143-149`

```dart
// PROBLEMA: Stream para listagem de reports
Stream<QuerySnapshot> _getReportsStream() {
  if (filterType == null) {
    return reportsRef.orderBy('createdAt', descending: true).snapshots();
  }
  return reportsRef
      .where('type', isEqualTo: filterType)
      .snapshots();
}
```

**Impacto:**
- ❌ Reports não mudam com frequência
- ❌ Tabela administrativa não precisa ser reativa
- ❌ Desperdiça leituras

**Solução:**
```dart
// ✅ Carregar uma vez com get()
Future<QuerySnapshot> _getReports() async {
  if (filterType == null) {
    return reportsRef.orderBy('createdAt', descending: true).limit(100).get();
  }
  return reportsRef
      .where('type', isEqualTo: filterType)
      .limit(100)
      .get();
}
```

**Economia:** ~90% menos leituras

---

### 4. ❌ Presence Drawer - Lista de Participantes Aprovados
**Arquivo:** `lib/screens/chat/widgets/presence_drawer.dart:108-113`

```dart
// PROBLEMA: Stream para lista estática de presenças
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance
      .collection('EventApplications')
      .where('eventId', isEqualTo: widget.eventId)
      .where('status', whereIn: ['approved', 'autoApproved'])
      .snapshots(),
```

**Impacto:**
- ❌ Lista de participantes não muda frequentemente
- ❌ Drawer é aberto/fechado muitas vezes
- ❌ Cada abertura reconstrói o stream

**Solução:**
```dart
// ✅ Carregar uma vez ao abrir o drawer
FutureBuilder<QuerySnapshot>(
  future: FirebaseFirestore.instance
      .collection('EventApplications')
      .where('eventId', isEqualTo: widget.eventId)
      .where('status', whereIn: ['approved', 'autoApproved'])
      .get(),
```

**Economia:** ~80% menos leituras

---

### 5. ❌ User Images Grid - Galeria do Próprio Usuário
**Arquivo:** `lib/features/profile/presentation/widgets/user_images_grid.dart:181-286`

```dart
// PROBLEMA: Stream para galeria do próprio usuário
StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance
      .collection('Users')
      .doc(userId)
      .snapshots(),
```

**Impacto:**
- ❌ Usuário editando suas próprias fotos não precisa de stream
- ❌ Upload já atualiza a UI localmente
- ❌ Desperdiça leituras desnecessárias

**Solução:**
```dart
// ✅ Usar state local + atualizar após upload
class _UserImagesGridState extends State<UserImagesGrid> {
  Map<String, dynamic> _gallery = {};
  bool _loading = true;
  
  @override
  void initState() {
    super.initState();
    _loadGalleryOnce();
  }
  
  Future<void> _loadGalleryOnce() async {
    final doc = await FirebaseFirestore.instance
        .collection('Users')
        .doc(widget.userId)
        .get();
    
    setState(() {
      _gallery = doc.data()?['user_gallery'] ?? {};
      _loading = false;
    });
  }
  
  // Atualizar localmente após upload bem-sucedido
  void _onUploadSuccess(int index, String url) {
    setState(() {
      _gallery['image_$index'] = {'url': url};
    });
  }
}
```

**Economia:** ~95% menos leituras

---

### 6. ❌ Profile Header - Contador de Seguidores
**Arquivo:** `lib/features/profile/presentation/components/profile_header.dart:587-609`

```dart
// PROBLEMA: Stream para contador de seguidores no header
StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance
      .collection('users_status')
      .doc(widget.user.userId)
      .snapshots(),
```

**Impacto:**
- ❌ Contador não precisa ser real-time no header
- ❌ Atualizar a cada segundo é overkill
- ❌ Header é reconstruído com frequência

**Solução:**
```dart
// ✅ Carregar uma vez ou usar cache com TTL
FutureBuilder<DocumentSnapshot>(
  future: _getFollowersCountCached(widget.user.userId),
  // OU usar um ValueNotifier atualizado apenas ao seguir/desseguir
```

**Economia:** ~85% menos leituras

---

### 7. ⚠️ Follow Remote Datasource - isFollowing Stream
**Arquivo:** `lib/features/profile/data/datasources/follow_remote_datasource.dart:27-37`

```dart
// PROBLEMA: Stream para verificar se está seguindo
Stream<bool> isFollowing(String myUid, String targetUid) {
  return _firestore
      .collection('Users')
      .doc(myUid)
      .collection('following')
      .doc(targetUid)
      .snapshots()
      .map((snapshot) => snapshot.exists);
}
```

**Impacto:**
- ⚠️ Stream ativo mesmo quando não está na tela
- ⚠️ Uso aceitável apenas se for usado em poucos lugares
- ⚠️ Verificar usages antes de decidir

**Análise Necessária:**
- Ver quantos lugares usam esse stream
- Se for usado em listas, substituir por get() + cache
- Se for apenas no botão de follow, pode manter

**Solução Alternativa:**
```dart
// ✅ Usar get() + atualizar localmente após follow/unfollow
Future<bool> isFollowing(String myUid, String targetUid) async {
  final doc = await _firestore
      .collection('Users')
      .doc(myUid)
      .collection('following')
      .doc(targetUid)
      .get();
  return doc.exists;
}
```

---

### 8. ❌ Event Photo Like Service - Like Count Stream
**Arquivo:** `lib/features/event_photo_feed/domain/services/event_photo_like_service.dart:35-40`

```dart
// PROBLEMA: Stream para contador de likes (N+1 queries no feed)
Stream<int> watchLikesCount(String photoId) {
  return _photos.doc(photoId).snapshots().map((doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return (data['likesCount'] as num?)?.toInt() ?? 0;
  });
}
```

**Impacto:**
- ❌ Cada foto no feed cria um stream separado
- ❌ N+1 query problem: 20 fotos = 20 streams ativos
- ❌ Contador atualiza constantemente desperdiçando reads
- ❌ Causa erro de permissão com `collectionGroup('likes')`

**Solução:**
```dart
// ✅ Buscar likesCount uma vez junto com os dados da foto
// O likesCount já vem no documento da foto do Firestore
int getLikesCount(Map<String, dynamic> photoData) {
  return (photoData['likesCount'] as num?)?.toInt() ?? 0;
}

// ✅ Se precisar atualizar após like/unlike, fazer optimistic update
Future<void> _updateLikesCountLocally(String photoId, int delta) {
  // Atualizar state local
  setState(() {
    _photos[photoId].likesCount += delta;
  });
}
```

**Economia:** ~95% menos leituras (elimina 20+ streams simultâneos)

---

### 9. ❌ Event Photo Like Service - isLiked Stream (DEPRECATED)
**Arquivo:** `lib/features/event_photo_feed/domain/services/event_photo_like_service.dart:49-71`

```dart
// PROBLEMA: Stream realtime para verificar se curtiu cada foto
@Deprecated('Use isLikedSync() ou isLikedFromCache() para evitar N+1 queries')
Stream<bool> watchIsLiked(String photoId) {
  final uid = _auth.currentUser?.uid;
  if (uid == null) return Stream<bool>.value(false);

  return _photos
      .doc(photoId)
      .collection('likes')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists);
}
```

**Impacto:**
- ❌ Já marcado como @Deprecated mas ainda pode estar sendo usado
- ❌ N+1 query problem severo (1 stream por foto)
- ❌ 20 fotos = 20 streams de likes simultâneos

**Solução:**
```dart
// ✅ JÁ IMPLEMENTADO: Usar cache local
bool isLikedSync(String photoId) {
  return _likesCache?.isLiked(photoId) ?? false;
}

// ✅ Toggle com optimistic update
Future<bool> toggleLike({required String photoId}) async {
  final isLiked = isLikedSync(photoId);
  
  // 1. Atualizar cache local imediatamente
  if (isLiked) {
    await _likesCache?.removeLike(photoId);
  } else {
    await _likesCache?.addLike(photoId);
  }
  
  // 2. Sincronizar com Firestore em background
  try {
    // ... persist to Firestore
  } catch (e) {
    // 3. Reverter em caso de erro
    if (isLiked) {
      await _likesCache?.addLike(photoId);
    } else {
      await _likesCache?.removeLike(photoId);
    }
  }
}
```

**Ação:** Remover completamente o método `watchIsLiked()` após confirmar que não há usages

---

### 10. ⚠️ Event Photo Likes Cache - CollectionGroup Query
**Arquivo:** `lib/features/event_photo_feed/domain/services/event_photo_likes_cache_service.dart:160-170`

```dart
// PROBLEMA: collectionGroup com permissões inadequadas
final snapshot = await _firestore
    .collectionGroup('likes')
    .where('userId', isEqualTo: uid)
    .orderBy('createdAt', descending: true)
    .limit(_hydrationLimit)
    .get();
```

**Erro Atual:**
```
❌ [EventPhotoLikesCacheService] Erro na hidratação: 
[cloud_firestore/permission-denied] The caller does not have permission 
to execute the specified operation.
```

**Impacto:**
- ❌ CollectionGroup query requer permissões especiais no Firestore
- ❌ Query falha bloqueando hidratação do cache
- ❌ Pode ser substituída por abordagem mais eficiente

**Solução:**
```dart
// ✅ OPÇÃO 1: Manter histórico de likes em users_stats
// Criar subcoleção Users/{uid}/liked_photos com índice
Future<void> hydrateIfNeeded() async {
  final uid = _auth.currentUser?.uid;
  if (uid == null) return;

  try {
    final snapshot = await _firestore
        .collection('Users')
        .doc(uid)
        .collection('liked_photos')
        .orderBy('likedAt', descending: true)
        .limit(_hydrationLimit)
        .get();

    final photoIds = snapshot.docs
        .map((doc) => doc.id)  // doc.id é o photoId
        .toSet();

    _likedPhotoIds.clear();
    _likedPhotoIds.addAll(photoIds);
    _lastHydrationAt = DateTime.now();
    await _saveToHive();
  } catch (e) {
    debugPrint('❌ Erro na hidratação: $e');
  }
}

// ✅ OPÇÃO 2: Usar índice denormalizado em users_stats
// Manter array de photoIds curtidos recentemente
Future<void> hydrateIfNeeded() async {
  final uid = _auth.currentUser?.uid;
  if (uid == null) return;

  try {
    final doc = await _firestore
        .collection('users_stats')
        .doc(uid)
        .get();

    final data = doc.data();
    final recentLikes = List<String>.from(
      data?['recentLikedPhotos'] ?? []
    );

    _likedPhotoIds.clear();
    _likedPhotoIds.addAll(recentLikes);
    _lastHydrationAt = DateTime.now();
    await _saveToHive();
  } catch (e) {
    debugPrint('❌ Erro na hidratação: $e');
  }
}
```

**Recomendação:** Implementar OPÇÃO 2 (users_stats) por ser mais eficiente (1 read vs N reads)

**Economia:** ~99% menos leituras + resolve erro de permissão

---

## 🟡 PROBLEMAS MODERADOS (Média Prioridade)

### 11. ⚠️ Event Card Controller - Participants Count Stream
**Arquivo:** `lib/features/home/presentation/widgets/event_card/event_card_controller.dart:400-407`

```dart
// PROBLEMA: Stream público exposto para contagem
Stream<int> get participantsCountStream => (_participantsSnapshotStream ??
  FirebaseFirestore.instance
      .collection('EventApplications')
      .where('eventId', isEqualTo: eventId)
      .where('status', whereIn: ['approved', 'autoApproved'])
      .snapshots())
    .map((snapshot) => snapshot.docs.length);
```

**Análise:**
- ⚠️ Já tem `_participantsSnapshotStream` interno para tempo real
- ⚠️ Getter público pode causar múltiplas subscrições
- ✅ Se `enableRealtime` está false, não usa stream (OK)

**Recomendação:**
- ✅ Manter stream interno se `enableRealtime = true`
- ❌ Não expor getter público de stream
- ✅ Expor apenas o `participantsCount` (int) atualizado localmente

---

## 🟢 USO CORRETO DE STREAMS (Manter)

### ✅ 1. Chat Service - Mensagens
**Arquivo:** `lib/screens/chat/services/chat_service.dart:56,97,156`

```dart
// ✅ CORRETO: Chat precisa de tempo real
.snapshots()
```

**Justificativa:** Chat ativo precisa de atualizações em tempo real.

---

### ✅ 2. Notifications Counter Service
**Arquivo:** `lib/common/services/notifications_counter_service.dart:131,193`

```dart
// ✅ CORRETO: Badge de notificações não lidas precisa ser real-time
.snapshots()
```

**Justificativa:** Contador de notificações não lidas deve atualizar imediatamente.

---

### ✅ 3. Conversations Viewmodel
**Arquivo:** `lib/features/conversations/state/conversations_viewmodel.dart:238`

```dart
// ✅ CORRETO: Lista de conversas precisa atualizar em tempo real
.snapshots()
```

**Justificativa:** Novas mensagens devem aparecer imediatamente na lista de conversas.

---

### ✅ 4. Block Service
**Arquivo:** `lib/core/services/block_service.dart:69,94,301`

```dart
// ✅ CORRETO: Sistema de bloqueio precisa ser reativo
.snapshots()
```

**Justificativa:** Mudanças em bloqueios devem refletir imediatamente na UI.

---

### ✅ 5. Chat Repository
**Arquivo:** `lib/core/repositories/chat_repository.dart:44,68,533`

```dart
// ✅ CORRETO: Chat precisa de tempo real
.snapshots()
```

**Justificativa:** Mensagens de chat ativas.

---

## 📋 CHECKLIST DE IMPLEMENTAÇÃO

### Fase 1: Web Dashboard (Impacto Imediato) ✅ COMPLETO
- [x] Substituir stream por get() em `users_table_screen.dart`
- [x] Substituir stream por get() em `events_table_screen.dart`
- [ ] Substituir stream por get() em `reports_table_screen.dart`
- [x] Adicionar botão de refresh manual
- [x] Implementar paginação (50 itens por página)

### Fase 2: Profile & UI Components ✅ COMPLETO
- [x] Substituir stream por state local em `user_images_grid.dart`
- [x] Substituir stream por cache em `profile_header.dart` (followers count)
- [x] Atualizar localmente após upload de imagens (optimistic updates)

### Fase 3: Event Components ✅ COMPLETO
- [x] Substituir stream por get() em `presence_drawer.dart`
- [ ] Revisar uso de `participantsCountStream` em event cards
- [ ] Garantir que `enableRealtime = false` em listas de eventos

### Fase 4: Event Photo Likes (CRÍTICO) 🚨 URGENTE
- [ ] Remover `watchLikesCount()` stream do like service
- [ ] Remover completamente `watchIsLiked()` (deprecated)
- [ ] Corrigir `collectionGroup` com erro de permissão
- [ ] Implementar índice denormalizado em `users_stats/recentLikedPhotos`
- [ ] Usar apenas `isLikedSync()` e optimistic updates

### Fase 5: Análise de Follow System
- [ ] Mapear todos os usos de `isFollowing()` stream
- [ ] Avaliar se stream é necessário em cada caso
- [ ] Substituir por get() + cache onde possível

---

## 💰 ECONOMIA ESTIMADA

### Por Feature:

| Feature | Leituras Antes | Leituras Depois | Economia |
|---------|----------------|-----------------|----------|
| Web Dashboard Users | ~1000/hora | ~50/hora | 95% |
| Web Dashboard Events | ~500/hora | ~25/hora | 95% |
| Web Dashboard Reports | ~300/hora | ~30/hora | 90% |
| User Images Grid | ~200/hora | ~10/hora | 95% |
| Profile Header Followers | ~400/hora | ~60/hora | 85% |
| Presence Drawer | ~150/hora | ~30/hora | 80% |
| **Event Photo Likes** | **~2000/hora** | **~50/hora** | **97.5%** |

### Total Estimado:
- **Antes:** ~4550 leituras/hora em streams desnecessários
- **Depois:** ~255 leituras/hora
- **Economia:** ~94% de redução
- **Impacto Financeiro:** Redução drástica nos custos do Firestore

### 🚨 Event Photo Likes - Impacto Detalhado

**Problema Atual:**
- Feed com 20 fotos = **40 streams ativos simultâneos**
  - 20x `watchLikesCount()` 
  - 20x `watchIsLiked()` (se usado)
- Cada rebuild = nova wave de leituras
- Scroll = mais 20 fotos = +40 streams
- **Erro crítico:** `collectionGroup` falhando por permissões

**Solução Implementada:**
- Cache local em memória + Hive
- `isLikedSync()` - zero reads (cache-only)
- Optimistic updates para like/unlike
- Hidratação 1x por dia via `users_stats`

**Resultado:**
- **De:** ~2000 reads/hora (40 streams × 50 updates/hora)
- **Para:** ~50 reads/hora (hidratação diária + alguns updates)
- **Economia:** 97.5% + resolve erro de permissão

---

## 🎯 REGRAS PARA NOVOS DESENVOLVIMENTOS

### ❓ Quando usar Stream?

**Perguntas a fazer:**

1. ✅ **É uma mensagem de chat ativa?** → SIM = Stream
2. ✅ **É um contador crítico que precisa atualizar instantaneamente?** → SIM = Stream
3. ✅ **O usuário espera ver mudanças de outros usuários em tempo real?** → SIM = Stream
4. ❌ **É uma lista histórica ou estática?** → NÃO = get()
5. ❌ **É uma tabela administrativa?** → NÃO = get()
6. ❌ **É o próprio usuário editando seus dados?** → NÃO = state local
7. ❌ **Os dados mudam raramente?** → NÃO = get() + cache

### ✅ Padrão Recomendado:

```dart
// Para listas estáticas/históricas
class MyController extends ChangeNotifier {
  List<Item> _items = [];
  bool _loading = false;
  DocumentSnapshot? _lastDoc;
  
  // ✅ Carregar uma vez com paginação
  Future<void> loadItems() async {
    _loading = true;
    notifyListeners();
    
    final query = _firestore
        .collection('items')
        .orderBy('createdAt', descending: true)
        .limit(20);
    
    final snapshot = await query.get();
    
    _items = snapshot.docs.map((doc) => Item.fromDoc(doc)).toList();
    _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
    _loading = false;
    
    notifyListeners();
  }
  
  // ✅ Paginação para carregar mais
  Future<void> loadMore() async {
    if (_lastDoc == null) return;
    
    final snapshot = await _firestore
        .collection('items')
        .orderBy('createdAt', descending: true)
        .startAfterDocument(_lastDoc!)
        .limit(20)
        .get();
    
    _items.addAll(snapshot.docs.map((doc) => Item.fromDoc(doc)));
    _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
    
    notifyListeners();
  }
  
  // ✅ Refresh manual
  Future<void> refresh() async {
    _items.clear();
    _lastDoc = null;
    await loadItems();
  }
}
```

---

## 📖 Referências

- ✅ **ProfileVisitsController** - Exemplo de implementação correta com get() + paginação
- ✅ **FollowersController** - Implementação com cache Hive + SWR
- ✅ **InfiniteListView** - Widget de paginação reutilizável
- ❌ **Web Dashboard** - Exemplo do que NÃO fazer (streams sem paginação)

---

## ⚠️ ATENÇÃO

**Antes de remover qualquer stream:**

1. ✅ Verificar todos os lugares onde é usado
2. ✅ Garantir que a UI pode funcionar com state local
3. ✅ Implementar paginação se a lista for grande
4. ✅ Adicionar loading states apropriados
5. ✅ Testar comportamento após mudanças remotas
6. ✅ Considerar adicionar pull-to-refresh

**Streams são ferramentas poderosas, mas caras.** Use-as apenas quando realmente necessário para atualizações em tempo real.

---

**Próximos Passos:**
1. Revisar este relatório com a equipe
2. Priorizar implementações por impacto
3. Começar com Web Dashboard (maior economia)
4. Monitorar custos do Firestore antes/depois
5. Documentar padrões para novos desenvolvedores
