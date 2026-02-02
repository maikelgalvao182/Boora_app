import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;
import 'package:partiu/core/services/cache/cache_key_utils.dart';
import 'package:partiu/core/services/cache/image_caches.dart';

/// Centraliza caches e chaves versionadas do app.
///
/// Objetivo:
/// - Chaves versionadas para facilitar invalidação global
/// - Cache separado por domínio (avatar, marker)
class AppCacheService {
  AppCacheService._();
  static final AppCacheService instance = AppCacheService._();

  static const int _galleryCacheVersion = 1;
  static const int _markerCacheVersion = 1;

  /// Cache para avatares usados na UI (StableAvatar) e downloads de marker
  final fcm.BaseCacheManager avatarCacheManager = AvatarImageCache.instance;

  /// Cache para PNG final do marker (bitmap)
  final fcm.BaseCacheManager markerBitmapCacheManager =
      _MarkerBitmapCacheManager();

  /// Cache para imagens de galeria do profile
  final fcm.BaseCacheManager galleryCacheManager = _GalleryImageCacheManager();

  /// Cache key para avatar (mesma do StableAvatar)
  String avatarCacheKey(String url) => stableImageCacheKey(url);

  /// Cache key versionada para PNG final do marker
  String markerBitmapCacheKey(
    String url, {
    int sizePx = 120,
  }) {
    final stableKey = stableImageCacheKey(url);
    if (stableKey.isEmpty) return stableKey;
    return 'marker:v$_markerCacheVersion:$stableKey:$sizePx';
  }

  /// Cache key versionada para imagens da galeria
  String galleryCacheKey(String url) {
    final stableKey = stableImageCacheKey(url);
    if (stableKey.isEmpty) return stableKey;
    return 'gal:v$_galleryCacheVersion:$stableKey';
  }
}

class _MarkerBitmapCacheManager extends fcm.CacheManager {
  _MarkerBitmapCacheManager()
      : super(
          fcm.Config(
            'markerBitmapCache',
            stalePeriod: const Duration(days: 7),
            maxNrOfCacheObjects: 5000,
          ),
        );
}

class _GalleryImageCacheManager extends fcm.CacheManager {
  _GalleryImageCacheManager()
      : super(
          fcm.Config(
            'galleryImageCache',
            stalePeriod: const Duration(days: 30),
            maxNrOfCacheObjects: 20000,
          ),
        );
}
