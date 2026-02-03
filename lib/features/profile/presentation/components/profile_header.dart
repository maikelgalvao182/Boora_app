import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:circle_flags/circle_flags.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/services/cache/cache_key_utils.dart';
import 'package:partiu/core/services/cache/image_caches.dart';
import 'package:partiu/core/services/cache/image_cache_stats.dart';
import 'package:partiu/core/constants/glimpse_variables.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/stores/user_store.dart';

/// Header principal do perfil com foto, nome, idade e informações básicas
/// 
/// Inclui:
/// - Foto de perfil com overlay de gradiente
/// - Nome, idade, profissão e localização
/// - Renderiza dados estáticos do perfil
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
  
  // ValueNotifier para followers count - evita rebuild de todo o widget
  late final ValueNotifier<int?> _followersCountNotifier;

  @override
  void initState() {
    super.initState();
    _imageUrlNotifier = ValueNotifier<String>(_getFirstValidImage());
    _pageController = PageController();
    _galleryImageUrls = _extractGalleryImageUrls(widget.user.userGallery);
    _followersCountNotifier = ValueNotifier<int?>(null);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _configureAutoSwipe();
    });
    
    // Carrega followers count uma vez no init (sem setState)
    _loadFollowersCount();
  }
  
  Future<void> _loadFollowersCount() async {
    const maxRetries = 3;
    var retryCount = 0;
    
    while (retryCount < maxRetries) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('Users')
            .doc(widget.user.userId)
            .collection('followers')
            .count()
            .get();
        
        if (mounted) {
          _followersCountNotifier.value = snapshot.count ?? 0;
        }
        return; // Sucesso, sai do loop
        
      } catch (e) {
        retryCount++;
        
        if (retryCount >= maxRetries) {
          debugPrint('❌ [ProfileHeader] Erro ao carregar followers count após $maxRetries tentativas: $e');
          // Em caso de erro final, não mostra nada
          return;
        }
        
        // Backoff exponencial: 500ms, 1s, 2s
        final delayMs = 500 * (1 << (retryCount - 1));
        debugPrint('⚠️ [ProfileHeader] Tentativa $retryCount falhou, retrying em ${delayMs}ms...');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  @override
  void didUpdateWidget(covariant ProfileHeader oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.user.photoUrl != oldWidget.user.photoUrl) {
      final newUrl = _getFirstValidImage();
      if (newUrl != _imageUrlNotifier.value) {
        _imageUrlNotifier.value = newUrl;
        final newTotal = _pageCountFor(newUrl);
        if (_currentPage >= newTotal) {
          _currentPage = 0;
          _pageController.jumpToPage(0);
        }
        _configureAutoSwipe();
      }
    }

    if (widget.user.userGallery != oldWidget.user.userGallery) {
      _galleryImageUrls = _extractGalleryImageUrls(widget.user.userGallery);
      if (_currentPage >= _pageCountFor(_imageUrlNotifier.value)) {
        _currentPage = 0;
        _pageController.jumpToPage(0);
      }

      _configureAutoSwipe();
    }
  }

  @override
  void dispose() {
    _imageUrlNotifier.dispose();
    _followersCountNotifier.dispose();
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
            
            // Zonas de tap nas bordas (por cima de tudo para capturar gestos)
            _buildTapZones(),
          ],
        ),
      ),
    );
  }
  
  /// Constrói zonas de tap transparentes nas bordas esquerda e direita
  /// para avançar/recuar na galeria. Posicionadas no topo do Stack para
  /// garantir que capturam os taps mesmo sobre outros overlays.
  Widget _buildTapZones() {
    return ValueListenableBuilder<String>(
      valueListenable: _imageUrlNotifier,
      builder: (context, imageUrl, _) {
        final pages = _buildPages(imageUrl);
        if (pages.length <= 1) return const SizedBox.shrink();
        
        return Positioned.fill(
          child: Row(
            children: [
              // Zona esquerda (recuar) - apenas metade superior para não cobrir userInfo
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      flex: 2, // 2/3 superior
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _goToPreviousPage(pages.length),
                      ),
                    ),
                    const Expanded(flex: 1, child: SizedBox()), // 1/3 inferior (userInfo)
                  ],
                ),
              ),
              // Zona direita (avançar) - apenas metade superior
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      flex: 2, // 2/3 superior
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _goToNextPage(pages.length),
                      ),
                    ),
                    const Expanded(flex: 1, child: SizedBox()), // 1/3 inferior (userInfo)
                  ],
                ),
              ),
            ],
          ),
        );
      },
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

  /// Badge que exibe a contagem de seguidores no canto superior direito (estilo Instagram)
  Widget _buildFollowersBadge() {
    return Positioned(
      top: 14,
      right: 14,
      child: FutureBuilder<AggregateQuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('Users')
            .doc(widget.user.userId)
            .collection('followers')
            .count()
            .get(),
        builder: (context, snapshot) {
          // Não mostra nada enquanto carrega ou se não tem dados
          if (!snapshot.hasData) {
            return const SizedBox.shrink();
          }
          
          final count = snapshot.data!.count ?? 0;
          
          // Não mostra badge se não tem seguidores
          if (count == 0) {
            return const SizedBox.shrink();
          }
          
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Iconsax.people5,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatFollowersCount(count),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black54,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfo() {
    final hasLocation = widget.user.userLocality.trim().isNotEmpty ||
        (widget.user.userState?.trim().isNotEmpty ?? false);
    // 🔒 DESATIVADO: Campo country/origin removido da UI
    // final hasOrigin = widget.user.from?.trim().isNotEmpty ?? false;
    final hasInstagram = widget.user.userInstagram?.trim().isNotEmpty ?? false;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Informações não-clicáveis envolvidas em IgnorePointer
          // para permitir swipe horizontal na galeria
          IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNameWithAgeAndFlag(),
                if (hasLocation) const SizedBox(height: 8),
                if (hasLocation) _buildLocationWithState(),
              ],
            ),
          ),
          // 🔒 DESATIVADO: Campo country/origin removido da UI
          // if (hasOrigin) const SizedBox(height: 8),
          // if (hasOrigin) _buildOriginFrom(),
          if (hasInstagram) const SizedBox(height: 8),
          // Instagram é clicável, então não tem IgnorePointer
          if (hasInstagram) _buildInstagram(),
        ],
      ),
    );
  }

  void _configureAutoSwipe() {
    _stopAutoSwipeTimers();
    final total = _pageCountFor(_imageUrlNotifier.value);
    if (total <= 1) return;

    _autoSwipeTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _isUserInteracting) return;
      final nextPage = (_currentPage + 1) % total;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      if (mounted) setState(() => _currentPage = nextPage);
      _precacheAdjacent(_buildPages(_imageUrlNotifier.value), nextPage);
    });
  }

  void _stopAutoSwipeTimers() {
    _autoSwipeTimer?.cancel();
    _autoSwipeTimer = null;
    _autoSwipeResumeTimer?.cancel();
    _autoSwipeResumeTimer = null;
  }

  void _onUserInteractionStart() {
    _isUserInteracting = true;
    _stopAutoSwipeTimers();
  }

  void _onUserInteractionEnd() {
    if (!_isUserInteracting) return;
    _isUserInteracting = false;
    _autoSwipeResumeTimer?.cancel();
    _autoSwipeResumeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _configureAutoSwipe();
    });
  }

  void _goToNextPage(int total) {
    if (total <= 1 || !_pageController.hasClients) return;
    _onUserInteractionStart();
    final nextPage = (_currentPage + 1) % total;
    _pageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
    _autoSwipeResumeTimer?.cancel();
    _autoSwipeResumeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _configureAutoSwipe();
    });
  }

  void _goToPreviousPage(int total) {
    if (total <= 1 || !_pageController.hasClients) return;
    _onUserInteractionStart();
    final prevPage = (_currentPage - 1 + total) % total;
    _pageController.animateToPage(
      prevPage,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
    _autoSwipeResumeTimer?.cancel();
    _autoSwipeResumeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _configureAutoSwipe();
    });
  }

  Widget _buildNameWithAgeAndFlag() {
    final displayName = _buildDisplayName(widget.user.userFullname);
    return Row(
      children: [
        // Nome com badge
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  displayName,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.user.userIsVerified) ...[
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 3),
                  child: Icon(
                    Icons.verified,
                    size: 18,
                    color: Colors.blue,
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // Idade removida daqui e movida para AboutMeSection
      ],
    );
  }

  String _buildDisplayName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return 'Usuário';

    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Usuário';

    final first = parts.first;
    if (parts.length == 1) {
      return first.length > 15 ? first.substring(0, 15) : first;
    }

    final lastInitial = parts.last.isNotEmpty ? parts.last[0].toUpperCase() : '';
    final safeFirst = first.length > 15 ? first.substring(0, 15) : first;
    return lastInitial.isEmpty ? safeFirst : '$safeFirst $lastInitial.';
  }

  Widget _buildLocationWithState() { // static
    final city = widget.user.userLocality;
    final state = widget.user.userState;
    final parts = <String>[];
    if (city.trim().isNotEmpty) parts.add(city);
    if (state?.trim().isNotEmpty == true) parts.add(state!.trim());

    if (parts.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Icon(
          Iconsax.location,
          size: 18,
          color: Colors.white.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            parts.join(', '),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ),
        // Distância do usuário atual
        if (!widget.isMyProfile) _buildDistanceText(),
      ],
    );
  }

  /// Calcula e exibe a distância entre o usuário logado e o perfil visualizado
  /// Respeita a preferência do usuário (advancedSettings.showDistance)
  Widget _buildDistanceText() {
    final profileLat = widget.user.displayLatitude;
    final profileLng = widget.user.displayLongitude;
    
    // Se não tem coordenadas do perfil, não exibe
    if (profileLat == null || profileLng == null) {
      return const SizedBox.shrink();
    }
    
    // Verifica se o usuário do perfil permite exibir distância
    return ValueListenableBuilder<bool>(
      valueListenable: UserStore.instance.getShowDistanceNotifier(widget.user.userId),
      builder: (context, showDistance, _) {
        // Se o usuário desativou, não exibe a distância
        if (!showDistance) {
          return const SizedBox.shrink();
        }
        
        return FutureBuilder<Position?>(
          future: Geolocator.getLastKnownPosition(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data == null) {
              return const SizedBox.shrink();
            }
            
            final myPosition = snapshot.data!;
            
            // Calcula distância em metros
            final distanceMeters = Geolocator.distanceBetween(
              myPosition.latitude,
              myPosition.longitude,
              profileLat,
              profileLng,
            );
            
            // Converte para km
            final distanceKm = distanceMeters / 1000.0;
            
            return Text(
              '${distanceKm.toStringAsFixed(1)} km',
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOriginFrom() {
    final origin = widget.user.from?.trim() ?? '';
    if (origin.isEmpty) return const SizedBox.shrink();

    final flagCode = _resolveIsoCode(context, origin);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (flagCode != null && flagCode.isNotEmpty) ...[
          CircleFlag(
            flagCode,
            size: 18,
          ),
          const SizedBox(width: 8),
        ],
        Text(
          origin,
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  String? _resolveIsoCode(BuildContext context, String country) {
    final normalized = country.trim();
    if (normalized.isEmpty) return null;

    if (normalized.length == 2) {
      final upper = normalized.toUpperCase();
      final isValid = IsoCode.values.any((code) => code.name.toUpperCase() == upper);
      return isValid ? upper : null;
    }

    // Primeiro tenta pelo locale atual.
    final localization = CountrySelectorLocalization.of(context);
    if (localization != null) {
      final target = normalized.toLowerCase();
      for (final iso in IsoCode.values) {
        if (localization.countryName(iso).toLowerCase() == target) {
          return iso.name;
        }
      }
    }

    // Fallback técnico: inglês (export público) para cobrir casos onde o dado veio em EN.
    final en = CountrySelectorLocalizationEn();
    final target = normalized.toLowerCase();
    for (final iso in IsoCode.values) {
      if (en.countryName(iso).toLowerCase() == target) {
        return iso.name;
      }
    }

    // Último: map rápido (nomes comuns).
    return getCountryInfo(normalized)?.flagCode;
  }

  Widget _buildInstagram() {
    final instagram = widget.user.userInstagram?.trim() ?? '';
    if (instagram.isEmpty) return const SizedBox.shrink();
    
    return Row(
      children: [
        GestureDetector(
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
        ),
        const Spacer(),
        // Followers count (volátil)
        _buildFollowersCount(),
      ],
    );
  }

  /// Exibe o número de seguidores de forma estática (carrega uma vez no initState)
  /// Usa a subcoleção followers da coleção Users
  /// Usa ValueListenableBuilder para rebuild isolado (sem reconstruir todo o ProfileHeader)
  Widget _buildFollowersCount() {
    return ValueListenableBuilder<int?>(
      valueListenable: _followersCountNotifier,
      builder: (context, followersCount, _) {
        // Não mostra nada enquanto carrega ou se não tem seguidores
        if (followersCount == null || followersCount == 0) {
          return const SizedBox.shrink();
        }
        
        // Singular/plural
        final label = followersCount == 1
            ? widget.i18n.translate('follower')
            : widget.i18n.translate('followers');
        
        return Text(
          '${_formatFollowersCount(followersCount)} $label',
          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        );
      },
    );
  }
  
  /// Formata o número de seguidores (ex: 1.2K, 10K, 1M)
  String _formatFollowersCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
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
