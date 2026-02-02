import 'package:flutter/foundation.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/core/services/cache/hive_initializer.dart';

/// Cache persistente para páginas de galeria do perfil
///
/// TTL padrão: 7d
class ProfileGalleryCacheService {
  ProfileGalleryCacheService._();

  static final ProfileGalleryCacheService instance = ProfileGalleryCacheService._();

  static const Duration defaultTtl = Duration(days: 7);

  final HiveCacheService<List> _cache =
      HiveCacheService<List>('profile_gallery_page_cache');

  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await HiveInitializer.initialize();
    try {
      await _cache.initialize();
      _initialized = true;
    } catch (e) {
      debugPrint('📦 ProfileGalleryCacheService init error: $e');
    }
  }

  List<String>? getPage(String userId, int page) {
    if (!_initialized) return null;
    if (userId.trim().isEmpty) return null;

    final raw = _cache.get(_key(userId, page));
    if (raw == null || raw.isEmpty) return null;

    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> putPage(
    String userId,
    int page,
    List<String> urls, {
    Duration ttl = defaultTtl,
  }) async {
    if (userId.trim().isEmpty) return;
    await ensureInitialized();
    if (!_initialized) return;

    final sanitized = urls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    if (sanitized.isEmpty) return;
    await _cache.put(_key(userId, page), sanitized, ttl: ttl);
  }

  Future<void> invalidateUserGallery(String userId) async {
    if (userId.trim().isEmpty) return;
    await ensureInitialized();
    if (!_initialized) return;
    await _cache.delete(_key(userId, 0));
  }

  String _key(String userId, int page) => 'gallery_page:$userId:$page';
}
