import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/core/services/cache/hive_initializer.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_comment_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_comment_reply_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_feed_scope.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/tagged_participant_model.dart';

final eventPhotoCacheServiceProvider = Provider<EventPhotoCacheService>((ref) {
  return EventPhotoCacheService();
});

class EventPhotoCacheService {
  static const Duration feedIndexTtl = Duration(minutes: 5);
  static const Duration postTtl = Duration(minutes: 10);
  static const Duration commentsTtl = Duration(minutes: 2);
  static const Duration repliesTtl = Duration(minutes: 2);
  static const int maxCommentsCached = 50;
  static const int maxRepliesCached = 50;

  final HiveCacheService<List> _feedIndexCache = HiveCacheService<List>('event_photo_feed_index');
  final HiveCacheService<Map> _postCache = HiveCacheService<Map>('event_photo_post_cache');
  final HiveCacheService<List> _commentsCache = HiveCacheService<List>('event_photo_comments_cache');
  final HiveCacheService<List> _repliesCache = HiveCacheService<List>('event_photo_replies_cache');

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    await HiveInitializer.initialize();

    try {
      await _feedIndexCache.initialize();
      await _postCache.initialize();
      await _commentsCache.initialize();
      await _repliesCache.initialize();
      _initialized = true;
    } catch (e) {
      debugPrint('📦 EventPhotoCacheService init error: $e');
    }
  }

  String scopeKey(EventPhotoFeedScope scope) {
    return switch (scope) {
      EventPhotoFeedScopeCity(:final cityId) => 'city:${cityId ?? ''}',
      EventPhotoFeedScopeEvent(:final eventId) => 'event:$eventId',
      EventPhotoFeedScopeUser(:final userId) => 'user:$userId',
      EventPhotoFeedScopeFollowing(:final userId) => 'following:$userId',
      EventPhotoFeedScopeGlobal() => 'global',
    };
  }

  String _commentsKey(String photoId) => 'comments:$photoId';
  String _repliesKey(String photoId, String commentId) => 'replies:$photoId:$commentId';

  List<EventPhotoModel>? getCachedFeed(EventPhotoFeedScope scope) {
    if (!_initialized) return null;
    final key = scopeKey(scope);
    final raw = _feedIndexCache.get(key);
    if (raw == null || raw.isEmpty) return null;

    final items = raw
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .map(_eventPhotoFromCache)
        .toList(growable: false);

    return items;
  }

  Future<void> setCachedFeed(EventPhotoFeedScope scope, List<EventPhotoModel> items) async {
    await initialize();
    if (!_initialized) return;

    final key = scopeKey(scope);
    final indexList = items.map(_eventPhotoToIndexCache).toList(growable: false);

    await _feedIndexCache.put(key, indexList, ttl: feedIndexTtl);

    for (final item in items) {
      await _postCache.put(item.id, _eventPhotoToPostCache(item), ttl: postTtl);
    }
  }

  EventPhotoModel? getCachedPost(String postId) {
    if (!_initialized) return null;
    final raw = _postCache.get(postId);
    if (raw == null) return null;
    return _eventPhotoFromCache(Map<String, dynamic>.from(raw));
  }

  Future<void> setCachedPost(EventPhotoModel item) async {
    await initialize();
    if (!_initialized) return;
    await _postCache.put(item.id, _eventPhotoToPostCache(item), ttl: postTtl);
  }

  List<EventPhotoCommentModel>? getCachedComments(String photoId) {
    if (!_initialized) return null;
    final raw = _commentsCache.get(_commentsKey(photoId));
    if (raw == null || raw.isEmpty) return null;

    return raw
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .map((e) => _commentFromCache(e, photoId))
        .toList(growable: false);
  }

  Future<void> setCachedComments(String photoId, List<EventPhotoCommentModel> items) async {
    await initialize();
    if (!_initialized) return;

    final limited = items.take(maxCommentsCached).toList(growable: false);
    final data = limited.map(_commentToCache).toList(growable: false);
    await _commentsCache.put(_commentsKey(photoId), data, ttl: commentsTtl);
  }

  Future<void> appendCachedComment(String photoId, EventPhotoCommentModel comment) async {
    await initialize();
    if (!_initialized) return;

    final key = _commentsKey(photoId);
    final existing = _commentsCache.get(key);
    final next = <Map<String, dynamic>>[
      _commentToCache(comment),
      ...?existing?.whereType<Map>().map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)),
    ];

    await _commentsCache.put(
      key,
      next.take(maxCommentsCached).toList(growable: false),
      ttl: commentsTtl,
    );
  }

  Future<void> removeCachedComment(String photoId, String commentId) async {
    await initialize();
    if (!_initialized) return;

    final key = _commentsKey(photoId);
    final existing = _commentsCache.get(key);
    if (existing == null) return;

    final filtered = existing
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['id'] as String?) != commentId)
        .toList(growable: false);

    await _commentsCache.put(key, filtered, ttl: commentsTtl);
  }

  List<EventPhotoCommentReplyModel>? getCachedReplies(String photoId, String commentId) {
    if (!_initialized) return null;
    final raw = _repliesCache.get(_repliesKey(photoId, commentId));
    if (raw == null || raw.isEmpty) return null;

    return raw
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .map((e) => _replyFromCache(e, photoId, commentId))
        .toList(growable: false);
  }

  Future<void> setCachedReplies(
    String photoId,
    String commentId,
    List<EventPhotoCommentReplyModel> items,
  ) async {
    await initialize();
    if (!_initialized) return;

    final limited = items.take(maxRepliesCached).toList(growable: false);
    final data = limited.map(_replyToCache).toList(growable: false);
    await _repliesCache.put(_repliesKey(photoId, commentId), data, ttl: repliesTtl);
  }

  Future<void> appendCachedReply(
    String photoId,
    String commentId,
    EventPhotoCommentReplyModel reply,
  ) async {
    await initialize();
    if (!_initialized) return;

    final key = _repliesKey(photoId, commentId);
    final existing = _repliesCache.get(key);
    final next = <Map<String, dynamic>>[
      _replyToCache(reply),
      ...?existing?.whereType<Map>().map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)),
    ];

    await _repliesCache.put(
      key,
      next.take(maxRepliesCached).toList(growable: false),
      ttl: repliesTtl,
    );
  }

  Future<void> removeCachedReply(
    String photoId,
    String commentId,
    String replyId,
  ) async {
    await initialize();
    if (!_initialized) return;

    final key = _repliesKey(photoId, commentId);
    final existing = _repliesCache.get(key);
    if (existing == null) return;

    final filtered = existing
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['id'] as String?) != replyId)
        .toList(growable: false);

    await _repliesCache.put(key, filtered, ttl: repliesTtl);
  }

  Map<String, dynamic> _eventPhotoToIndexCache(EventPhotoModel item) {
    return {
      'id': item.id,
      'eventId': item.eventId,
      'userId': item.userId,
      'imageUrl': item.imageUrl,
      'thumbnailUrl': item.thumbnailUrl,
      'imageUrls': item.imageUrls,
      'thumbnailUrls': item.thumbnailUrls,
      'caption': item.caption,
      'createdAtMs': item.createdAt?.millisecondsSinceEpoch,
      'eventTitle': item.eventTitle,
      'eventEmoji': item.eventEmoji,
      'eventDateMs': item.eventDate?.millisecondsSinceEpoch,
      'eventCityId': item.eventCityId,
      'eventCityName': item.eventCityName,
      'userName': item.userName,
      'userPhotoUrl': item.userPhotoUrl,
      'status': item.status,
      'reportCount': item.reportCount,
      'likesCount': item.likesCount,
      'commentsCount': item.commentsCount,
      'taggedParticipants': item.taggedParticipants.map((p) => p.toMap()).toList(),
    };
  }

  Map<String, dynamic> _eventPhotoToPostCache(EventPhotoModel item) {
    return _eventPhotoToIndexCache(item);
  }

  EventPhotoModel _eventPhotoFromCache(Map<String, dynamic> data) {
    final taggedRaw = data['taggedParticipants'];
    final tagged = taggedRaw is List
        ? taggedRaw
            .whereType<Map>()
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .map(TaggedParticipantModel.fromMap)
            .toList(growable: false)
        : const <TaggedParticipantModel>[];

    return EventPhotoModel(
      id: (data['id'] as String?) ?? '',
      eventId: (data['eventId'] as String?) ?? '',
      userId: (data['userId'] as String?) ?? '',
      imageUrl: (data['imageUrl'] as String?) ?? '',
      thumbnailUrl: data['thumbnailUrl'] as String?,
      imageUrls: (data['imageUrls'] as List?)?.whereType<String>().toList() ?? const [],
      thumbnailUrls: (data['thumbnailUrls'] as List?)?.whereType<String>().toList() ?? const [],
      caption: data['caption'] as String?,
      createdAt: (data['createdAtMs'] as int?) != null
          ? Timestamp.fromMillisecondsSinceEpoch(data['createdAtMs'] as int)
          : null,
      eventTitle: (data['eventTitle'] as String?) ?? '',
      eventEmoji: (data['eventEmoji'] as String?) ?? '',
      eventDate: (data['eventDateMs'] as int?) != null
          ? Timestamp.fromMillisecondsSinceEpoch(data['eventDateMs'] as int)
          : null,
      eventCityId: data['eventCityId'] as String?,
      eventCityName: data['eventCityName'] as String?,
      userName: (data['userName'] as String?) ?? '',
      userPhotoUrl: (data['userPhotoUrl'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'active',
      reportCount: (data['reportCount'] as num?)?.toInt() ?? 0,
      likesCount: (data['likesCount'] as num?)?.toInt() ?? 0,
      commentsCount: (data['commentsCount'] as num?)?.toInt() ?? 0,
      taggedParticipants: tagged,
    );
  }

  Map<String, dynamic> _commentToCache(EventPhotoCommentModel comment) {
    return {
      'id': comment.id,
      'photoId': comment.photoId,
      'userId': comment.userId,
      'userName': comment.userName,
      'userPhotoUrl': comment.userPhotoUrl,
      'text': comment.text,
      'createdAtMs': comment.createdAt?.millisecondsSinceEpoch,
      'status': comment.status,
    };
  }

  EventPhotoCommentModel _commentFromCache(Map<String, dynamic> data, String photoId) {
    return EventPhotoCommentModel(
      id: (data['id'] as String?) ?? '',
      photoId: photoId,
      userId: (data['userId'] as String?) ?? '',
      userName: (data['userName'] as String?) ?? '',
      userPhotoUrl: (data['userPhotoUrl'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
      createdAt: (data['createdAtMs'] as int?) != null
          ? Timestamp.fromMillisecondsSinceEpoch(data['createdAtMs'] as int)
          : null,
      status: (data['status'] as String?) ?? 'active',
    );
  }

  Map<String, dynamic> _replyToCache(EventPhotoCommentReplyModel reply) {
    return {
      'id': reply.id,
      'photoId': reply.photoId,
      'commentId': reply.commentId,
      'userId': reply.userId,
      'userName': reply.userName,
      'userPhotoUrl': reply.userPhotoUrl,
      'text': reply.text,
      'createdAtMs': reply.createdAt?.millisecondsSinceEpoch,
      'status': reply.status,
    };
  }

  EventPhotoCommentReplyModel _replyFromCache(
    Map<String, dynamic> data,
    String photoId,
    String commentId,
  ) {
    return EventPhotoCommentReplyModel(
      id: (data['id'] as String?) ?? '',
      photoId: photoId,
      commentId: commentId,
      userId: (data['userId'] as String?) ?? '',
      userName: (data['userName'] as String?) ?? '',
      userPhotoUrl: (data['userPhotoUrl'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
      createdAt: (data['createdAtMs'] as int?) != null
          ? Timestamp.fromMillisecondsSinceEpoch(data['createdAtMs'] as int)
          : null,
      status: (data['status'] as String?) ?? 'active',
    );
  }
}
