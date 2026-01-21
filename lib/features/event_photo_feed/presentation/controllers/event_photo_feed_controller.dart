import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/data/repositories/event_photo_repository.dart';

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
  return EventPhotoRepository();
});

final eventPhotoFeedControllerProvider =
    AsyncNotifierProviderFamily<EventPhotoFeedController, EventPhotoFeedState, EventPhotoFeedScope>(
  EventPhotoFeedController.new,
);

class EventPhotoFeedController extends FamilyAsyncNotifier<EventPhotoFeedState, EventPhotoFeedScope> {
  static const int _pageSize = 20;
  static const Duration _ttl = Duration(seconds: 45);

  EventPhotoRepository get _repo => ref.read(eventPhotoRepositoryProvider);

  @override
  Future<EventPhotoFeedState> build(EventPhotoFeedScope scope) async {
    print('🎯 [EventPhotoFeedController.build] Iniciando build - scope: $scope');
    
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
      
      return EventPhotoFeedState.initial().copyWith(
        items: page.items,
        cursor: page.nextCursor,
        activeCursor: page.activeCursor,
        pendingCursor: page.pendingCursor,
        hasMore: page.hasMore,
        lastUpdatedAt: DateTime.now(),
      );
    } catch (e, stack) {
      print('❌ [EventPhotoFeedController.build] ERRO ao carregar feed: $e');
      print('📚 Stack trace: $stack');
      rethrow;
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
  }
}
