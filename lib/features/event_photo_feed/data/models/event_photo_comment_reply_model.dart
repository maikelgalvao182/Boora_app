import 'package:cloud_firestore/cloud_firestore.dart';

class EventPhotoCommentReplyModel {
  const EventPhotoCommentReplyModel({
    required this.id,
    required this.photoId,
    required this.commentId,
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
    required this.text,
    required this.createdAt,
    this.status = 'active',
  });

  final String id;
  final String photoId;
  final String commentId;
  final String userId;
  final String userName;
  final String userPhotoUrl;
  final String text;
  final Timestamp? createdAt;
  final String status;

  Map<String, dynamic> toMap() {
    return {
      'photoId': photoId,
      'commentId': commentId,
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'text': text,
      'createdAt': createdAt,
      'status': status,
    };
  }

  factory EventPhotoCommentReplyModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String photoId,
    required String commentId,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    return EventPhotoCommentReplyModel(
      id: doc.id,
      photoId: photoId,
      commentId: commentId,
      userId: (data['userId'] as String?) ?? '',
      userName: (data['userName'] as String?) ?? '',
      userPhotoUrl: (data['userPhotoUrl'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
      createdAt: data['createdAt'] as Timestamp?,
      status: (data['status'] as String?) ?? 'active',
    );
  }
}
