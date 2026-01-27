import 'dart:convert';

import 'package:partiu/core/models/user_preferences_cache.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';

/// Repositório de cache persistente para preferências do usuário
class UserPreferencesCacheRepository {
  static final UserPreferencesCacheRepository _instance =
      UserPreferencesCacheRepository._internal();

  factory UserPreferencesCacheRepository() => _instance;

  UserPreferencesCacheRepository._internal();

  static const String _cacheKey = 'current';
  static const Duration _defaultTtl = Duration(hours: 24);

  final HiveCacheService<UserPreferencesCache> _cache =
      HiveCacheService<UserPreferencesCache>('user_preferences');

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _cache.initialize();
    _initialized = true;
  }

  Future<UserPreferencesCache?> getCached({
    Duration maxAge = _defaultTtl,
  }) async {
    await _ensureInitialized();

    final cached = _cache.get(_cacheKey);
    if (cached == null) return null;

    final age = DateTime.now().difference(cached.cachedAt);
    if (age > maxAge) return null;

    return cached;
  }

  Future<void> cachePreferences({
    required double radiusKm,
    Map<String, dynamic>? advancedFilters,
    String? lastCategoryFilter,
    String? distanceUnit,
    Duration ttl = _defaultTtl,
  }) async {
    await _ensureInitialized();

    final sanitizedFilters = _sanitizeMap(advancedFilters);

    final cached = UserPreferencesCache(
      radiusKm: radiusKm,
      advancedFilters: sanitizedFilters,
      lastCategoryFilter: lastCategoryFilter,
      distanceUnit: distanceUnit,
      cachedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await _cache.put(_cacheKey, cached, ttl: ttl);
  }

  Map<String, dynamic>? _sanitizeMap(Map<String, dynamic>? input) {
    if (input == null) return null;
    try {
      return (jsonDecode(jsonEncode(input)) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
}