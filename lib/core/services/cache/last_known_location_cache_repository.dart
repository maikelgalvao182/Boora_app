import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:partiu/core/models/last_known_location_cache.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';

/// Repositório de cache persistente para última localização conhecida
class LastKnownLocationCacheRepository {
  static final LastKnownLocationCacheRepository _instance =
      LastKnownLocationCacheRepository._internal();

  factory LastKnownLocationCacheRepository() => _instance;

  LastKnownLocationCacheRepository._internal();

  static const String _cacheKey = 'last';
  static const Duration _defaultTtl = Duration(hours: 24);

  final HiveCacheService<LastKnownLocationCache> _cache =
      HiveCacheService<LastKnownLocationCache>('last_known_location');

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _cache.initialize();
    _initialized = true;
  }

  Future<LastKnownLocationCache?> getCached({
    Duration maxAge = _defaultTtl,
  }) async {
    await _ensureInitialized();

    final cached = _cache.get(_cacheKey);
    if (cached == null) return null;

    final age = DateTime.now().difference(cached.timestamp);
    if (age > maxAge) return null;

    return cached;
  }

  Future<void> cachePosition(
    Position position, {
    Duration ttl = _defaultTtl,
  }) async {
    await _ensureInitialized();

    final timestamp = position.timestamp ?? DateTime.now();

    final cached = LastKnownLocationCache(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestampMs: timestamp.millisecondsSinceEpoch,
    );

    await _cache.put(_cacheKey, cached, ttl: ttl);
  }

  Position toPosition(LastKnownLocationCache cached) {
    return Position(
      latitude: cached.latitude,
      longitude: cached.longitude,
      accuracy: cached.accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      timestamp: cached.timestamp,
      isMocked: false,
    );
  }
}