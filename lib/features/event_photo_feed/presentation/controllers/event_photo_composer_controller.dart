import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_feed_scope.dart';
import 'package:partiu/features/event_photo_feed/data/models/tagged_participant_model.dart';
import 'package:partiu/features/event_photo_feed/data/repositories/event_photo_repository.dart';
import 'package:partiu/features/event_photo_feed/domain/services/event_photo_composer_service.dart';
import 'package:partiu/features/event_photo_feed/domain/services/recent_events_service.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_feed_controller.dart';
import 'package:partiu/features/home/data/models/event_model.dart';

class EventPhotoComposerState {
  const EventPhotoComposerState({
    required this.selectedEvent,
    required this.images,
    required this.caption,
    required this.progress,
    required this.isSubmitting,
    required this.error,
    required this.taggedParticipants,
  });

  final EventModel? selectedEvent;
  final List<XFile> images;
  final String caption;
  final double? progress;
  final bool isSubmitting;
  final String? error;
  final List<TaggedParticipantModel> taggedParticipants;

  factory EventPhotoComposerState.initial() => const EventPhotoComposerState(
        selectedEvent: null,
        images: [],
        caption: '',
        progress: null,
        isSubmitting: false,
        error: null,
        taggedParticipants: [],
      );

  EventPhotoComposerState copyWith({
    EventModel? selectedEvent,
    List<XFile>? images,
    String? caption,
    double? progress,
    bool? isSubmitting,
    String? error,
    List<TaggedParticipantModel>? taggedParticipants,
    bool clearEvent = false,
  }) {
    return EventPhotoComposerState(
      selectedEvent: clearEvent ? null : (selectedEvent ?? this.selectedEvent),
      images: images ?? this.images,
      caption: caption ?? this.caption,
      progress: progress,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      taggedParticipants: taggedParticipants ?? this.taggedParticipants,
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
    // Limpar participantes se o evento mudou
    state = state.copyWith(selectedEvent: event, error: null, taggedParticipants: []);
  }

  void setTaggedParticipants(List<TaggedParticipantModel> participants) {
    state = state.copyWith(taggedParticipants: participants, error: null);
  }

  void setCaption(String value) {
    state = state.copyWith(caption: value, error: null);
  }

  Future<void> pickImage() async {
    final images = await _service.pickMultipleImages();
    if (images.isEmpty) return;
    final updatedImages = [...state.images, ...images];
    state = state.copyWith(images: updatedImages, error: null);
  }

  void removeImage(int index) {
    final updatedImages = [...state.images];
    updatedImages.removeAt(index);
    state = state.copyWith(images: updatedImages, error: null);
  }

  Future<void> submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      state = state.copyWith(error: 'event_photo_error_not_authenticated');
      return;
    }

    final selectedEvent = state.selectedEvent;
    if (selectedEvent == null) {
      state = state.copyWith(error: 'event_photo_error_select_event');
      return;
    }

    if ((state.caption ?? '').trim().isEmpty) {
      state = state.copyWith(error: 'event_photo_error_add_caption');
      return;
    }

    if (state.images.isEmpty) {
      state = state.copyWith(error: 'event_photo_error_select_image');
      return;
    }

    state = state.copyWith(isSubmitting: true, progress: 0, error: null);

    try {
      // photoId: doc id
      final photoId = FirebaseFirestore.instance.collection('EventPhotos').doc().id;

      // Upload de todas as imagens
      final List<String> imageUrls = [];
      final List<String> thumbnailUrls = [];
      
      debugPrint('📸 [EventPhotoComposer] Iniciando upload de ${state.images.length} imagens');
      
      for (int i = 0; i < state.images.length; i++) {
        debugPrint('📸 [EventPhotoComposer] Uploading image ${i + 1}/${state.images.length}');
        final upload = await _service.uploadPhotoAndThumb(
          eventId: selectedEvent.id,
          photoId: '$photoId-$i',
          image: state.images[i],
          onProgress: (p) {
            final overallProgress = (i + p) / state.images.length;
            state = state.copyWith(progress: overallProgress);
          },
        );
        imageUrls.add(upload.photoUrl);
        debugPrint('📸 [EventPhotoComposer] Image ${i + 1} uploaded: ${upload.photoUrl}');
        if (upload.thumbUrl != null) {
          thumbnailUrls.add(upload.thumbUrl!);
        }
      }
      
      debugPrint('📸 [EventPhotoComposer] Upload completo. imageUrls: ${imageUrls.length}, thumbnailUrls: ${thumbnailUrls.length}');

      // user info (MVP: via AppState)
      final currentUser = AppState.currentUser.value;
  final userName = currentUser?.fullName ?? '';
      final userPhotoUrl = currentUser?.photoUrl ?? '';

      final payload = await _service.buildCreatePayload(
        eventId: selectedEvent.id,
        userId: user.uid,
        imageUrl: imageUrls.first,
        thumbnailUrl: thumbnailUrls.isNotEmpty ? thumbnailUrls.first : null,
        imageUrls: imageUrls,
        thumbnailUrls: thumbnailUrls,
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
        taggedParticipants: state.taggedParticipants,
      );

      debugPrint('📸 [EventPhotoComposer] Payload imageUrls: ${payload['imageUrls']}');
      debugPrint('📸 [EventPhotoComposer] Payload thumbnailUrls: ${payload['thumbnailUrls']}');

      await FirebaseFirestore.instance.collection('EventPhotos').doc(photoId).set(payload);
      debugPrint('📸 [EventPhotoComposer] Post salvo com id: $photoId');

      // Optimistic UI: insere imediatamente no topo do feed global.
      // Obs: `createdAt` ainda pode vir null (serverTimestamp), então o sort final pode mudar após refresh.
      ref
          .read(eventPhotoFeedControllerProvider(const EventPhotoFeedScopeGlobal()).notifier)
          .optimisticPrepend(
            EventPhotoModel(
              id: photoId,
              eventId: selectedEvent.id,
              userId: user.uid,
              imageUrl: imageUrls.first,
              thumbnailUrl: thumbnailUrls.isNotEmpty ? thumbnailUrls.first : null,
              imageUrls: imageUrls,
              thumbnailUrls: thumbnailUrls,
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
              status: 'active',
              reportCount: 0,
              likesCount: 0,
              commentsCount: 0,
              taggedParticipants: state.taggedParticipants,
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
