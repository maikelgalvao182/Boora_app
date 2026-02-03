import 'package:flutter/foundation.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/core/services/cache/hive_initializer.dart';
import 'package:partiu/features/home/data/models/ranking_filters_model.dart';
import 'package:partiu/features/home/data/models/user_ranking_model.dart';

class PeopleRankingCacheService {
  static const Duration rankingTtl = Duration(hours: 6);
  static const Duration filtersTtl = Duration(minutes: 30);

  final HiveCacheService<List> _rankingCache =
      HiveCacheService<List>('people_ranking_cache');
  final HiveCacheService<Map> _filtersCache =
      HiveCacheService<Map>('people_ranking_filters');

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    await HiveInitializer.initialize();

    try {
      await _rankingCache.initialize();
      await _filtersCache.initialize();
      _initialized = true;
    } catch (e) {
      debugPrint('📦 PeopleRankingCache init error: $e');
    }
  }

  List<UserRankingModel>? getCachedRanking(String key) {
    if (!_initialized) return null;
    final raw = _rankingCache.get(key);
    if (raw == null || raw.isEmpty) return null;

    return raw
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .map(UserRankingModel.fromMap)
        .toList(growable: false);
  }

  Future<void> setCachedRanking(String key, List<UserRankingModel> items) async {
    await initialize();
    if (!_initialized) return;

    final data = items.map((e) => e.toMap()).toList(growable: false);
    await _rankingCache.put(key, data, ttl: rankingTtl);
  }

  RankingFilters? getCachedFilters({String key = 'current'}) {
    if (!_initialized) return null;
    final raw = _filtersCache.get(key);
    if (raw == null || raw.isEmpty) return null;
    return RankingFilters.fromMap(Map<String, dynamic>.from(raw));
  }

  Future<void> setCachedFilters(RankingFilters filters, {String key = 'current'}) async {
    await initialize();
    if (!_initialized) return;

    await _filtersCache.put(key, filters.toMap(), ttl: filtersTtl);
  }
}
