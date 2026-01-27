import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:partiu/features/event_photo_feed/domain/services/event_photo_like_service.dart';

final eventPhotoLikeServiceProvider = Provider<EventPhotoLikeService>((ref) {
  return EventPhotoLikeService();
});

final eventPhotoLikesCountProvider = StreamProvider.family<int, String>((ref, photoId) {
  final service = ref.read(eventPhotoLikeServiceProvider);
  return service.watchLikesCount(photoId);
});

final eventPhotoIsLikedProvider = StreamProvider.family<bool, String>((ref, photoId) {
  final service = ref.read(eventPhotoLikeServiceProvider);
  return service.watchIsLiked(photoId);
});

final eventPhotoLikeUiProvider = StateNotifierProvider.family<EventPhotoLikeUiController, EventPhotoLikeUiState, String>(
  (ref, photoId) => EventPhotoLikeUiController(
    service: ref.read(eventPhotoLikeServiceProvider),
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
    required this.photoId,
  })  : _service = service,
        super(const EventPhotoLikeUiState());

  final EventPhotoLikeService _service;
  final String photoId;

  static const Duration _debounceWindow = Duration(milliseconds: 600);
  DateTime? _lastTapAt;
  Timer? _resetTimer;

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

    state = state.copyWith(
      isLiked: nextLiked,
      likesCount: nextCount,
      isPending: true,
    );

    try {
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
      state = const EventPhotoLikeUiState();
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }
}
