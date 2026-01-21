import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/event_photo_feed/data/models/tagged_participant_model.dart';

class EventPhotoModel {
  const EventPhotoModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.imageUrl,
    this.thumbnailUrl,
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

    return EventPhotoModel(
      id: doc.id,
      eventId: (data['eventId'] as String?) ?? '',
      userId: (data['userId'] as String?) ?? '',
      imageUrl: (data['imageUrl'] as String?) ?? '',
      thumbnailUrl: data['thumbnailUrl'] as String?,
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
