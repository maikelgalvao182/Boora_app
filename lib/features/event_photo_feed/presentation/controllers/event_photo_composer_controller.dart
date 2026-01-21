import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/data/repositories/event_photo_repository.dart';
import 'package:partiu/features/event_photo_feed/domain/services/event_photo_composer_service.dart';
import 'package:partiu/features/event_photo_feed/domain/services/recent_events_service.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_feed_controller.dart';
import 'package:partiu/features/home/data/models/event_model.dart';

class EventPhotoComposerState {
  const EventPhotoComposerState({
    required this.selectedEvent,
    required this.image,
    required this.caption,
    required this.progress,
    required this.isSubmitting,
    required this.error,
  });

  final EventModel? selectedEvent;
  final XFile? image;
  final String caption;
  final double? progress;
  final bool isSubmitting;
  final String? error;

  factory EventPhotoComposerState.initial() => const EventPhotoComposerState(
        selectedEvent: null,
        image: null,
        caption: '',
        progress: null,
        isSubmitting: false,
        error: null,
      );

  EventPhotoComposerState copyWith({
    EventModel? selectedEvent,
    XFile? image,
    String? caption,
    double? progress,
    bool? isSubmitting,
    String? error,
    bool clearImage = false,
  }) {
    return EventPhotoComposerState(
      selectedEvent: selectedEvent ?? this.selectedEvent,
      image: clearImage ? null : (image ?? this.image),
      caption: caption ?? this.caption,
      progress: progress,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
    );
  }
}

final recentEventsServiceProvider = Provider<RecentEventsService>((ref) {
  return RecentEventsService();
});

final eventPhotoComposerServiceProvider = Provider<EventPhotoComposerService>((ref) {
  return EventPhotoComposerService();
});

final eventPhotoComposerControllerProvider =
    NotifierProvider<EventPhotoComposerController, EventPhotoComposerState>(
  EventPhotoComposerController.new,
);

class EventPhotoComposerController extends Notifier<EventPhotoComposerState> {
  EventPhotoComposerService get _service => ref.read(eventPhotoComposerServiceProvider);
  // EventPhotoRepository get _repo => ref.read(eventPhotoRepositoryProvider);

  @override
  EventPhotoComposerState build() => EventPhotoComposerState.initial();

  void setSelectedEvent(EventModel? event) {
    state = state.copyWith(selectedEvent: event, error: null);
  }

  void setCaption(String value) {
    state = state.copyWith(caption: value, error: null);
  }

  Future<void> pickImage() async {
    final img = await _service.pickImage();
    if (img == null) return;
    state = state.copyWith(image: img, error: null);
  }

  void removeImage() {
    state = state.copyWith(clearImage: true, error: null);
  }

  Future<void> submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      state = state.copyWith(error: 'Usuário não autenticado');
      return;
    }

    final selectedEvent = state.selectedEvent;
    if (selectedEvent == null) {
      state = state.copyWith(error: 'Selecione um evento');
      return;
    }

    final image = state.image;
    if (image == null) {
      state = state.copyWith(error: 'Selecione uma imagem');
      return;
    }

    state = state.copyWith(isSubmitting: true, progress: 0, error: null);

    try {
      // photoId: doc id
      final photoId = FirebaseFirestore.instance.collection('EventPhotos').doc().id;

      final upload = await _service.uploadPhotoAndThumb(
        eventId: selectedEvent.id,
        photoId: photoId,
        image: image,
        onProgress: (p) {
          state = state.copyWith(progress: p);
        },
      );

      // user info (MVP: via AppState)
      final currentUser = AppState.currentUser.value;
  final userName = currentUser?.fullName ?? '';
      final userPhotoUrl = currentUser?.photoUrl ?? '';

      final payload = _service.buildCreatePayload(
        eventId: selectedEvent.id,
        userId: user.uid,
        imageUrl: upload.photoUrl,
        thumbnailUrl: upload.thumbUrl,
        caption: state.caption,
        eventTitle: selectedEvent.title,
        eventEmoji: selectedEvent.emoji,
        eventDate: selectedEvent.scheduleDate != null
            ? Timestamp.fromDate(selectedEvent.scheduleDate!)
            : null,
        eventCityId: null,
        eventCityName: null,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
      );

      await FirebaseFirestore.instance.collection('EventPhotos').doc(photoId).set(payload);

      // Optimistic UI: insere imediatamente no topo do feed global.
      // Obs: `createdAt` ainda pode vir null (serverTimestamp), então o sort final pode mudar após refresh.
      ref
          .read(eventPhotoFeedControllerProvider(const EventPhotoFeedScopeGlobal()).notifier)
          .optimisticPrepend(
            EventPhotoModel(
              id: photoId,
              eventId: selectedEvent.id,
              userId: user.uid,
              imageUrl: upload.photoUrl,
              thumbnailUrl: upload.thumbUrl,
              caption: state.caption.trim().isEmpty ? null : state.caption.trim(),
              createdAt: Timestamp.now(),
              eventTitle: selectedEvent.title,
              eventEmoji: selectedEvent.emoji,
              eventDate: selectedEvent.scheduleDate != null
                  ? Timestamp.fromDate(selectedEvent.scheduleDate!)
                  : null,
              eventCityId: null,
              eventCityName: null,
              userName: userName,
              userPhotoUrl: userPhotoUrl,
              status: 'under_review',
              reportCount: 0,
              likesCount: 0,
              commentsCount: 0,
            ),
          );

      // Invalidate feeds (qualquer escopo pode refletir)
      ref.invalidate(eventPhotoFeedControllerProvider);

      state = EventPhotoComposerState.initial();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isSubmitting: false, progress: null);
    }
  }
}
