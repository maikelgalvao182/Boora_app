import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/event_photo_feed/data/models/tagged_participant_model.dart';

class EventPhotoModel {
  const EventPhotoModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.imageUrl,
    this.thumbnailUrl,
    this.imageUrls = const [],
    this.thumbnailUrls = const [],
    this.caption,
    required this.createdAt,
    required this.eventTitle,
    required this.eventEmoji,
    required this.eventDate,
    this.eventCityId,
    this.eventCityName,
    required this.userName,
    required this.userPhotoUrl,
    required this.status,
    required this.reportCount,
    required this.likesCount,
    required this.commentsCount,
    this.taggedParticipants = const [],
  });

  final String id;
  final String eventId;
  final String userId;

  final String imageUrl;
  final String? thumbnailUrl;
  final List<String> imageUrls;
  final List<String> thumbnailUrls;

  final String? caption;
  final Timestamp? createdAt;

  final String eventTitle;
  final String eventEmoji;
  final Timestamp? eventDate;
  final String? eventCityId;
  final String? eventCityName;

  final String userName;
  final String userPhotoUrl;

  final String status; // under_review | active | hidden...
  final int reportCount;

  final int likesCount;
  final int commentsCount;

  final List<TaggedParticipantModel> taggedParticipants;

  factory EventPhotoModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    
    // Parse tagged participants com tratamento defensivo
    List<TaggedParticipantModel> taggedList = [];
    final rawTagged = data['taggedParticipants'];
    if (rawTagged is List) {
      for (final item in rawTagged) {
        if (item is Map<String, dynamic>) {
          taggedList.add(TaggedParticipantModel.fromMap(item));
        }
      }
    }

    // Parse image arrays
    final rawImageUrls = data['imageUrls'];
    final rawThumbnailUrls = data['thumbnailUrls'];
    final imageUrlsList = rawImageUrls is List
        ? rawImageUrls.whereType<String>().toList()
        : <String>[];
    final thumbnailUrlsList = rawThumbnailUrls is List
        ? rawThumbnailUrls.whereType<String>().toList()
        : <String>[];

    // Fallback: se arrays estão vazios, usa campos simples
    if (imageUrlsList.isEmpty && (data['imageUrl'] as String?)?.isNotEmpty == true) {
      imageUrlsList.add(data['imageUrl'] as String);
    }
    if (thumbnailUrlsList.isEmpty && (data['thumbnailUrl'] as String?)?.isNotEmpty == true) {
      thumbnailUrlsList.add(data['thumbnailUrl'] as String);
    }
    
    // Debug log
    if (imageUrlsList.length > 1) {
      debugPrint('📸 [EventPhotoModel] Doc ${doc.id} has ${imageUrlsList.length} images');
    }

    return EventPhotoModel(
      id: doc.id,
      eventId: (data['eventId'] as String?) ?? '',
      userId: (data['userId'] as String?) ?? '',
      imageUrl: (data['imageUrl'] as String?) ?? '',
      thumbnailUrl: data['thumbnailUrl'] as String?,
      imageUrls: imageUrlsList,
      thumbnailUrls: thumbnailUrlsList,
      caption: data['caption'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      eventTitle: (data['eventTitle'] as String?) ?? '',
      eventEmoji: (data['eventEmoji'] as String?) ?? '',
      eventDate: data['eventDate'] as Timestamp?,
      eventCityId: data['eventCityId'] as String?,
      eventCityName: data['eventCityName'] as String?,
      userName: (data['userName'] as String?) ?? '',
      userPhotoUrl: (data['userPhotoUrl'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'under_review',
      reportCount: (data['reportCount'] as num?)?.toInt() ?? 0,
      likesCount: (data['likesCount'] as num?)?.toInt() ?? 0,
      commentsCount: (data['commentsCount'] as num?)?.toInt() ?? 0,
      taggedParticipants: taggedList,
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'eventId': eventId,
      'userId': userId,
      'imageUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
      'imageUrls': imageUrls,
      'thumbnailUrls': thumbnailUrls,
      'caption': caption,
      'createdAt': FieldValue.serverTimestamp(),
      'eventTitle': eventTitle,
      'eventEmoji': eventEmoji,
      'eventDate': eventDate,
      'eventCityId': eventCityId,
      'eventCityName': eventCityName,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'status': status,
      'reportCount': reportCount,
      'likesCount': likesCount,
      'commentsCount': commentsCount,
      'taggedParticipants': taggedParticipants.map((p) => p.toMap()).toList(),
    };
  }
}
