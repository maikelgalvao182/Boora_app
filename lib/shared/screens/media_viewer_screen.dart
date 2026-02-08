import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Representa um item de mídia (apenas imagens)
class MediaViewerItem {
  const MediaViewerItem({
    required this.url,
    required this.heroTag,
  });
  
  final String url;
  final String heroTag; // tag utilizada no Hero
}

/// Tela fullscreen que permite swipe entre imagens.
/// Usa InteractiveViewer para zoom.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    required this.items,
    super.key,
    this.initialIndex = 0,
    this.disableHero = false,
  });
  
  final List<MediaViewerItem> items;
  final int initialIndex;
  final bool disableHero; // Quando true, pula animação Hero (rota fade pura)

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late PageController _pageController;
  int _current = 0;
  bool _uiVisible = true;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _current = index);
  }

  void _toggleUI() {
    setState(() => _uiVisible = !_uiVisible);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Conteúdo principal (imagens)
          PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: widget.items.length,
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return GestureDetector(
                onTap: _toggleUI,
                child: _buildImagePage(item),
              );
            },
          ),
          
          // UI overlay (botão fechar e indicador)
          if (_uiVisible)
            SafeArea(
              child: Column(
                children: [
                  // Botão fechar
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Material(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(20.r),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Indicador de página
                  if (widget.items.length > 1)
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        _buildPageIndicatorText(context),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _buildPageIndicatorText(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final template = i18n.translate('media_viewer_page_indicator');
    final current = (_current + 1).toString();
    final total = widget.items.length.toString();

    if (template.isEmpty) {
      return '$current / $total';
    }

    return template.replaceAll('{current}', current).replaceAll('{total}', total);
  }

  Widget _buildImagePage(MediaViewerItem item) {
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 4.0,
      child: Center(
        child: widget.disableHero
            ? CachedNetworkImage(
                imageUrl: item.url,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CupertinoActivityIndicator(color: Colors.white),
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 48,
                ),
              )
            : Hero(
                tag: item.heroTag,
                child: CachedNetworkImage(
                  imageUrl: item.url,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CupertinoActivityIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) => const Icon(
                    Icons.broken_image,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
      ),
    );
  }
}
