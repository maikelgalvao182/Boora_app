import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/common/services/notifications_counter_service.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/reactive/reactive_profile_completeness_ring.dart';
import 'package:partiu/features/home/presentation/widgets/auto_updating_badge.dart';
import 'package:partiu/features/home/presentation/widgets/home_app_bar_controller.dart';

/// AppBar personalizado para a tela home
/// Exibido apenas na aba de descoberta (index 0)
class HomeAppBar extends StatefulWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key, this.onNotificationsTap, this.onFilterTap});

  final VoidCallback? onNotificationsTap;
  final VoidCallback? onFilterTap;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<HomeAppBar> createState() => _HomeAppBarState();
}

class _HomeAppBarState extends State<HomeAppBar> {
  late final HomeAppBarController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HomeAppBarController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      leadingWidth: 0,
      automaticallyImplyLeading: false,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GlimpseStyles.horizontalMargin),
        child: ValueListenableBuilder(
          valueListenable: AppState.currentUser,
          builder: (context, user, _) {
            if (user == null) {
              return const _GuestAppBarContent();
            }
            return _UserAppBarContent(user: user);
          },
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: GlimpseStyles.horizontalMargin),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botão de notificações (com badge usando AppState diretamente)
              AutoUpdatingBadge(
                fontSize: 9,
                minBadgeSize: 14.0,
                badgePadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                badgeColor: GlimpseColors.actionColor,
                child: SizedBox(
                  width: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      IconsaxPlusLinear.notification,
                      size: 24,
                      color: GlimpseColors.textSubTitle,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      context.push(AppRoutes.notifications);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Widget para exibir conteúdo da AppBar para usuários logados
class _UserAppBarContent extends StatelessWidget {
  const _UserAppBarContent({required this.user});

  final user;

  @override
  Widget build(BuildContext context) {
    final fullName = user.fullName ?? 'Usuário';
    final locality = user.locality ?? '';
    final state = user.state ?? '';
    
    final location = locality.isNotEmpty && state.isNotEmpty
        ? '$locality, $state'
        : locality.isNotEmpty
            ? locality
            : state.isNotEmpty
                ? state
                : 'Localização não definida';

    return Row(
      children: [
        // Avatar do usuário com anel de completude
        ReactiveProfileCompletenessRing(
          size: 44,
          strokeWidth: 2,
          child: StableAvatar(
            userId: user.userId,
            size: 38,
            photoUrl: user.photoUrl,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 12),
        // Nome e localização do usuário
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Oi, $fullName 👋',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: GlimpseColors.primaryColorLight,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                location,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: GlimpseColors.textSubTitle,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Widget para exibir conteúdo da AppBar para usuários não logados (Visitantes)
class _GuestAppBarContent extends StatelessWidget {
  const _GuestAppBarContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar estático de visitante
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: GlimpseColors.lightTextField,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.person, color: Colors.grey, size: 24),
        ),
        const SizedBox(width: 12),
        // Nome e localização estáticos
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Oi, Visitante 👋',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: GlimpseColors.textSubTitle,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Localização não definida',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: GlimpseColors.textSubTitle,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
