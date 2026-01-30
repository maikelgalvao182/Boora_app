import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/features/profile/presentation/controllers/followers_cache_service.dart';

/// ✅ OTIMIZADO: Controller de seguidores com paginação, batch queries e cache Hive
/// 
/// Arquitetura de cache (Fase 2):
/// ┌─────────────────────────────────────────────────────────────┐
/// │  FollowersCacheService (Hive)   │  UserCacheService (Memory) │
/// │  - Index: followers/following   │  - Users: UserModel        │
/// │  - TTL: 20 min                  │  - TTL: 10 min             │
/// │  - Persiste entre sessões       │  - Rápido, sem I/O         │
/// └─────────────────────────────────────────────────────────────┘
/// 
/// Fluxo SWR (Stale-While-Revalidate):
/// 1. Mostra cache Hive instantaneamente (se disponível)
/// 2. Se cache < 5 min, não revalida
/// 3. Se cache > 5 min, revalida em background
/// 4. Atualiza UI quando dados frescos chegam
/// 
/// Economia estimada: 95%+ menos reads
/// Antes: 200 reads para 100 seguidores (N+1)
/// Depois: 0 reads (cache hit) ou ~13 reads (cache miss)
class FollowersController {
  FollowersController({required this.userId});

  final String userId;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FollowersCacheService _cache = FollowersCacheService.instance;

  // ========== State ==========
  final ValueNotifier<List<User>> followers = ValueNotifier(const []);
  final ValueNotifier<List<User>> following = ValueNotifier(const []);

  final ValueNotifier<bool> isLoadingFollowers = ValueNotifier(false);
  final ValueNotifier<bool> isLoadingFollowing = ValueNotifier(false);

  // ✅ NOVO: Loading para "carregar mais"
  final ValueNotifier<bool> isLoadingMoreFollowers = ValueNotifier(false);
  final ValueNotifier<bool> isLoadingMoreFollowing = ValueNotifier(false);

  final ValueNotifier<Object?> followersError = ValueNotifier(null);
  final ValueNotifier<Object?> followingError = ValueNotifier(null);

  // ✅ NOVO: Controle de paginação
  final ValueNotifier<bool> hasMoreFollowers = ValueNotifier(true);
  final ValueNotifier<bool> hasMoreFollowing = ValueNotifier(true);

  // ========== Paginação ==========
  static const int _pageSize = 30;

  DocumentSnapshot? _lastFollowerDoc;
  DocumentSnapshot? _lastFollowingDoc;

  // ========== Request IDs (race condition protection) ==========
  int _followersRequestId = 0;
  int _followingRequestId = 0;

  /// Inicializa carregando primeira página de ambas as listas
  /// Usa Stale-While-Revalidate: mostra cache instantâneo, revalida em background
  void initialize() {
    _loadFollowersWithSWR();
    _loadFollowingWithSWR();
  }

  // ========== FOLLOWERS ==========

  /// ✅ SWR: Stale-While-Revalidate para followers
  Future<void> _loadFollowersWithSWR() async {
    final requestId = ++_followersRequestId;
    _setNotifierValue(followersError, null);
    _lastFollowerDoc = null;

    // 1. Tentar mostrar cache instantaneamente
    final cached = await _cache.getFollowersIndex(userId);
    
    if (cached != null && cached.ids.isNotEmpty) {
      // Cache HIT - mostrar imediatamente
      _setNotifierValue(hasMoreFollowers, cached.hasMore);
      
      // Construir Users a partir do cache global (UserCacheService)
      final users = await _buildUsersFromCachedIndex(cached.ids, requestId, isFollowers: true);
      
      if (requestId != _followersRequestId) return;
      
      if (users.isNotEmpty) {
        _setNotifierValue(followers, users);
        debugPrint('📦 [FollowersController] Cache HIT: ${users.length} seguidores (instant, age: ${cached.ageMinutes}min)');
        
        // Se cache está fresco (< 5min), não revalidar
        if (cached.isFresh) {
          debugPrint('📦 [FollowersController] Cache fresh, skipping revalidation');
          return;
        }
        
        // Cache stale - revalidar em background (sem loading indicator)
        debugPrint('📦 [FollowersController] Cache stale, revalidating in background...');
        unawaited(_revalidateFollowers(requestId));
        return;
      }
    }
    
    // 2. Cache MISS - carregar do Firestore com loading
    _setNotifierValue(isLoadingFollowers, true);
    await _loadFollowersFromFirestore(requestId);
  }

  /// Revalida followers em background (SWR)
  Future<void> _revalidateFollowers(int requestId) async {
    try {
      final snapshot = await _firestore
          .collection('Users')
          .doc(userId)
          .collection('followers')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      if (requestId != _followersRequestId) return;

      // Converter docs para index items (ID + createdAt)
      final items = _docsToIndexItems(snapshot.docs);
      final hasMore = snapshot.docs.length >= _pageSize;
      
      // Salvar index no cache Hive
      await _cache.saveFollowersIndex(userId, items, hasMore: hasMore);
      
      // Construir users e atualizar UI
      final users = await _buildUsersFromDocs(snapshot.docs, requestId, isFollowers: true);
      
      if (requestId != _followersRequestId) return;

      _lastFollowerDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _setNotifierValue(hasMoreFollowers, hasMore);
      _setNotifierValue(followers, users);

      debugPrint('✅ [FollowersController] Revalidated: ${users.length} seguidores');
    } catch (e) {
      debugPrint('⚠️ [FollowersController] Revalidation failed: $e');
      // Não mostra erro - mantém dados do cache
    }
  }

  /// ✅ OTIMIZADO: Carrega primeira página do Firestore
  Future<void> _loadFollowersFromFirestore(int requestId) async {
    try {
      final snapshot = await _firestore
          .collection('Users')
          .doc(userId)
          .collection('followers')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      if (requestId != _followersRequestId) return;

      // Converter docs para index items (ID + createdAt)
      final items = _docsToIndexItems(snapshot.docs);
      final hasMore = snapshot.docs.length >= _pageSize;
      
      // Salvar index no cache Hive
      await _cache.saveFollowersIndex(userId, items, hasMore: hasMore);

      final users = await _buildUsersFromDocs(snapshot.docs, requestId, isFollowers: true);

      if (requestId != _followersRequestId) return;

      _lastFollowerDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _setNotifierValue(hasMoreFollowers, hasMore);
      _setNotifierValue(followers, users);
      _setNotifierValue(isLoadingFollowers, false);

      debugPrint('✅ [FollowersController] Loaded: ${users.length} seguidores');
    } catch (e) {
      if (requestId != _followersRequestId) return;
      debugPrint('❌ [FollowersController] Erro ao carregar seguidores: $e');
      _setNotifierValue(followersError, e);
      _setNotifierValue(isLoadingFollowers, false);
    }
  }

  /// ✅ NOVO: Carrega próxima página de seguidores
  Future<void> loadMoreFollowers() async {
    if (isLoadingMoreFollowers.value || !hasMoreFollowers.value || _lastFollowerDoc == null) {
      return;
    }

    final requestId = ++_followersRequestId;
    _setNotifierValue(isLoadingMoreFollowers, true);

    try {
      final snapshot = await _firestore
          .collection('Users')
          .doc(userId)
          .collection('followers')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastFollowerDoc!)
          .limit(_pageSize)
          .get();

      if (requestId != _followersRequestId) return;

      final newUsers = await _buildUsersFromDocs(snapshot.docs, requestId, isFollowers: true);

      if (requestId != _followersRequestId) return;

      // Atualizar cache com index acumulado
      final existingCache = await _cache.getFollowersIndex(userId);
      final existingItems = existingCache?.items ?? [];
      final newItems = _docsToIndexItems(snapshot.docs);
      final allItems = [...existingItems, ...newItems];
      
      final hasMore = snapshot.docs.length >= _pageSize;
      await _cache.saveFollowersIndex(userId, allItems, hasMore: hasMore);

      _lastFollowerDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _setNotifierValue(hasMoreFollowers, hasMore);
      _setNotifierValue(followers, [...followers.value, ...newUsers]);
      _setNotifierValue(isLoadingMoreFollowers, false);

      debugPrint('✅ [FollowersController] Carregados mais ${newUsers.length} seguidores');
    } catch (e) {
      if (requestId != _followersRequestId) return;
      debugPrint('❌ [FollowersController] Erro ao carregar mais seguidores: $e');
      _setNotifierValue(isLoadingMoreFollowers, false);
    }
  }

  /// Pull-to-refresh: invalida cache e recarrega
  Future<void> refreshFollowers() async {
    await _cache.invalidateFollowers(userId);
    final requestId = ++_followersRequestId;
    _setNotifierValue(isLoadingFollowers, true);
    _lastFollowerDoc = null;
    await _loadFollowersFromFirestore(requestId);
  }

  // ========== FOLLOWING ==========

  /// ✅ SWR: Stale-While-Revalidate para following
  Future<void> _loadFollowingWithSWR() async {
    final requestId = ++_followingRequestId;
    _setNotifierValue(followingError, null);
    _lastFollowingDoc = null;

    // 1. Tentar mostrar cache instantaneamente
    final cached = await _cache.getFollowingIndex(userId);
    
    if (cached != null && cached.ids.isNotEmpty) {
      // Cache HIT - mostrar imediatamente
      _setNotifierValue(hasMoreFollowing, cached.hasMore);
      
      // Construir Users a partir do cache global (UserCacheService)
      final users = await _buildUsersFromCachedIndex(cached.ids, requestId, isFollowers: false);
      
      if (requestId != _followingRequestId) return;
      
      if (users.isNotEmpty) {
        _setNotifierValue(following, users);
        debugPrint('📦 [FollowersController] Cache HIT: ${users.length} seguindo (instant, age: ${cached.ageMinutes}min)');
        
        // Se cache está fresco (< 5min), não revalidar
        if (cached.isFresh) {
          debugPrint('📦 [FollowersController] Cache fresh, skipping revalidation');
          return;
        }
        
        // Cache stale - revalidar em background (sem loading indicator)
        debugPrint('📦 [FollowersController] Cache stale, revalidating in background...');
        unawaited(_revalidateFollowing(requestId));
        return;
      }
    }
    
    // 2. Cache MISS - carregar do Firestore com loading
    _setNotifierValue(isLoadingFollowing, true);
    await _loadFollowingFromFirestore(requestId);
  }

  /// Revalida following em background (SWR)
  Future<void> _revalidateFollowing(int requestId) async {
    try {
      final snapshot = await _firestore
          .collection('Users')
          .doc(userId)
          .collection('following')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      if (requestId != _followingRequestId) return;

      // Converter docs para index items (ID + createdAt)
      final items = _docsToIndexItems(snapshot.docs);
      final hasMore = snapshot.docs.length >= _pageSize;
      
      // Salvar index no cache Hive
      await _cache.saveFollowingIndex(userId, items, hasMore: hasMore);
      
      // Construir users e atualizar UI
      final users = await _buildUsersFromDocs(snapshot.docs, requestId, isFollowers: false);
      
      if (requestId != _followingRequestId) return;

      _lastFollowingDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _setNotifierValue(hasMoreFollowing, hasMore);
      _setNotifierValue(following, users);

      debugPrint('✅ [FollowersController] Revalidated: ${users.length} seguindo');
    } catch (e) {
      debugPrint('⚠️ [FollowersController] Revalidation failed: $e');
      // Não mostra erro - mantém dados do cache
    }
  }

  /// ✅ OTIMIZADO: Carrega primeira página de seguindo do Firestore
  Future<void> _loadFollowingFromFirestore(int requestId) async {
    try {
      final snapshot = await _firestore
          .collection('Users')
          .doc(userId)
          .collection('following')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      if (requestId != _followingRequestId) return;

      // Converter docs para index items (ID + createdAt)
      final items = _docsToIndexItems(snapshot.docs);
      final hasMore = snapshot.docs.length >= _pageSize;
      
      // Salvar index no cache Hive
      await _cache.saveFollowingIndex(userId, items, hasMore: hasMore);

      final users = await _buildUsersFromDocs(snapshot.docs, requestId, isFollowers: false);

      if (requestId != _followingRequestId) return;

      _lastFollowingDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _setNotifierValue(hasMoreFollowing, hasMore);
      _setNotifierValue(following, users);
      _setNotifierValue(isLoadingFollowing, false);

      debugPrint('✅ [FollowersController] Loaded: ${users.length} seguindo');
    } catch (e) {
      if (requestId != _followingRequestId) return;
      debugPrint('❌ [FollowersController] Erro ao carregar seguindo: $e');
      _setNotifierValue(followingError, e);
      _setNotifierValue(isLoadingFollowing, false);
    }
  }

  /// ✅ NOVO: Carrega próxima página de seguindo
  Future<void> loadMoreFollowing() async {
    if (isLoadingMoreFollowing.value || !hasMoreFollowing.value || _lastFollowingDoc == null) {
      return;
    }

    final requestId = ++_followingRequestId;
    _setNotifierValue(isLoadingMoreFollowing, true);

    try {
      final snapshot = await _firestore
          .collection('Users')
          .doc(userId)
          .collection('following')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastFollowingDoc!)
          .limit(_pageSize)
          .get();

      if (requestId != _followingRequestId) return;

      final newUsers = await _buildUsersFromDocs(snapshot.docs, requestId, isFollowers: false);

      if (requestId != _followingRequestId) return;

      // Atualizar cache com index acumulado
      final existingCache = await _cache.getFollowingIndex(userId);
      final existingItems = existingCache?.items ?? [];
      final newItems = _docsToIndexItems(snapshot.docs);
      final allItems = [...existingItems, ...newItems];
      
      final hasMore = snapshot.docs.length >= _pageSize;
      await _cache.saveFollowingIndex(userId, allItems, hasMore: hasMore);

      _lastFollowingDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _setNotifierValue(hasMoreFollowing, hasMore);
      _setNotifierValue(following, [...following.value, ...newUsers]);
      _setNotifierValue(isLoadingMoreFollowing, false);

      debugPrint('✅ [FollowersController] Carregados mais ${newUsers.length} seguindo');
    } catch (e) {
      if (requestId != _followingRequestId) return;
      debugPrint('❌ [FollowersController] Erro ao carregar mais seguindo: $e');
      _setNotifierValue(isLoadingMoreFollowing, false);
    }
  }

  /// Pull-to-refresh: invalida cache e recarrega
  Future<void> refreshFollowing() async {
    await _cache.invalidateFollowing(userId);
    final requestId = ++_followingRequestId;
    _setNotifierValue(isLoadingFollowing, true);
    _lastFollowingDoc = null;
    await _loadFollowingFromFirestore(requestId);
  }

  // ========== BATCH USER LOADING ==========

  /// ✅ Converte documentos Firestore para index items (ID + createdAt)
  List<FollowerIndexItem> _docsToIndexItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.map((doc) {
      final data = doc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      return FollowerIndexItem(
        id: doc.id,
        createdAt: createdAt?.toDate() ?? DateTime.now(),
      );
    }).toList();
  }

  /// ✅ Constrói Users a partir do index cached (IDs)
  /// 
  /// Fluxo otimizado:
  ///   1. Busca users_preview do cache Hive (TTL 30min)
  ///   2. Se faltam users, busca do Firestore via batch whereIn (chunks de 10)
  ///   3. NÃO faz 30 gets paralelos - usa batch
  Future<List<User>> _buildUsersFromCachedIndex(
    List<String> ids,
    int requestId, {
    required bool isFollowers,
  }) async {
    if (ids.isEmpty) return const [];

    // 1. Tentar obter do cache Hive (users_preview, TTL 30min)
    final cachedUsers = await _cache.getUsersPreviewFromCache(ids);
    
    // IDs não encontrados no cache
    final missingIds = ids.where((id) => !cachedUsers.containsKey(id)).toList();
    
    Map<String, Map<String, dynamic>> allUsersData = {...cachedUsers};
    
    // 2. Se há IDs faltando, buscar do Firestore via batch
    if (missingIds.isNotEmpty) {
      debugPrint('📦 [FollowersController] Cache parcial: ${cachedUsers.length}/${ids.length}, buscando ${missingIds.length} de users_preview');
      
      // ✅ UserRepository.getUsersByIds() já usa:
      //    - users_preview collection (leve, ~500 bytes)
      //    - Batch whereIn chunks de 10 (não 30 gets paralelos!)
      final freshUsers = await _cache.fetchMissingUsersPreview(missingIds);
      
      // Verificar race condition
      if (isFollowers && requestId != _followersRequestId) return const [];
      if (!isFollowers && requestId != _followingRequestId) return const [];
      
      allUsersData.addAll(freshUsers);
    }

    // 3. Construir lista de Users mantendo ordem original
    final users = <User>[];
    for (final id in ids) {
      final data = allUsersData[id];
      if (data == null) continue;

      final normalized = <String, dynamic>{
        ...data,
        'userId': id,
      };
      users.add(User.fromDocument(normalized).copyWith(distance: null));
    }

    return users;
  }

  /// ✅ OTIMIZADO: Constrói lista de Users a partir de docs Firestore
  ///
  /// ✅ Usa users_preview collection (não Users completo)
  /// ✅ Batch com whereIn chunks de 10 (não 30 gets paralelos)
  /// 
  /// Antes: N queries individuais (getUserById) = N reads
  /// Depois: ceil(N/10) queries batch (whereIn) = ~3 reads para 30 users
  Future<List<User>> _buildUsersFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int requestId, {
    required bool isFollowers,
  }) async {
    final ids = docs.map((doc) => doc.id).toList();
    if (ids.isEmpty) {
      return const [];
    }

    // ✅ OTIMIZAÇÃO: Batch query via users_preview
    // Isso já salva no cache Hive automaticamente
    final usersMap = await _cache.fetchMissingUsersPreview(ids);

    // Verificar race condition
    if (isFollowers && requestId != _followersRequestId) {
      return const [];
    }
    if (!isFollowers && requestId != _followingRequestId) {
      return const [];
    }

    final users = <User>[];
    for (final id in ids) {
      final data = usersMap[id];
      if (data == null) {
        debugPrint('⚠️ [FollowersController] Usuário $id não encontrado no batch');
        continue;
      }

      final normalized = <String, dynamic>{
        ...data,
        'userId': id,
      };
      users.add(User.fromDocument(normalized).copyWith(distance: null));
    }

    return users;
  }

  // ========== OPTIMISTIC REMOVAL ==========

  /// Remove um usuário da lista de "Seguindo" de forma otimista (instant UI)
  /// Usado quando o usuário clica em "Deixar de seguir" na aba Seguindo
  void optimisticRemoveFromFollowing(String targetUserId) {
    final current = following.value;
    final filtered = current.where((u) => u.userId != targetUserId).toList();
    if (filtered.length != current.length) {
      following.value = filtered;
      debugPrint('🗑️ [FollowersController] Removed $targetUserId from following (optimistic)');
      
      // Também invalida o cache para garantir consistência no próximo refresh
      _cache.invalidateFollowing(userId);
    }
  }

  // ========== HELPERS ==========

  void _setNotifierValue<T>(ValueNotifier<T> notifier, T value) {
    if (notifier.value == value) return;
    scheduleMicrotask(() {
      if (notifier.value != value) {
        notifier.value = value;
      }
    });
  }

  void dispose() {
    // ✅ OTIMIZADO: Não há mais streams para cancelar
    followers.dispose();
    following.dispose();
    isLoadingFollowers.dispose();
    isLoadingFollowing.dispose();
    isLoadingMoreFollowers.dispose();
    isLoadingMoreFollowing.dispose();
    followersError.dispose();
    followingError.dispose();
    hasMoreFollowers.dispose();
    hasMoreFollowing.dispose();
  }
}
