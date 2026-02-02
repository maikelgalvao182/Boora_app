import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_feed_scope.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/unified_feed_item.dart';
import 'package:partiu/features/event_photo_feed/data/repositories/event_photo_repository.dart';
import 'package:partiu/features/event_photo_feed/domain/services/event_photo_cache_service.dart';
import 'package:partiu/features/event_photo_feed/domain/services/event_photo_likes_cache_service.dart';
import 'package:partiu/features/event_photo_feed/domain/services/feed_metrics_service.dart';
import 'package:partiu/features/event_photo_feed/domain/services/feed_preloader.dart';
import 'package:partiu/features/feed/data/models/activity_feed_item_model.dart';
import 'package:partiu/features/feed/data/repositories/activity_feed_repository.dart';
import 'package:partiu/core/services/cache/media_cache_manager.dart';

class EventPhotoFeedState {
  const EventPhotoFeedState({
    required this.items,
    required this.activityItems,
    required this.cursor,
  required this.activeCursor,
  required this.pendingCursor,
    required this.hasMore,
    required this.isLoadingMore,
    required this.lastUpdatedAt,
  });

  final List<EventPhotoModel> items;
  final List<ActivityFeedItemModel> activityItems;
  
  /// Retorna lista unificada ordenada por data (mais recente primeiro)
  List<UnifiedFeedItem> get unifiedItems {
    final unified = <UnifiedFeedItem>[
      ...items.map(UnifiedFeedItem.fromPhoto),
      ...activityItems.map(UnifiedFeedItem.fromActivity),
    ];
    return unified.sortedByDate();
  }
  
  // cursor antigo (compat) - mantém o último cursor "dominante".
  final DocumentSnapshot<Map<String, dynamic>>? cursor;

  // cursores reais (para merge de active + under_review do autor)
  final DocumentSnapshot<Map<String, dynamic>>? activeCursor;
  final DocumentSnapshot<Map<String, dynamic>>? pendingCursor;
  final bool hasMore;
  final bool isLoadingMore;
  final DateTime? lastUpdatedAt;

  factory EventPhotoFeedState.initial() => const EventPhotoFeedState(
        items: [],
        activityItems: [],
        cursor: null,
  activeCursor: null,
  pendingCursor: null,
        hasMore: true,
        isLoadingMore: false,
        lastUpdatedAt: null,
      );

  EventPhotoFeedState copyWith({
    List<EventPhotoModel>? items,
    List<ActivityFeedItemModel>? activityItems,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    DocumentSnapshot<Map<String, dynamic>>? activeCursor,
    DocumentSnapshot<Map<String, dynamic>>? pendingCursor,
    bool? hasMore,
    bool? isLoadingMore,
    DateTime? lastUpdatedAt,
  }) {
    return EventPhotoFeedState(
      items: items ?? this.items,
      activityItems: activityItems ?? this.activityItems,
      cursor: cursor ?? this.cursor,
      activeCursor: activeCursor ?? this.activeCursor,
      pendingCursor: pendingCursor ?? this.pendingCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }
}

final eventPhotoRepositoryProvider = Provider<EventPhotoRepository>((ref) {
  final cacheService = ref.read(eventPhotoCacheServiceProvider);
  return EventPhotoRepository(cacheService: cacheService);
});

final activityFeedRepositoryProvider = Provider<ActivityFeedRepository>((ref) {
  return ActivityFeedRepository();
});

final eventPhotoFeedControllerProvider =
    AsyncNotifierProviderFamily<EventPhotoFeedController, EventPhotoFeedState, EventPhotoFeedScope>(
  EventPhotoFeedController.new,
);

class EventPhotoFeedController extends FamilyAsyncNotifier<EventPhotoFeedState, EventPhotoFeedScope> {
  static const int _pageSize = 20;
  
  // Removido TTL fixo - agora usa FeedTtlConfig.getMemoryTtl(scope)
  
  /// Timestamp do último refresh silencioso por scope (debounce)
  static final Map<String, DateTime> _lastSilentRefresh = {};

  EventPhotoRepository get _repo => ref.read(eventPhotoRepositoryProvider);
  EventPhotoCacheService get _cache => ref.read(eventPhotoCacheServiceProvider);
  ActivityFeedRepository get _activityRepo => ref.read(activityFeedRepositoryProvider);
  EventPhotoLikesCacheService get _likesCache => ref.read(eventPhotoLikesCacheServiceProvider);
  FeedMetricsService get _metrics => ref.read(feedMetricsServiceProvider);

  @override
  Future<EventPhotoFeedState> build(EventPhotoFeedScope scope) async {
    debugPrint('🎯 [EventPhotoFeedController.build] Iniciando build - scope: $scope');
    
    // Inicia tracking de métricas
    final tracker = _metrics.startFeedLoad(scope);

    await _cache.initialize();
    
    // Inicializa e hidrata cache de likes (uma vez por sessão/dia)
    await _likesCache.initialize();
    // Dispara hidratação em background (não bloqueia o build)
    Future.microtask(() => _likesCache.hydrateIfNeeded());
    
    // CACHE-FIRST: Verifica se o FeedPreloader tem cache fresco para este scope
    final preloader = FeedPreloader.instance;
    final preloadedPhotos = preloader.getCachedPhotos(scope);
    final preloadedActivities = preloader.getCachedActivities(scope);
    
    if (preloadedPhotos != null && preloadedPhotos.isNotEmpty) {
      debugPrint('📦 [EventPhotoFeedController.build] Usando cache do FeedPreloader para $scope: ${preloadedPhotos.length} photos, ${preloadedActivities?.length ?? 0} activities');
      
      // Registra cache hit
      await tracker.finish(docsRead: 0, cacheHit: true);

      // Atualiza likes em background para itens visíveis
      Future.microtask(() => _likesCache.fetchLikesForPhotos(
            preloadedPhotos.map((item) => item.id).toList(growable: false),
          ));
      
      // Dispara refresh silencioso em background (com debounce)
      Future.microtask(_refreshSilentlyWithDebounce);
      
      return EventPhotoFeedState.initial().copyWith(
        items: preloadedPhotos,
        activityItems: preloadedActivities ?? [],
        hasMore: true,
        lastUpdatedAt: DateTime.now(),
      );
    }
    
    // Fallback para cache do EventPhotoCacheService
    final cachedItems = _cache.getCachedFeed(scope);
    if (cachedItems != null && cachedItems.isNotEmpty) {
      // Registra cache hit
      await tracker.finish(docsRead: 0, cacheHit: true);

      // Atualiza likes em background para itens visíveis
      Future.microtask(() => _likesCache.fetchLikesForPhotos(
            cachedItems.map((item) => item.id).toList(growable: false),
          ));
      
      Future.microtask(_refreshSilentlyWithDebounce);
      return EventPhotoFeedState.initial().copyWith(
        items: cachedItems,
        hasMore: true,
        lastUpdatedAt: DateTime.now(),
      );
    }
    
    // TTL in-memory: se já carregou recentemente e ainda é válido, mantém.
    // Usa TTL específico por scope
    final ttl = FeedTtlConfig.getMemoryTtl(scope);
    final existing = state.valueOrNull;
    if (existing != null && existing.lastUpdatedAt != null) {
      final age = DateTime.now().difference(existing.lastUpdatedAt!);
      if (age < ttl && existing.items.isNotEmpty) {
        debugPrint('✅ [EventPhotoFeedController.build] Cache válido (age: ${age.inSeconds}s, ttl: ${ttl.inSeconds}s)');
        await tracker.finish(docsRead: 0, cacheHit: true);
        return existing;
      }
    }

    debugPrint('🔄 [EventPhotoFeedController.build] Carregando dados do Firestore...');
    final userId = _safeUserId();
    debugPrint('👤 [EventPhotoFeedController.build] userId: $userId');
    
    try {
      // Busca EventPhotos
      final page = userId == null
          ? await _repo.fetchFeedPage(scope: scope, limit: _pageSize)
          : await _repo.fetchFeedPageWithOwnPending(
              scope: scope,
              limit: _pageSize,
              currentUserId: userId,
            );
      
      // Busca ActivityFeed items (global por enquanto)
      final activityItems = await _fetchActivityFeed(scope);
      
      // Registra métricas de load
      final docsRead = page.items.length + activityItems.length;
      await tracker.finish(docsRead: docsRead, cacheHit: false);
      
      debugPrint('✅ [EventPhotoFeedController.build] Dados carregados: ${page.items.length} photos, ${activityItems.length} activities');

      final nextState = EventPhotoFeedState.initial().copyWith(
        items: page.items,
        activityItems: activityItems,
        cursor: page.nextCursor,
        activeCursor: page.activeCursor,
        pendingCursor: page.pendingCursor,
        hasMore: page.hasMore,
        lastUpdatedAt: DateTime.now(),
      );

      await _cache.setCachedFeed(scope, page.items);
      // Atualiza likes em background para itens visíveis
      Future.microtask(() => _likesCache.fetchLikesForPhotos(
            page.items.map((item) => item.id).toList(growable: false),
          ));
      await _prefetchInitialThumbnails(page.items);
      return nextState;
    } catch (e, stack) {
      print('❌ [EventPhotoFeedController.build] ERRO ao carregar feed: $e');
      print('📚 Stack trace: $stack');
      rethrow;
    }
  }

  /// Verifica debounce antes de disparar refresh silencioso
  Future<void> _refreshSilentlyWithDebounce() async {
    final scope = arg;
    final scopeKey = _cache.scopeKey(scope);
    final debounce = FeedTtlConfig.getRefreshDebounce(scope);
    
    final lastRefresh = _lastSilentRefresh[scopeKey];
    if (lastRefresh != null) {
      final elapsed = DateTime.now().difference(lastRefresh);
      if (elapsed < debounce) {
        debugPrint('⏳ [_refreshSilentlyWithDebounce] Debounce ativo para $scopeKey '
            '(${elapsed.inSeconds}s < ${debounce.inSeconds}s)');
        return;
      }
    }
    
    _lastSilentRefresh[scopeKey] = DateTime.now();
    await _refreshSilently();
  }

  Future<void> _refreshSilently() async {
    final scope = arg;
    final userId = _safeUserId();

    try {
      final page = userId == null
          ? await _repo.fetchFeedPage(scope: scope, limit: _pageSize)
          : await _repo.fetchFeedPageWithOwnPending(
              scope: scope,
              limit: _pageSize,
              currentUserId: userId,
            );
      
      // Busca ActivityFeed items
      final activityItems = await _fetchActivityFeed(scope);

      final nextState = EventPhotoFeedState.initial().copyWith(
        items: page.items,
        activityItems: activityItems,
        cursor: page.nextCursor,
        activeCursor: page.activeCursor,
        pendingCursor: page.pendingCursor,
        hasMore: page.hasMore,
        lastUpdatedAt: DateTime.now(),
      );
      state = AsyncData(nextState);
      await _cache.setCachedFeed(scope, page.items);
      await _prefetchInitialThumbnails(page.items);
    } catch (_) {
      // Silencioso para não impactar a UI
    }
  }

  String? _safeUserId() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.trim().isEmpty) return null;
      return uid;
    } catch (_) {
      return null;
    }
  }

  /// Busca IDs dos usuários seguidos pelo usuário atual
  Future<List<String>> _fetchFollowingIds(String userId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('following')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
      
      return snap.docs.map((doc) => doc.id).toList(growable: false);
    } catch (e) {
      debugPrint('❌ [EventPhotoFeedController._fetchFollowingIds] Erro: $e');
      return [];
    }
  }

  /// Busca ActivityFeed items baseado no scope
  Future<List<ActivityFeedItemModel>> _fetchActivityFeed(EventPhotoFeedScope scope) async {
    try {
      final userId = _safeUserId();
      
      // Para scope User, busca apenas do usuário específico
      if (scope is EventPhotoFeedScopeUser) {
        return await _activityRepo.fetchUserFeed(
          userId: scope.userId,
          limit: _pageSize,
        );
      }
      
      // Para scope Following, busca de todos os usuários seguidos
      if (scope is EventPhotoFeedScopeFollowing && userId != null) {
        final followingIds = await _fetchFollowingIds(userId);
        if (followingIds.isEmpty) {
          debugPrint('ℹ️ [_fetchActivityFeed] Usuário não segue ninguém');
          return [];
        }
        
        return await _activityRepo.fetchFollowingFeed(
          userIds: followingIds,
          limit: _pageSize,
        );
      }
      
      // Para scope Global ou outros, busca global
      return await _activityRepo.fetchGlobalFeed(limit: _pageSize);
    } catch (e) {
      debugPrint('⚠️ [EventPhotoFeedController] Erro ao buscar ActivityFeed: $e');
      return [];
    }
  }

  Future<void> refresh() async {
    debugPrint('🔄 [EventPhotoFeedController.refresh] Iniciando refresh...');
    
    final current = state.valueOrNull;
    final scope = arg;
    
    // Se não tem dados carregados ou lista vazia, faz refresh completo
    if (current == null || current.items.isEmpty) {
      debugPrint('📥 [refresh] Lista vazia, fazendo refresh completo');
      return _refreshFull();
    }
    
    // Tenta refresh incremental
    final topCreatedAt = current.items.first.createdAt;
    if (topCreatedAt == null) {
      debugPrint('⚠️ [refresh] topCreatedAt nulo, fazendo refresh completo');
      return _refreshFull();
    }
    
    // Para scope Following, faz refresh completo (lógica de chunks é complexa)
    if (scope is EventPhotoFeedScopeFollowing) {
      debugPrint('👥 [refresh] Scope Following, fazendo refresh completo');
      return _refreshFull();
    }
    
    debugPrint('🆕 [refresh] Tentando refresh incremental desde ${topCreatedAt.toDate()}');
    
    try {
      final userId = _safeUserId();
      
      // Busca novos posts em paralelo
      final activeNewFuture = _repo.fetchActiveNewerThan(
        scope: scope,
        newerThan: topCreatedAt,
        limit: 20,
      );
      
      final underReviewNewFuture = userId != null
          ? _repo.fetchUnderReviewMineNewerThan(
              scope: scope,
              userId: userId,
              newerThan: topCreatedAt,
              limit: 20,
            )
          : Future.value(<EventPhotoModel>[]);
      
      // Busca novos ActivityFeed items
      final activityNewFuture = _fetchActivityFeedNewerThan(scope, topCreatedAt);
      
      final results = await Future.wait([
        activeNewFuture,
        underReviewNewFuture,
        activityNewFuture,
      ]);
      
      final newActivePhotos = results[0] as List<EventPhotoModel>;
      final newUnderReviewPhotos = results[1] as List<EventPhotoModel>;
      final newActivities = results[2] as List<ActivityFeedItemModel>;
      
      final totalNewPhotos = newActivePhotos.length + newUnderReviewPhotos.length;
      debugPrint('✅ [refresh] Encontrados: $totalNewPhotos novos photos, ${newActivities.length} novos activities');
      
      // Se não tem nada novo, apenas atualiza timestamp
      if (totalNewPhotos == 0 && newActivities.isEmpty) {
        state = AsyncData(current.copyWith(lastUpdatedAt: DateTime.now()));
        debugPrint('📭 [refresh] Nenhum post novo');
        return;
      }
      
      // Merge e dedupe photos por ID
      final photosById = <String, EventPhotoModel>{};
      for (final photo in newActivePhotos) {
        photosById[photo.id] = photo;
      }
      for (final photo in newUnderReviewPhotos) {
        photosById[photo.id] = photo;
      }
      for (final photo in current.items) {
        photosById.putIfAbsent(photo.id, () => photo);
      }
      
      // Ordena por createdAt desc
      final mergedPhotos = photosById.values.toList()
        ..sort((a, b) {
          final aTs = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bTs = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return bTs.compareTo(aTs);
        });
      
      // Merge e dedupe activities por ID
      final activitiesById = <String, ActivityFeedItemModel>{};
      for (final activity in newActivities) {
        activitiesById[activity.id] = activity;
      }
      for (final activity in current.activityItems) {
        activitiesById.putIfAbsent(activity.id, () => activity);
      }
      
      final mergedActivities = activitiesById.values.toList()
        ..sort((a, b) {
          final aTs = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bTs = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return bTs.compareTo(aTs);
        });
      
      debugPrint('📊 [refresh] Após merge: ${mergedPhotos.length} photos, ${mergedActivities.length} activities');
      
      // Atualiza state
      state = AsyncData(current.copyWith(
        items: mergedPhotos,
        activityItems: mergedActivities,
        lastUpdatedAt: DateTime.now(),
      ));
      
      // Atualiza cache (limita a 60 items para não crescer infinito)
      await _cache.setCachedFeed(scope, mergedPhotos.take(60).toList());
      
      // Invalida cache do preloader para este scope
      FeedPreloader.instance.invalidateCacheFor(scope);
      
    } catch (e, stack) {
      debugPrint('❌ [refresh] Erro no refresh incremental: $e');
      debugPrint('📚 Stack: $stack');
      // Fallback para refresh completo em caso de erro
      return _refreshFull();
    }
  }

  /// Refresh completo - recarrega a primeira página do zero
  /// 
  /// Usado quando:
  /// - Lista está vazia
  /// - Scope é Following (chunks complexos)
  /// - Erro no refresh incremental
  /// - Forçado pelo usuário
  /// 
  /// ⚠️ IMPORTANTE: Não define AsyncLoading durante refresh para evitar shimmer.
  /// O shimmer só deve aparecer no carregamento inicial (lista vazia).
  Future<void> _refreshFull() async {
    debugPrint('🔄 [EventPhotoFeedController._refreshFull] Iniciando refresh completo...');
    
    final scope = arg;
    final current = state.valueOrNull;
    
    // Invalida o cache do preloader apenas para este scope
    FeedPreloader.instance.invalidateCacheFor(scope);
    
    // ⚠️ CORREÇÃO RACE CONDITION:
    // Se já tem dados (fotos OU activities), NÃO define AsyncLoading (evita shimmer durante pull-to-refresh)
    // Shimmer só aparece no carregamento inicial (lista vazia)
    final hasExistingData = current != null && 
        (current.items.isNotEmpty || current.activityItems.isNotEmpty);
    
    if (!hasExistingData) {
      // Apenas no carregamento inicial, mostra shimmer
      state = const AsyncLoading();
    }
    
    final userId = _safeUserId();
    debugPrint('👤 [_refreshFull] userId: $userId, scope: $scope');
    
    try {
      final page = userId == null
        ? await _repo.fetchFeedPage(scope: scope, limit: _pageSize)
        : await _repo.fetchFeedPageWithOwnPending(
          scope: scope,
          limit: _pageSize,
          currentUserId: userId,
        );
      
      // Busca ActivityFeed items
      final activityItems = await _fetchActivityFeed(scope);
      
      debugPrint('✅ [_refreshFull] Refresh completo: ${page.items.length} photos, ${activityItems.length} activities');
      
      final newState = EventPhotoFeedState.initial().copyWith(
        items: page.items,
        activityItems: activityItems,
        cursor: page.nextCursor,
        activeCursor: page.activeCursor,
        pendingCursor: page.pendingCursor,
        hasMore: page.hasMore,
        lastUpdatedAt: DateTime.now(),
      );
      
      state = AsyncData(newState);
      
      if (newState.items.isNotEmpty) {
        await _cache.setCachedFeed(scope, newState.items);
        await _prefetchInitialThumbnails(newState.items);
      }
    } catch (e, stack) {
      debugPrint('❌ [_refreshFull] ERRO no refresh: $e');
      debugPrint('📚 Stack trace: $stack');
      
      // Se tinha dados, mantém (não mostra erro)
      // Se não tinha dados, mostra erro
      if (!hasExistingData) {
        state = AsyncError(e, stack);
      }
      // Se tinha dados e deu erro, mantém dados antigos (UX melhor)
    }
  }
  
  /// Busca ActivityFeed items mais novos que um timestamp
  Future<List<ActivityFeedItemModel>> _fetchActivityFeedNewerThan(
    EventPhotoFeedScope scope,
    Timestamp newerThan,
  ) async {
    try {
      final userId = _safeUserId();
      
      // Para scope User, busca apenas do usuário específico
      if (scope is EventPhotoFeedScopeUser) {
        return await _activityRepo.fetchUserFeedNewerThan(
          userId: scope.userId,
          newerThan: newerThan,
          limit: _pageSize,
        );
      }
      
      // Para scope Following, busca de todos os usuários seguidos
      if (scope is EventPhotoFeedScopeFollowing && userId != null) {
        final followingIds = await _fetchFollowingIds(userId);
        if (followingIds.isEmpty) return [];
        
        return await _activityRepo.fetchFollowingFeedNewerThan(
          userIds: followingIds,
          newerThan: newerThan,
          limit: _pageSize,
        );
      }
      
      // Para scope Global ou outros, busca global
      return await _activityRepo.fetchGlobalFeedNewerThan(
        newerThan: newerThan,
        limit: _pageSize,
      );
    } catch (e) {
      debugPrint('⚠️ [_fetchActivityFeedNewerThan] Erro: $e');
      return [];
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.isLoadingMore || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final userId = _safeUserId();
      final page = userId == null
          ? await _repo.fetchFeedPage(
              scope: arg,
              limit: _pageSize,
              cursor: current.cursor,
            )
          : await _repo.fetchFeedPageWithOwnPending(
              scope: arg,
              limit: _pageSize,
              currentUserId: userId,
              activeCursor: current.activeCursor,
              pendingCursor: current.pendingCursor,
            );

      final merged = <EventPhotoModel>[...current.items, ...page.items];
      state = AsyncData(
        current.copyWith(
          items: merged,
          cursor: page.nextCursor,
          activeCursor: page.activeCursor,
          pendingCursor: page.pendingCursor,
          hasMore: page.hasMore,
          isLoadingMore: false,
          lastUpdatedAt: DateTime.now(),
        ),
      );
      await _cache.setCachedFeed(arg, merged);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Insere um item no topo do feed local (optimistic UI) e evita duplicados.
  /// Útil logo após postar no composer para o usuário ver instantaneamente.
  void optimisticPrepend(EventPhotoModel item) {
    final current = state.valueOrNull;
    if (current == null) return;

    final existingIndex = current.items.indexWhere((e) => e.id == item.id);
    final nextItems = [...current.items];
    if (existingIndex >= 0) {
      nextItems.removeAt(existingIndex);
    }
    nextItems.insert(0, item);

    state = AsyncData(
      current.copyWith(
        items: nextItems,
        // Mantém hasMore/cursors como estão.
        lastUpdatedAt: DateTime.now(),
      ),
    );

    _cache.setCachedFeed(arg, nextItems);
  }

  /// Remove um post do feed local (optimistic UI) para feedback instantâneo ao deletar.
  void optimisticRemovePhoto({required String photoId}) {
    final current = state.valueOrNull;
    if (current == null) return;

    final nextItems = current.items.where((e) => e.id != photoId).toList();
    
    // Se não mudou, retorna
    if (nextItems.length == current.items.length) return;
    
    debugPrint('🗑️ [optimisticRemovePhoto] Removendo $photoId da UI (${current.items.length} -> ${nextItems.length})');

    state = AsyncData(
      current.copyWith(
        items: nextItems,
        lastUpdatedAt: DateTime.now(),
      ),
    );

    _cache.setCachedFeed(arg, nextItems);
  }

  /// Remove uma imagem do item localmente para evitar flicker após delete.
  void optimisticRemoveImage({
    required String photoId,
    required int index,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;

    final itemIndex = current.items.indexWhere((e) => e.id == photoId);
    if (itemIndex < 0) return;

    final item = current.items[itemIndex];
    if (index < 0 || index >= item.imageUrls.length) return;
    if (item.imageUrls.length <= 1) return;

    final nextImageUrls = [...item.imageUrls]..removeAt(index);
    final nextThumbnailUrls = [...item.thumbnailUrls];
    if (index < nextThumbnailUrls.length) {
      nextThumbnailUrls.removeAt(index);
    }

    final updatedItem = EventPhotoModel(
      id: item.id,
      eventId: item.eventId,
      userId: item.userId,
      imageUrl: nextImageUrls.first,
      thumbnailUrl: nextThumbnailUrls.isNotEmpty ? nextThumbnailUrls.first : null,
      imageUrls: nextImageUrls,
      thumbnailUrls: nextThumbnailUrls,
      caption: item.caption,
      createdAt: item.createdAt,
      eventTitle: item.eventTitle,
      eventEmoji: item.eventEmoji,
      eventDate: item.eventDate,
      eventCityId: item.eventCityId,
      eventCityName: item.eventCityName,
      userName: item.userName,
      userPhotoUrl: item.userPhotoUrl,
      status: item.status,
      reportCount: item.reportCount,
      likesCount: item.likesCount,
      commentsCount: item.commentsCount,
      taggedParticipants: item.taggedParticipants,
    );

    final nextItems = [...current.items];
    nextItems[itemIndex] = updatedItem;

    state = AsyncData(
      current.copyWith(
        items: nextItems,
        lastUpdatedAt: DateTime.now(),
      ),
    );

    _cache.setCachedFeed(arg, nextItems);
  }

  void optimisticUpdateCaption({
    required String photoId,
    required String caption,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;

    final itemIndex = current.items.indexWhere((e) => e.id == photoId);
    if (itemIndex < 0) return;

    final item = current.items[itemIndex];

    final updatedItem = EventPhotoModel(
      id: item.id,
      eventId: item.eventId,
      userId: item.userId,
      imageUrl: item.imageUrl,
      thumbnailUrl: item.thumbnailUrl,
      imageUrls: item.imageUrls,
      thumbnailUrls: item.thumbnailUrls,
      caption: caption,
      createdAt: item.createdAt,
      eventTitle: item.eventTitle,
      eventEmoji: item.eventEmoji,
      eventDate: item.eventDate,
      eventCityId: item.eventCityId,
      eventCityName: item.eventCityName,
      userName: item.userName,
      userPhotoUrl: item.userPhotoUrl,
      status: item.status,
      reportCount: item.reportCount,
      likesCount: item.likesCount,
      commentsCount: item.commentsCount,
      taggedParticipants: item.taggedParticipants,
    );

    final nextItems = [...current.items];
    nextItems[itemIndex] = updatedItem;

    state = AsyncData(
      current.copyWith(
        items: nextItems,
        lastUpdatedAt: DateTime.now(),
      ),
    );

    _cache.setCachedFeed(arg, nextItems);
  }

  Future<void> _prefetchInitialThumbnails(List<EventPhotoModel> items) async {
    if (items.isEmpty) return;

    final maxItems = await _prefetchMaxItems();
    if (maxItems <= 0) return;

    final urls = <String>[];
    for (final item in items) {
      String? thumb;
      if (item.thumbnailUrls.isNotEmpty) {
        thumb = item.thumbnailUrls.first;
      } else if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty) {
        thumb = item.thumbnailUrl;
      }

      if (thumb != null && thumb.isNotEmpty) {
        urls.add(thumb);
      }

      if (urls.length >= maxItems) break;
    }

    await MediaCacheManager.prefetchThumbnails(urls, maxItems: maxItems);
  }

  Future<int> _prefetchMaxItems() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.wifi) {
        return 10;
      }
      if (connectivity == ConnectivityResult.mobile) {
        return 5;
      }
    } catch (_) {
      // fallback
    }
    return 5;
  }
}
