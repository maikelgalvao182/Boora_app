import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/services/global_cache_service.dart';
import 'package:partiu/core/services/cache/app_cache_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/screens/media_viewer_screen.dart';

/// Gallery section widget exibindo grid de imagens
/// 
/// - Espaçamento superior: 24px
/// - Espaçamento inferior: 36px  
/// - Padding horizontal: 20px
/// - Grid 3 colunas, aspect ratio 4:5
/// - Auto-oculta se galeria vazia
class GalleryProfileSection extends StatelessWidget {

  const GalleryProfileSection({
    required this.galleryMap, 
    super.key,
    this.title,
    this.titleColor,
    this.maxRows = 6,
    this.columns = 3,
    this.aspectRatio = 4 / 5,
  });
  
  final Map<String, dynamic>? galleryMap;
  final String? title;
  final Color? titleColor;
  final int maxRows;
  final int columns;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final effectiveTitleColor = titleColor ?? GlimpseColors.primaryColorLight;
    
    // ✅ AUTO-OCULTA: não renderiza seção vazia
    if (galleryMap == null || galleryMap!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Extrai URLs das imagens (com cache de 10 min para galerias)
    final imageUrls = _getImageUrlsCached(galleryMap!);
    if (imageUrls.isEmpty) return const SizedBox.shrink();
    
    final maxItems = columns * maxRows;
    final limited = imageUrls.take(maxItems).toList();
    
    return Container(
      padding: GlimpseStyles.profileSectionPadding,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            title ?? i18n.translate('gallery_section_title'),
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: effectiveTitleColor,
            ),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 16),
          
          // Grid
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: aspectRatio,
            ),
            itemCount: limited.length,
            itemBuilder: (context, index) {
              final imageUrl = limited[index];
              return _ImageThumb(
                key: ValueKey(imageUrl),
                imageUrl: imageUrl,
                onTap: () => _openGalleryViewer(context, imageUrls, index),
              );
            },
          ),
        ],
      ),
    );
  }
  
  /// Obtém URLs da galeria com cache (TTL: 6h)
  /// Galerias mudam raramente, então cache mais longo é apropriado
  List<String> _getImageUrlsCached(Map<String, dynamic> gallery) {
    final cacheKey = 'gallery_${gallery.hashCode}';
    
    // Tenta obter do cache
    final cached = GlobalCacheService.instance.get<List<String>>(cacheKey);
    if (cached != null) return cached;
    
    // Extrai e cacheia
    final urls = _extractImageUrls(gallery);
    GlobalCacheService.instance.set(
      cacheKey, 
      urls, 
      ttl: const Duration(hours: 6),
    );
    
    return urls;
  }
  
  List<String> _extractImageUrls(Map<String, dynamic> gallery) {
    final urls = <String>[];
    
    // Ordena pelas chaves numéricas
    final entries = gallery.entries.where((e) => e.value != null).toList();
    entries.sort((a, b) {
      int parseKey(String k) {
        final numPart = RegExp(r'(\d+)').firstMatch(k)?.group(1);
        return int.tryParse(numPart ?? k) ?? 0;
      }
      return parseKey(a.key).compareTo(parseKey(b.key));
    });
    
    for (final e in entries) {
      final val = e.value;
      final url = val is Map ? (val['url'] ?? '').toString() : val.toString();
      if (url.isNotEmpty) {
        urls.add(url);
      }
    }
    
    return urls;
  }
  
  /// Abre o visualizador de imagens em tela cheia com transição fade
  void _openGalleryViewer(BuildContext context, List<String> urls, int initialIndex) {
    final items = urls.map((url) => MediaViewerItem(
      url: url,
      heroTag: 'gallery_$url',
    )).toList();
    
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => MediaViewerScreen(
          items: items,
          initialIndex: initialIndex,
          disableHero: true, // Desabilita Hero, usa fade puro
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({
    required this.imageUrl,
    required this.onTap,
    super.key,
  });
  
  final String imageUrl;
  final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            cacheManager: AppCacheService.instance.galleryCacheManager,
            cacheKey: AppCacheService.instance.galleryCacheKey(imageUrl),
            placeholder: (context, url) => Container(
              color: GlimpseColors.lightTextField,
              child: const Center(
                child: CupertinoActivityIndicator(
                  radius: 14,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: GlimpseColors.lightTextField,
              child: const Center(
                child: Icon(
                  Icons.photo_outlined,
                  color: Colors.white70,
                  size: 28,
                ),
              ),
            ),
            fadeInDuration: const Duration(milliseconds: 200),
            fadeOutDuration: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
  }
}
