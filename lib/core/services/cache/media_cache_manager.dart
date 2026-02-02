import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class MediaCacheManager {
  static final CacheManager thumbnail = CacheManager(
    Config(
      'event_photo_thumbs_cache',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 500,
    ),
  );

  static final CacheManager fullImage = CacheManager(
    Config(
      'event_photo_full_cache',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 300,
    ),
  );

  static CacheManager forThumbnail(bool isThumbnail) {
    return isThumbnail ? thumbnail : fullImage;
  }

  static Future<void> prefetchThumbnails(
    List<String> urls, {
    int maxItems = 8,
  }) async {
    if (urls.isEmpty) return;

    final unique = <String>{};
    for (final url in urls) {
      if (url.trim().isEmpty) continue;
      unique.add(url.trim());
      if (unique.length >= maxItems) break;
    }

    for (final url in unique) {
      try {
        await thumbnail.downloadFile(url);
      } catch (_) {
        // Ignorar erro de prefetch
      }
    }
  }
}