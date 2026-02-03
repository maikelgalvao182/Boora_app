import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:partiu/core/services/cache/cache_key_utils.dart';
import 'package:partiu/core/services/cache/image_caches.dart';
import 'package:partiu/core/services/cache/image_cache_stats.dart';

class ImageLightbox extends StatelessWidget {

  const ImageLightbox({required this.imageUrl, super.key, this.heroTag});
  final String imageUrl;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Fullscreen zoomable image
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Builder(
                  builder: (context) {
                    final key = stableImageCacheKey(imageUrl);
                    ImageCacheStats.instance.record(
                      category: ImageCacheCategory.chatMedia,
                      url: imageUrl,
                      cacheKey: key,
                    );

                    return CachedNetworkImage(
                      imageUrl: imageUrl,
                      cacheManager: ChatMediaImageCache.instance,
                      cacheKey: key,
                  fit: BoxFit.contain,
                  placeholder: (context, _) => const SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: Center(
                      child: CupertinoActivityIndicator(color: Colors.white),
                    ),
                  ),
                  errorWidget: (context, _, __) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 96,
                  ),
                    );
                  },
                ),
              ),
            ),

            // Close button
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
