import 'package:flutter/foundation.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/core/services/cache/hive_initializer.dart';

/// Cache persistente para stats agregadas de reviews
///
/// TTL padrão: 6h
class ReviewStatsCacheService {
  ReviewStatsCacheService._();

  static final ReviewStatsCacheService instance = ReviewStatsCacheService._();

  static const Duration defaultTtl = Duration(hours: 6);

  final HiveCacheService<Map<String, dynamic>> _cache =
      HiveCacheService<Map<String, dynamic>>('profile_review_stats_cache');

  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await HiveInitializer.initialize();
    try {
      await _cache.initialize();
      _initialized = true;
    } catch (e) {
      debugPrint('📦 ReviewStatsCacheService init error: $e');
    }
  }

  Map<String, dynamic>? get(String userId) {
    if (!_initialized) return null;
    if (userId.trim().isEmpty) return null;
    return _cache.get(_key(userId));
  }

  Future<void> put(
    String userId,
    Map<String, dynamic> data, {
    Duration ttl = defaultTtl,
  }) async {
    if (userId.trim().isEmpty) return;
    await ensureInitialized();
    if (!_initialized) return;
    await _cache.put(_key(userId), _sanitize(data), ttl: ttl);
  }

  String _key(String userId) => 'stats:$userId';

  Map<String, dynamic> _sanitize(Map<String, dynamic> data) {
    final safe = <String, dynamic>{};

    void putNum(String key) {
      final value = data[key];
      if (value is num) {
        safe[key] = value;
      }
    }

    void putMap(String key) {
      final value = data[key];
      if (value is Map) {
        final cleaned = <String, dynamic>{};
        for (final entry in value.entries) {
          final k = entry.key.toString();
          final v = entry.value;
          if (v is num) cleaned[k] = v;
        }
        if (cleaned.isNotEmpty) safe[key] = cleaned;
      }
    }

    void putDate(String key) {
      final value = data[key];
      if (value is DateTime) {
        safe[key] = value.toIso8601String();
      } else if (value is String && value.trim().isNotEmpty) {
        safe[key] = value;
      }
    }

    putNum('totalReviews');
    putNum('total_reviews');
    putNum('overallRating');
    putNum('overall_rating');
    putMap('ratingBuckets');
    putMap('ratingsBreakdown');
    putMap('ratings_breakdown');
    putMap('badgesCount');
    putMap('badges_count');
    putDate('lastReviewAt');
    putDate('lastUpdated');
    putDate('last_updated');

    return safe;
  }
}
