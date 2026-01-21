import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:partiu/core/services/image_compress_service.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/features/event_photo_feed/data/models/tagged_participant_model.dart';

class EventPhotoUploadResult {
  const EventPhotoUploadResult({
    required this.photoUrl,
    required this.thumbUrl,
  });

  final String photoUrl;
  final String? thumbUrl;
}

class EventPhotoComposerService {
  EventPhotoComposerService({
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    ImagePicker? picker,
    ImageCompressService? compressService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _picker = picker ?? ImagePicker(),
        _compressService = compressService ?? const ImageCompressService();

  static const String _tag = 'EventPhotoComposer';

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final ImagePicker _picker;
  final ImageCompressService _compressService;

  Future<XFile?> pickImage() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      maxWidth: 4096,
      maxHeight: 4096,
    );
  }

  Future<EventPhotoUploadResult> uploadPhotoAndThumb({
    required String eventId,
    required String photoId,
    required XFile image,
    void Function(double progress)? onProgress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    final original = File(image.path);

    // photo ~1080px
    final photoBytes = await _compressService.compressFileToBytes(
      original,
      minWidth: 1080,
      minHeight: 1080,
      quality: 82,
    );

    // thumb ~420px
    final thumbBytes = await _compressService.compressFileToBytes(
      original,
      minWidth: 420,
      minHeight: 420,
      quality: 70,
    );

    final photoRef = _storage.ref('event_photos/$eventId/$photoId.jpg');
    final thumbRef = _storage.ref('event_photos/$eventId/${photoId}_thumb.jpg');

    AppLogger.info('Upload start: eventId=$eventId photoId=$photoId', tag: _tag);

    final photoTask = photoRef.putData(
      photoBytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    photoTask.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes <= 0) return;
      onProgress?.call(snapshot.bytesTransferred / snapshot.totalBytes);
    });

    await photoTask;
    final photoUrl = await photoRef.getDownloadURL();

    String? thumbUrl;
    try {
      await thumbRef.putData(
        thumbBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      thumbUrl = await thumbRef.getDownloadURL();
    } catch (e) {
      AppLogger.warning('Thumb upload failed: $e', tag: _tag);
    }

    return EventPhotoUploadResult(photoUrl: photoUrl, thumbUrl: thumbUrl);
  }

  Map<String, dynamic> buildCreatePayload({
    required String eventId,
    required String userId,
    required String imageUrl,
    required String? thumbnailUrl,
    required String? caption,
    required String eventTitle,
    required String eventEmoji,
    required Timestamp? eventDate,
    required String? eventCityId,
    required String? eventCityName,
    required String userName,
    required String userPhotoUrl,
    List<TaggedParticipantModel> taggedParticipants = const [],
  }) {
    if (eventId.trim().isEmpty) throw Exception('eventId obrigatório');
    final safeCaption = (caption ?? '').trim();
    if (safeCaption.length > 500) throw Exception('Legenda muito longa (max 500)');

    return {
      'eventId': eventId,
      'userId': userId,
      'imageUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
      'caption': safeCaption.isEmpty ? null : safeCaption,
      'createdAt': FieldValue.serverTimestamp(),
      'eventTitle': eventTitle,
      'eventEmoji': eventEmoji,
      'eventDate': eventDate,
      'eventCityId': eventCityId,
      'eventCityName': eventCityName,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'status': 'under_review',
      'reportCount': 0,
      'likesCount': 0,
      'commentsCount': 0,
      'taggedParticipants': taggedParticipants.map((p) => p.toMap()).toList(),
    };
  }
}
