import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/reactive/reactive_profile_completeness_ring.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_location.dart';
import 'package:partiu/features/home/presentation/widgets/auto_updating_badge.dart';
import 'package:partiu/features/home/presentation/widgets/home_app_bar_controller.dart';
import 'package:partiu/shared/widgets/safety_tips_button.dart';

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
              // Botão de dicas de segurança
              const SafetyTipsButton(),
              const SizedBox(width: 12),
              // Botão do feed de fotos (controlado por feature flag)
              if (ENABLE_EVENT_PHOTO_FEED_ICON) ...[
                SizedBox(
                  width: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      IconsaxPlusLinear.gallery,
                      size: 24,
                      color: GlimpseColors.textSubTitle,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      context.push(AppRoutes.eventPhotoFeed);
                    },
                  ),
                ),
                const SizedBox(width: 12),
              ],
              // Botão de notificações (com badge reativo usando AppState)
              Builder(
                builder: (context) {
                  debugPrint('🏠 [HomeAppBar] Builder reconstruído');
                  debugPrint('🏠 [HomeAppBar] AppState.unreadNotifications.value: ${AppState.unreadNotifications.value}');
                  return AutoUpdatingBadge(
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
              );
                },
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

  final dynamic user;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Row(
      children: [
        // Avatar do usuário com anel de completude
        ReactiveProfileCompletenessRing(
          size: 44,
          strokeWidth: 2.5,
          showBadge: false,
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
              ReactiveUserNameWithBadge(
                userId: user.userId,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
              const SizedBox(height: 2),
              // ✅ Localização reativa - atualiza instantaneamente quando muda no Firestore
              ReactiveUserLocation(
                userId: user.userId,
                fallbackText: i18n.translate('location_not_defined'),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: GlimpseColors.textSubTitle,
                ),
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
    final i18n = AppLocalizations.of(context);
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
                i18n.translate('home_greeting_guest'),
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
                i18n.translate('location_not_defined'),
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
