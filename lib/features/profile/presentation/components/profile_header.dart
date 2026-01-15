import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:circle_flags/circle_flags.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/services/cache/cache_key_utils.dart';
import 'package:partiu/core/services/cache/image_caches.dart';
import 'package:partiu/core/services/cache/image_cache_stats.dart';
import 'package:partiu/core/constants/glimpse_variables.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

/// Header principal do perfil com foto, nome, idade e informações básicas
/// 
/// Inclui:
/// - Foto de perfil com overlay de gradiente
/// - Nome, idade, profissão e localização
/// - Sistema reativo via UserStore
class ProfileHeader extends StatefulWidget {

  const ProfileHeader({
    required this.user,
    required this.isMyProfile,
    required this.i18n,
    super.key,
  });

  final User user;
  final bool isMyProfile;
  final AppLocalizations i18n;

  @override
  State<ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<ProfileHeader> {
  late final ValueNotifier<String> _imageUrlNotifier;
  late final PageController _pageController;

  Timer? _autoSwipeTimer;
  Timer? _autoSwipeResumeTimer;
  bool _isUserInteracting = false;

  List<String> _galleryImageUrls = const <String>[];
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _imageUrlNotifier = ValueNotifier<String>(_getFirstValidImage());
    _pageController = PageController();
    _galleryImageUrls = _extractGalleryImageUrls(widget.user.userGallery);
    
    // Observa mudanças na foto via UserStore
    final avatarNotifier = UserStore.instance.getAvatarNotifier(widget.user.userId);
    avatarNotifier.addListener(_updateAvatar);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _configureAutoSwipe();
    });
  }

  @override
  void didUpdateWidget(covariant ProfileHeader oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.user.userGallery != oldWidget.user.userGallery) {
      _galleryImageUrls = _extractGalleryImageUrls(widget.user.userGallery);
      if (_currentPage >= _pageCountFor(_imageUrlNotifier.value)) {
        _currentPage = 0;
        _pageController.jumpToPage(0);
      }

      _configureAutoSwipe();
    }
  }

  void _updateAvatar() {
    final avatarNotifier = UserStore.instance.getAvatarNotifier(widget.user.userId);
    final provider = avatarNotifier.value;

    String? url;
    if (provider is NetworkImage) {
      url = provider.url;
    } else if (provider is CachedNetworkImageProvider) {
      url = provider.url;
    }

    if (url != null && url.isNotEmpty && url != _imageUrlNotifier.value) {
      _imageUrlNotifier.value = url;

      final newTotal = _pageCountFor(url);
      if (_currentPage >= newTotal) {
        setState(() => _currentPage = 0);
        _pageController.jumpToPage(0);
      }

      _configureAutoSwipe();
    }
  }

  @override
  void dispose() {
    final avatarNotifier = UserStore.instance.getAvatarNotifier(widget.user.userId);
    avatarNotifier.removeListener(_updateAvatar);
    _imageUrlNotifier.dispose();
    _pageController.dispose();
    _stopAutoSwipeTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1 / 1.4,
        child: Stack(
          children: [
            // Imagem de fundo
            _buildImageSlider(),
            
            // Gradiente overlay
            _buildGradientOverlay(),
            
            // Informações do usuário
            _buildUserInfo(),

            // Indicador de páginas (apenas quando há múltiplas imagens)
            _buildPageIndicatorOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSlider() {
    return ValueListenableBuilder<String>(
      valueListenable: _imageUrlNotifier,
      builder: (context, imageUrl, _) {
        final pages = _buildPages(imageUrl);

        if (pages.isEmpty) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.grey[300],
            child: const Icon(
              Icons.person,
              size: 100,
              color: Colors.white,
            ),
          );
        }

        if (pages.length == 1) {
          return _buildCachedImage(pages.first);
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification && notification.dragDetails != null) {
              _onUserInteractionStart();
            } else if (notification is ScrollEndNotification) {
              _onUserInteractionEnd();
            }
            return false;
          },
          child: PageView.builder(
            controller: _pageController,
            itemCount: pages.length,
            onPageChanged: (index) {
              if (index == _currentPage) return;
              setState(() => _currentPage = index);
              _precacheAdjacent(pages, index);
            },
            itemBuilder: (context, index) {
              final url = pages[index];
              return _buildCachedImage(url);
            },
          ),
        );
      },
    );
  }

  Widget _buildCachedImage(String imageUrl) {
    if (imageUrl.isEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.grey[300],
        child: const Icon(
          Icons.person,
          size: 100,
          color: Colors.white,
        ),
      );
    }

    final key = stableImageCacheKey(imageUrl);
    ImageCacheStats.instance.record(
      category: ImageCacheCategory.chatMedia,
      url: imageUrl,
      cacheKey: key,
    );

    return CachedNetworkImage(
      key: ValueKey(key),
      imageUrl: imageUrl,
      cacheManager: ChatMediaImageCache.instance,
      cacheKey: key,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      placeholder: (context, _) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.grey[200],
          child: const Center(
            child: CupertinoActivityIndicator(),
          ),
        );
      },
      errorWidget: (context, _, __) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.grey[300],
          child: const Icon(
            Icons.person,
            size: 100,
            color: Colors.white,
          ),
        );
      },
    );
  }

  Widget _buildPageIndicatorOverlay() {
    return ValueListenableBuilder<String>(
      valueListenable: _imageUrlNotifier,
      builder: (context, imageUrl, _) {
        final total = _buildPages(imageUrl).length;
        if (total <= 1) return const SizedBox.shrink();

        return Positioned(
          top: 14,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(total, (index) {
                final isActive = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      // IgnorePointer: garante que o swipe do PageView funcione (overlay não captura gestos)
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.7),
              ],
              stops: const [0.5, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  void _configureAutoSwipe() {
    if (!mounted) return;

    final total = _pageCountFor(_imageUrlNotifier.value);
    if (total <= 1) {
      _stopAutoSwipeTimers();
      return;
    }

    if (_autoSwipeTimer != null) {
      // já rodando
      return;
    }

    _autoSwipeTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _autoAdvanceIfPossible(),
    );
  }

  void _stopAutoSwipeTimers() {
    _autoSwipeTimer?.cancel();
    _autoSwipeTimer = null;
    _autoSwipeResumeTimer?.cancel();
    _autoSwipeResumeTimer = null;
  }

  void _pauseAutoSwipe() {
    _autoSwipeTimer?.cancel();
    _autoSwipeTimer = null;
  }

  void _scheduleAutoSwipeResume() {
    _autoSwipeResumeTimer?.cancel();
    _autoSwipeResumeTimer = Timer(
      const Duration(seconds: 5),
      () {
        if (!mounted) return;
        if (_isUserInteracting) return;
        _configureAutoSwipe();
      },
    );
  }

  void _onUserInteractionStart() {
    _isUserInteracting = true;
    _pauseAutoSwipe();
    _autoSwipeResumeTimer?.cancel();
    _autoSwipeResumeTimer = null;
  }

  void _onUserInteractionEnd() {
    _isUserInteracting = false;
    _scheduleAutoSwipeResume();
  }

  void _autoAdvanceIfPossible() {
    if (!mounted) return;
    if (_isUserInteracting) return;
    if (!_pageController.hasClients) return;

    final pages = _buildPages(_imageUrlNotifier.value);
    if (pages.length <= 1) return;

    final nextIndex = (_currentPage + 1) % pages.length;
    if (nextIndex == _currentPage) return;

    setState(() => _currentPage = nextIndex);
    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
    _precacheAdjacent(pages, nextIndex);
  }

  Widget _buildUserInfo() {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nome, Idade com Bandeira
          _buildNameWithAgeAndFlag(),
          
          const SizedBox(height: 8),
          
          // Localização (Cidade, Estado)
          _buildLocationWithState(),
          
          const SizedBox(height: 8),
          
          // Instagram
          _buildInstagram(),
        ],
      ),
    );
  }

  Widget _buildNameWithAgeAndFlag() {
    return ValueListenableBuilder<String?>(
      valueListenable: UserStore.instance.getFromNotifier(widget.user.userId),
      builder: (context, from, _) {
        // Obtém informações do país se disponível
        final countryInfo = (from != null && from.isNotEmpty) ? getCountryInfo(from) : null;
        
        return Row(
          children: [
            // Bandeira do país (se disponível)
            if (countryInfo != null) ...[
              CircleFlag(
                countryInfo.flagCode,
                size: 20,
              ),
              const SizedBox(width: 8),
            ],
            
            // Nome com badge
            Flexible(
              child: ReactiveUserNameWithBadge(
                userId: widget.user.userId,
                style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                iconSize: 18,
                spacing: 8,
              ),
            ),
            
            // Idade removida daqui e movida para AboutMeSection
          ],
        );
      },
    );
  }

  Widget _buildLocationWithState() {
    return ValueListenableBuilder<String?>(
      valueListenable: UserStore.instance.getCityNotifier(widget.user.userId),
      builder: (context, city, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: UserStore.instance.getStateNotifier(widget.user.userId),
          builder: (context, state, _) {
            final parts = <String>[];
            if (city != null && city.isNotEmpty) parts.add(city);
            if (state != null && state.isNotEmpty) parts.add(state);
            
            if (parts.isEmpty) return const SizedBox.shrink();
            
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Iconsax.location,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 8),
                Text(
                  parts.join(', '),
                  style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildInstagram() {
    return ValueListenableBuilder<String?>(
      valueListenable: UserStore.instance.getInstagramNotifier(widget.user.userId),
      builder: (context, instagram, _) {
        if (instagram == null || instagram.isEmpty) return const SizedBox.shrink();
        
        return GestureDetector(
          onTap: () => _openInstagram(instagram),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Iconsax.instagram,
                size: 18,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Text(
                instagram,
                style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.8),
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openInstagram(String username) async {
    // Remove @ se estiver presente
    final cleanUsername = username.replaceAll('@', '');
    final url = Uri.parse('https://www.instagram.com/$cleanUsername');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _getFirstValidImage() {
    // Usa photoUrl (campo unificado)
    if (widget.user.photoUrl.isNotEmpty) {
      return widget.user.photoUrl;
    }
    
    // Fallback: galeria
    if (widget.user.userGallery != null && widget.user.userGallery!.isNotEmpty) {
      final urls = _extractGalleryImageUrls(widget.user.userGallery);
      if (urls.isNotEmpty) return urls.first;
    }
    
    return '';
  }

  List<String> _buildPages(String imageUrl) {
    final pages = <String>[];
    if (imageUrl.isNotEmpty) {
      pages.add(imageUrl);
    }
    if (_galleryImageUrls.isNotEmpty) {
      for (final url in _galleryImageUrls) {
        if (url.isEmpty) continue;
        if (url == imageUrl) continue;
        pages.add(url);
      }
    }
    return pages;
  }

  int _pageCountFor(String imageUrl) {
    return _buildPages(imageUrl).length;
  }

  List<String> _extractGalleryImageUrls(Map<String, dynamic>? gallery) {
    if (gallery == null || gallery.isEmpty) return const <String>[];

    final urls = <String>[];
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

    // Remove duplicados preservando ordem
    final seen = <String>{};
    final unique = <String>[];
    for (final url in urls) {
      if (seen.add(url)) unique.add(url);
    }
    return unique;
  }

  void _precacheAdjacent(List<String> pages, int currentIndex) {
    final nextIndex = currentIndex + 1;
    if (nextIndex < 0 || nextIndex >= pages.length) return;

    final url = pages[nextIndex];
    if (url.isEmpty) return;

    final key = stableImageCacheKey(url);
    final provider = CachedNetworkImageProvider(
      url,
      cacheManager: ChatMediaImageCache.instance,
      cacheKey: key,
    );
    precacheImage(provider, context);
  }
}
