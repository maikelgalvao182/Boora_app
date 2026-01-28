import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/cache/media_cache_manager.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/screens/media_viewer_screen.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';

/// Widget que exibe uma ou múltiplas imagens com scroll horizontal
/// Cada imagem tem seu próprio container, igual ao composer
class EventPhotoImagesSlider extends StatefulWidget {
  const EventPhotoImagesSlider({
    super.key,
    required this.imageUrls,
    required this.thumbnailUrls,
    this.height,
    this.imageWidth = 180,
    this.spacing = 10,
    this.onDeleteImage,
  });

  final List<String> imageUrls;
  final List<String> thumbnailUrls;
  final double? height;
  final double imageWidth;
  final double spacing;
  final Future<void> Function(int index)? onDeleteImage;

  @override
  State<EventPhotoImagesSlider> createState() => _EventPhotoImagesSliderState();
}

class _EventPhotoImagesSliderState extends State<EventPhotoImagesSlider> {
  final Set<int> _deletingIndices = <int>{};

  bool _isDeleting(int index) => _deletingIndices.contains(index);

  void _openLightbox(BuildContext context, int initialIndex) {
    final items = List.generate(
      widget.imageUrls.length,
      (index) => MediaViewerItem(
        url: widget.imageUrls[index],
        heroTag: 'event_photo_${widget.imageUrls[index]}_$index',
      ),
    );

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => MediaViewerScreen(
          items: items,
          initialIndex: initialIndex,
          disableHero: true,
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

  Future<void> _confirmDelete(BuildContext context, int index) async {
    if (widget.onDeleteImage == null) return;
    final i18n = AppLocalizations.of(context);

    final confirmed = await GlimpseCupertinoDialog.showDestructive(
      context: context,
      title: i18n.translate('event_photo_remove_image_title'),
      message: i18n.translate('event_photo_remove_image_message'),
      destructiveText: i18n.translate('remove'),
      cancelText: i18n.translate('cancel'),
    );

    if (confirmed == true) {
      setState(() => _deletingIndices.add(index));
      try {
        await widget.onDeleteImage?.call(index);
      } finally {
        if (!mounted) return;
        setState(() => _deletingIndices.remove(index));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Se só tem uma imagem, exibe direto sem scroll
    if (widget.imageUrls.length == 1) {
      final imageUrl = widget.imageUrls.first;
      final thumbnailUrl = widget.thumbnailUrls.isNotEmpty ? widget.thumbnailUrls.first : null;
      final displayUrl = thumbnailUrl ?? imageUrl;
      final isThumbnail = thumbnailUrl != null && thumbnailUrl.isNotEmpty;
      final isDeleting = _isDeleting(0);

      return GestureDetector(
        onTap: () => _openLightbox(context, 0),
        onLongPress: widget.onDeleteImage != null ? () => _confirmDelete(context, 0) : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: BoxConstraints(maxWidth: widget.imageWidth),
            width: widget.imageWidth,
            height: widget.height,
            child: Stack(
              fit: widget.height != null ? StackFit.expand : StackFit.loose,
              children: [
                CachedNetworkImage(
                  imageUrl: displayUrl,
                  cacheManager: MediaCacheManager.forThumbnail(isThumbnail),
                  fit: widget.height != null ? BoxFit.cover : BoxFit.fitWidth,
                  placeholder: (_, __) => Container(
                    height: widget.height ?? 180,
                    width: widget.imageWidth,
                    color: GlimpseColors.lightTextField,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: widget.height ?? 180,
                    width: widget.imageWidth,
                    color: GlimpseColors.lightTextField,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
                if (isDeleting)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      alignment: Alignment.center,
                      child: const CupertinoActivityIndicator(radius: 14),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Múltiplas imagens: ListView horizontal com cada imagem em seu container
    return SizedBox(
      height: widget.height ?? 220,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        primary: false,
        scrollDirection: Axis.horizontal,
        itemCount: widget.imageUrls.length,
        itemBuilder: (context, index) {
          final imageUrl = widget.imageUrls[index];
          final thumbnailUrl = index < widget.thumbnailUrls.length ? widget.thumbnailUrls[index] : null;
          final displayUrl = thumbnailUrl ?? imageUrl;
          final isThumbnail = thumbnailUrl != null && thumbnailUrl.isNotEmpty;
          final isDeleting = _isDeleting(index);

          return Padding(
            padding: EdgeInsets.only(
              right: index < widget.imageUrls.length - 1 ? widget.spacing : 0,
            ),
            child: GestureDetector(
              onTap: () => _openLightbox(context, index),
              onLongPress: widget.onDeleteImage != null ? () => _confirmDelete(context, index) : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: widget.imageWidth,
                  height: widget.height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: displayUrl,
                        cacheManager: MediaCacheManager.forThumbnail(isThumbnail),
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: GlimpseColors.lightTextField),
                        errorWidget: (_, __, ___) => Container(
                          color: GlimpseColors.lightTextField,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                      if (isDeleting)
                        Container(
                          color: Colors.black.withValues(alpha: 0.45),
                          alignment: Alignment.center,
                          child: const CupertinoActivityIndicator(radius: 14),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
