import 'package:flutter/foundation.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/core/services/cache/hive_initializer.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';

/// Cache persistente de páginas de reviews (primeira página tem maior ROI)
///
/// TTL padrão: 6h
class ReviewPageCacheService {
  ReviewPageCacheService._();

  static final ReviewPageCacheService instance = ReviewPageCacheService._();

  static const Duration defaultTtl = Duration(hours: 6);

  final HiveCacheService<List> _cache =
      HiveCacheService<List>('profile_review_page_cache');

  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await HiveInitializer.initialize();
    try {
      await _cache.initialize();
      _initialized = true;
    } catch (e) {
      debugPrint('📦 ReviewPageCacheService init error: $e');
    }
  }

  List<ReviewModel>? getPage(String userId, int page) {
    if (!_initialized) return null;
    if (userId.trim().isEmpty) return null;

    final raw = _cache.get(_key(userId, page));
    if (raw == null || raw.isEmpty) return null;

    final items = raw
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .map(_fromCache)
        .toList(growable: false);

    return items.isEmpty ? null : items;
  }

  Future<void> putPage(
    String userId,
    int page,
    List<ReviewModel> reviews, {
    Duration ttl = defaultTtl,
  }) async {
    if (userId.trim().isEmpty) return;
    await ensureInitialized();
    if (!_initialized) return;

    final data = reviews.map(_toCache).toList(growable: false);
    if (data.isEmpty) return;

    await _cache.put(_key(userId, page), data, ttl: ttl);
  }

  String _key(String userId, int page) => 'reviews_page:$userId:$page';

  Map<String, dynamic> _toCache(ReviewModel review) {
    return {
      'review_id': review.reviewId,
      'event_id': review.eventId,
      'reviewer_id': review.reviewerId,
      'reviewee_id': review.revieweeId,
      'reviewer_role': review.reviewerRole,
      'criteria_ratings': review.criteriaRatings,
      'overall_rating': review.overallRating,
      'badges': review.badges,
      if (review.comment != null && review.comment!.isNotEmpty)
        'comment': review.comment,
      'created_at': review.createdAt.toIso8601String(),
      'updated_at': review.updatedAt.toIso8601String(),
      if (review.reviewerName != null) 'reviewer_name': review.reviewerName,
      if (review.reviewerPhotoUrl != null)
        'reviewer_photo_url': review.reviewerPhotoUrl,
    };
  }

  ReviewModel _fromCache(Map<String, dynamic> data) {
    // Hive retorna Map<dynamic, dynamic>, precisa converter
    final criteriaRawDynamic = data['criteria_ratings'];
    final Map<String, int> criteriaRatings;
    if (criteriaRawDynamic is Map) {
      criteriaRatings = Map<String, int>.from(
        criteriaRawDynamic.map((key, value) => MapEntry(key.toString(), (value as num).toInt())),
      );
    } else {
      criteriaRatings = {};
    }

    final badgesRaw = data['badges'] as List<dynamic>?;
    final badges = badgesRaw?.map((e) => e.toString()).toList() ?? [];

    return ReviewModel(
      reviewId: data['review_id'] as String? ?? '',
      eventId: data['event_id'] as String? ?? '',
      reviewerId: data['reviewer_id'] as String? ?? '',
      revieweeId: data['reviewee_id'] as String? ?? '',
      reviewerRole: data['reviewer_role'] as String? ?? '',
      criteriaRatings: criteriaRatings,
      overallRating: (data['overall_rating'] as num?)?.toDouble() ?? 0.0,
      badges: badges,
      comment: data['comment'] as String?,
      createdAt: _parseDateTime(data['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(data['updated_at']) ?? DateTime.now(),
      reviewerName: data['reviewer_name'] as String?,
      reviewerPhotoUrl: data['reviewer_photo_url'] as String?,
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
