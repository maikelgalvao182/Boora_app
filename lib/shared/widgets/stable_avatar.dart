import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/cache/avatar_cache_service.dart';
import 'package:partiu/shared/stores/avatar_store.dart';

/// Avatar reativo, quadrado, leve, sem jank e com skeleton automático.
///
/// Integrado com AvatarCacheService para cache em memória.
/// Totalmente baseado em AvatarStore.
/// Mantém borderRadius configurável.
/// Nunca usa formato circular.
class StableAvatar extends StatelessWidget {
  const StableAvatar({
    required this.userId,
    required this.size,
    super.key,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.enableNavigation = true,
    this.onTap,
    this.photoUrl,
  });

  final String userId;
  final double size;
  final BorderRadius borderRadius;
  final bool enableNavigation;
  final VoidCallback? onTap;
  final String? photoUrl;

  static const String _emptyAsset = 'assets/images/empty_avatar.jpg';
  static const AssetImage _emptyImage = AssetImage(_emptyAsset);

  @override
  Widget build(BuildContext context) {
    // UserID vazio → avatar padrão
    if (userId.trim().isEmpty) {
      return _AvatarShell(
        size: size,
        borderRadius: borderRadius,
        enableNavigation: false,
        child: _image(_emptyImage),
      );
    }

    // Verificar cache primeiro para otimização
    final cachedUrl = photoUrl ?? AvatarCacheService.instance.getAvatarUrl(userId);
    
    final store = AvatarStore.instance;
    final notifier = store.getAvatarEntryNotifier(userId);
    
    // Se já temos URL no cache, fornecer ao store após o build
    if (cachedUrl != null && cachedUrl.isNotEmpty) {
      // Usar addPostFrameCallback para evitar setState durante build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        store.preloadAvatar(userId, cachedUrl);
      });
    }

    return _AvatarShell(
      size: size,
      borderRadius: borderRadius,
      enableNavigation: enableNavigation,
      onTap: onTap,
      child: RepaintBoundary(
        child: ValueListenableBuilder(
          valueListenable: notifier,
          builder: (context, entry, _) {
            final AvatarState state = entry.state;
            final ImageProvider provider = entry.provider;

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: state == AvatarState.loading
                  ? Container(
                      key: const ValueKey('skeleton'),
                      width: size,
                      height: size,
                      color: GlimpseColors.lightTextField,
                    )
                  : _image(provider),
            );
          },
        ),
      ),
    );
  }

  Widget _image(ImageProvider provider) {
    return Image(
      key: ValueKey(provider),
      image: provider,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }
}

class _AvatarShell extends StatelessWidget {
  const _AvatarShell({
    required this.size,
    required this.borderRadius,
    required this.enableNavigation,
    required this.child,
    this.onTap,
  });

  final double size;
  final BorderRadius borderRadius;
  final bool enableNavigation;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final clipped = ClipOval(
      child: Container(
        width: size,
        height: size,
        color: GlimpseColors.lightTextField,
        child: child,
      ),
    );

    if (!enableNavigation) return clipped;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: clipped,
      ),
    );
  }
}
