import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:partiu/features/event_photo_feed/domain/services/event_photo_like_service.dart';
import 'package:partiu/features/event_photo_feed/domain/services/event_photo_likes_cache_service.dart';

final eventPhotoLikeServiceProvider = Provider<EventPhotoLikeService>((ref) {
  final likesCache = ref.read(eventPhotoLikesCacheServiceProvider);
  final service = EventPhotoLikeService(likesCache: likesCache);
  return service;
});

final eventPhotoLikesCountProvider = StreamProvider.family<int, String>((ref, photoId) {
  final service = ref.read(eventPhotoLikeServiceProvider);
  return service.watchLikesCount(photoId);
});

/// Provider para verificar se uma foto foi curtida
/// 
/// **OTIMIZADO:** Agora usa cache local ao invés de Stream realtime.
/// Retorna valor do cache instantaneamente, sem criar listener no Firestore.
/// 
/// O cache é hidratado uma vez por sessão/dia via [EventPhotoLikesCacheService].
final eventPhotoIsLikedProvider = FutureProvider.family<bool, String>((ref, photoId) async {
  final likesCache = ref.read(eventPhotoLikesCacheServiceProvider);
  
  // Garante que o cache está inicializado
  await likesCache.initialize();
  
  // Retorna valor do cache (O(1), sem network)
  return likesCache.isLiked(photoId);
});

/// Provider síncrono para verificar se uma foto foi curtida
/// 
/// **USO RECOMENDADO** para UI no feed - não cria overhead de Future/Stream.
/// Retorna `false` se o cache não estiver pronto.
final eventPhotoIsLikedSyncProvider = Provider.family<bool, String>((ref, photoId) {
  final likesCache = ref.read(eventPhotoLikesCacheServiceProvider);
  return likesCache.isLiked(photoId);
});

final eventPhotoLikeUiProvider = StateNotifierProvider.family<EventPhotoLikeUiController, EventPhotoLikeUiState, String>(
  (ref, photoId) => EventPhotoLikeUiController(
    service: ref.read(eventPhotoLikeServiceProvider),
    likesCache: ref.read(eventPhotoLikesCacheServiceProvider),
    photoId: photoId,
  ),
);

class EventPhotoLikeUiState {
  const EventPhotoLikeUiState({
    this.isLiked,
    this.likesCount,
    this.isPending = false,
  });

  final bool? isLiked;
  final int? likesCount;
  final bool isPending;

  EventPhotoLikeUiState copyWith({
    bool? isLiked,
    int? likesCount,
    bool? isPending,
  }) {
    return EventPhotoLikeUiState(
      isLiked: isLiked ?? this.isLiked,
      likesCount: likesCount ?? this.likesCount,
      isPending: isPending ?? this.isPending,
    );
  }
}

class EventPhotoLikeUiController extends StateNotifier<EventPhotoLikeUiState> {
  EventPhotoLikeUiController({
    required EventPhotoLikeService service,
    required EventPhotoLikesCacheService likesCache,
    required this.photoId,
  })  : _service = service,
        _likesCache = likesCache,
        super(const EventPhotoLikeUiState()) {
    // Inicializa com valor do cache
    _initFromCache();
  }

  final EventPhotoLikeService _service;
  final EventPhotoLikesCacheService _likesCache;
  final String photoId;

  static const Duration _debounceWindow = Duration(milliseconds: 600);
  DateTime? _lastTapAt;
  Timer? _resetTimer;

  /// Inicializa o estado com valor do cache local
  void _initFromCache() {
    final isLiked = _likesCache.isLiked(photoId);
    if (isLiked) {
      state = state.copyWith(isLiked: true);
    }
  }

  Future<bool> toggle({
    required bool currentlyLiked,
    required int currentCount,
  }) async {
    final now = DateTime.now();
    if (_lastTapAt != null && now.difference(_lastTapAt!) < _debounceWindow) {
      return currentlyLiked;
    }
    if (state.isPending) {
      return state.isLiked ?? currentlyLiked;
    }

    _lastTapAt = now;
    final nextLiked = !currentlyLiked;
    final nextCount = max(0, currentCount + (nextLiked ? 1 : -1));

    // Atualização otimista: UI + cache local imediato
    state = state.copyWith(
      isLiked: nextLiked,
      likesCount: nextCount,
      isPending: true,
    );

    try {
      // Persiste no Firestore (cache já foi atualizado pelo service)
      final result = await _service.toggleLike(
        photoId: photoId,
        currentlyLiked: currentlyLiked,
      );

      state = state.copyWith(
        isLiked: result,
        likesCount: max(0, currentCount + (result ? 1 : -1)),
        isPending: false,
      );

      _scheduleReset();
      return result;
    } catch (_) {
      // Reverte UI (cache já foi revertido pelo service)
      state = state.copyWith(
        isLiked: currentlyLiked,
        likesCount: currentCount,
        isPending: false,
      );
      _scheduleReset();
      return currentlyLiked;
    }
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 1), () {
      // Mantém isLiked do cache ao resetar
      final cachedLiked = _likesCache.isLiked(photoId);
      state = EventPhotoLikeUiState(isLiked: cachedLiked ? true : null);
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }
}
