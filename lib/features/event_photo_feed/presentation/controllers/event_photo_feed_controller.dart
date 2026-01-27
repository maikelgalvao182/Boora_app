import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_feed_scope.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/data/repositories/event_photo_repository.dart';
import 'package:partiu/features/event_photo_feed/domain/services/event_photo_cache_service.dart';
import 'package:partiu/core/services/cache/media_cache_manager.dart';

class EventPhotoFeedState {
  const EventPhotoFeedState({
    required this.items,
    required this.cursor,
  required this.activeCursor,
  required this.pendingCursor,
    required this.hasMore,
    required this.isLoadingMore,
    required this.lastUpdatedAt,
  });

  final List<EventPhotoModel> items;
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
        cursor: null,
  activeCursor: null,
  pendingCursor: null,
        hasMore: true,
        isLoadingMore: false,
        lastUpdatedAt: null,
      );

  EventPhotoFeedState copyWith({
    List<EventPhotoModel>? items,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    DocumentSnapshot<Map<String, dynamic>>? activeCursor,
    DocumentSnapshot<Map<String, dynamic>>? pendingCursor,
    bool? hasMore,
    bool? isLoadingMore,
    DateTime? lastUpdatedAt,
  }) {
    return EventPhotoFeedState(
      items: items ?? this.items,
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

final eventPhotoFeedControllerProvider =
    AsyncNotifierProviderFamily<EventPhotoFeedController, EventPhotoFeedState, EventPhotoFeedScope>(
  EventPhotoFeedController.new,
);

class EventPhotoFeedController extends FamilyAsyncNotifier<EventPhotoFeedState, EventPhotoFeedScope> {
  static const int _pageSize = 20;
  static const Duration _ttl = Duration(seconds: 45);

  EventPhotoRepository get _repo => ref.read(eventPhotoRepositoryProvider);
  EventPhotoCacheService get _cache => ref.read(eventPhotoCacheServiceProvider);

  @override
  Future<EventPhotoFeedState> build(EventPhotoFeedScope scope) async {
    print('🎯 [EventPhotoFeedController.build] Iniciando build - scope: $scope');

    await _cache.initialize();
    final cachedItems = _cache.getCachedFeed(scope);
    if (cachedItems != null && cachedItems.isNotEmpty) {
      Future.microtask(_refreshSilently);
      return EventPhotoFeedState.initial().copyWith(
        items: cachedItems,
        hasMore: true,
        lastUpdatedAt: DateTime.now(),
      );
    }
    
    // TTL in-memory: se já carregou recentemente e ainda é válido, mantém.
    final existing = state.valueOrNull;
    if (existing != null && existing.lastUpdatedAt != null) {
      final age = DateTime.now().difference(existing.lastUpdatedAt!);
      if (age < _ttl && existing.items.isNotEmpty) {
        print('✅ [EventPhotoFeedController.build] Cache válido (age: ${age.inSeconds}s)');
        return existing;
      }
    }

    print('🔄 [EventPhotoFeedController.build] Carregando dados do Firestore...');
    final userId = _safeUserId();
    print('👤 [EventPhotoFeedController.build] userId: $userId');
    
    try {
      final page = userId == null
          ? await _repo.fetchFeedPage(scope: scope, limit: _pageSize)
          : await _repo.fetchFeedPageWithOwnPending(
              scope: scope,
              limit: _pageSize,
              currentUserId: userId,
            );
      
      print('✅ [EventPhotoFeedController.build] Dados carregados: ${page.items.length} items, hasMore: ${page.hasMore}');

      final nextState = EventPhotoFeedState.initial().copyWith(
        items: page.items,
        cursor: page.nextCursor,
        activeCursor: page.activeCursor,
        pendingCursor: page.pendingCursor,
        hasMore: page.hasMore,
        lastUpdatedAt: DateTime.now(),
      );

      await _cache.setCachedFeed(scope, page.items);
      await _prefetchInitialThumbnails(page.items);
      return nextState;
    } catch (e, stack) {
      print('❌ [EventPhotoFeedController.build] ERRO ao carregar feed: $e');
      print('📚 Stack trace: $stack');
      rethrow;
    }
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

      final nextState = EventPhotoFeedState.initial().copyWith(
        items: page.items,
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

  Future<void> refresh() async {
    print('🔄 [EventPhotoFeedController.refresh] Iniciando refresh...');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final scope = arg;
      final userId = _safeUserId();
      print('👤 [EventPhotoFeedController.refresh] userId: $userId, scope: $scope');
      
      try {
        final page = userId == null
          ? await _repo.fetchFeedPage(scope: scope, limit: _pageSize)
          : await _repo.fetchFeedPageWithOwnPending(
            scope: scope,
            limit: _pageSize,
            currentUserId: userId,
          );
        
        print('✅ [EventPhotoFeedController.refresh] Refresh completo: ${page.items.length} items');
        
        return EventPhotoFeedState.initial().copyWith(
          items: page.items,
          cursor: page.nextCursor,
          activeCursor: page.activeCursor,
          pendingCursor: page.pendingCursor,
          hasMore: page.hasMore,
          lastUpdatedAt: DateTime.now(),
        );
      } catch (e, stack) {
        print('❌ [EventPhotoFeedController.refresh] ERRO no refresh: $e');
        print('📚 Stack trace: $stack');
        rethrow;
      }
    });

    final refreshed = state.valueOrNull;
    if (refreshed != null && refreshed.items.isNotEmpty) {
      await _cache.setCachedFeed(arg, refreshed.items);
      await _prefetchInitialThumbnails(refreshed.items);
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
