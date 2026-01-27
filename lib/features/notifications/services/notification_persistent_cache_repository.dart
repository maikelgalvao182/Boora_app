import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/features/notifications/models/notification_cache_item.dart';

/// Cache persistente para notificações (cold start)
class NotificationPersistentCacheRepository {
  static final NotificationPersistentCacheRepository _instance =
      NotificationPersistentCacheRepository._internal();

  factory NotificationPersistentCacheRepository() => _instance;

  NotificationPersistentCacheRepository._internal();

  static const Duration _defaultTtl = Duration(minutes: 20);

  final HiveListCacheService<NotificationCacheItem> _cache =
      HiveListCacheService<NotificationCacheItem>('notifications_cache', maxItems: 100);

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _cache.initialize();
    _initialized = true;
  }

  String _buildKey(String userId, String? filterKey) {
    final filter = filterKey ?? 'all';
    return 'user_${userId}_$filter';
  }

  Future<List<NotificationCacheItem>?> getCached(
    String userId,
    String? filterKey,
  ) async {
    await _ensureInitialized();
    return _cache.get(_buildKey(userId, filterKey));
  }

  Future<void> cacheNotifications(
    String userId,
    String? filterKey,
    List<NotificationCacheItem> items, {
    Duration ttl = _defaultTtl,
  }) async {
    await _ensureInitialized();
    await _cache.put(_buildKey(userId, filterKey), items, ttl: ttl);
  }

  Future<void> clearFilter(String userId, String? filterKey) async {
    await _ensureInitialized();
    await _cache.delete(_buildKey(userId, filterKey));
  }
}