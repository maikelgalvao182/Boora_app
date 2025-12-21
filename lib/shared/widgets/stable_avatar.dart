import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/cache/avatar_cache_service.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/core/models/user.dart';

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
    debugPrint('═══════════════════════════════════════════');
    debugPrint('🎯 [StableAvatar] BUILD');
    debugPrint('   └─ userId: $userId');
    debugPrint('   └─ photoUrl param: $photoUrl');
    
    // UserID vazio → avatar padrão
    if (userId.trim().isEmpty) {
      debugPrint('⚠️ [StableAvatar] userId VAZIO - usando empty avatar');
      return _AvatarShell(
        size: size,
        borderRadius: borderRadius,
        enableNavigation: false,
        child: _image(_emptyImage),
      );
    }

    // Usar UserStore para reatividade global
    final notifier = UserStore.instance.getAvatarEntryNotifier(userId);
    
    // Se photoUrl foi passado explicitamente, preload no UserStore
    final hasValidPhotoUrl = photoUrl != null && photoUrl!.isNotEmpty;
    debugPrint('🔍 [StableAvatar] hasValidPhotoUrl: $hasValidPhotoUrl');
    
    if (hasValidPhotoUrl) {
      debugPrint('✅ [StableAvatar] Agendando preloadAvatar com URL: $photoUrl');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('⏰ [StableAvatar] PostFrameCallback - chamando preloadAvatar');
        UserStore.instance.preloadAvatar(userId, photoUrl!);
      });
    } else {
      debugPrint('⚠️ [StableAvatar] photoUrl VAZIO ou NULL - UserStore vai buscar');
    }

    return _AvatarShell(
      size: size,
      borderRadius: borderRadius,
      enableNavigation: enableNavigation,
      userId: userId,
      onTap: onTap,
      child: RepaintBoundary(
        child: ValueListenableBuilder(
          valueListenable: notifier,
          builder: (context, entry, _) {
            final state = entry.state;
            final provider = entry.provider;
            
            debugPrint('🔄 [StableAvatar] ValueListenableBuilder REBUILD');
            debugPrint('   └─ userId: $userId');
            debugPrint('   └─ state: $state');
            debugPrint('   └─ provider: ${provider.runtimeType}');
            if (provider is NetworkImage) {
              debugPrint('   └─ NetworkImage URL: ${(provider as NetworkImage).url}');
            }
            
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
    this.userId,
    this.onTap,
  });

  final double size;
  final BorderRadius borderRadius;
  final bool enableNavigation;
  final String? userId;
  final VoidCallback? onTap;
  final Widget child;

  void _handleTap(BuildContext context) async {
    // Se há callback customizado, usa ele
    if (onTap != null) {
      onTap!();
      return;
    }

    // Navegação padrão para perfil
    if (userId == null || userId!.isEmpty) return;

    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) return;

    try {
      User userToShow;

      // Se for o próprio usuário, usa AppState
      if (userId == currentUserId) {
        final currentUser = AppState.currentUser.value;
        if (currentUser == null) return;
        userToShow = currentUser;
      } else {
        // Buscar dados do outro usuário
        final userRepository = UserRepository();
        final userData = await userRepository.getUserById(userId!);
        if (userData == null) return;
        
        userToShow = User.fromDocument(userData);
      }

      // Navega para o perfil usando GoRouter
      if (context.mounted) {
        context.push(
          '${AppRoutes.profile}/$userId',
          extra: {
            'user': userToShow,
            'currentUserId': currentUserId,
          },
        );
      }
    } catch (e) {
      debugPrint('❌ Error navigating to profile from avatar: $e');
    }
  }

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
        onTap: () => _handleTap(context),
        child: clipped,
      ),
    );
  }
}
