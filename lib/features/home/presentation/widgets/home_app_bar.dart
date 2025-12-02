import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/router/app_router.dart';
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
  bool _isFilterOpening = false;

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

  void _handleFilterTap() {
    if (_isFilterOpening) return;

    setState(() => _isFilterOpening = true);

    HapticFeedback.lightImpact();
    widget.onFilterTap?.call();

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _isFilterOpening = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // TODO: Implementar lógica de usuário logado
    // Por enquanto, sempre exibir como visitante

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      leadingWidth: 0,
      automaticallyImplyLeading: false,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GlimpseStyles.horizontalMargin),
        child: _GuestAppBarContent(),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: GlimpseStyles.horizontalMargin),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botão de notificações
              AutoUpdatingBadge(
                count: 0, // TODO: Pegar contador real
                child: SizedBox(
                  width: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      IconsaxPlusLinear.notification,
                      size: 24,
                      color: GlimpseColors.textColorLight,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      context.push(AppRoutes.notifications);
                    },
                    tooltip: 'Notificações',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Botão de filtros
              SizedBox(
                width: 28,
                child: GestureDetector(
                  onTap: _handleFilterTap,
                  child: Icon(
                    IconsaxPlusLinear.setting_4,
                    size: 24,
                    color: _isFilterOpening
                        ? GlimpseColors.subtitleTextColorLight
                        : GlimpseColors.textColorLight,
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

/// Widget para exibir conteúdo da AppBar para usuários não logados (Visitantes)
class _GuestAppBarContent extends StatelessWidget {
  const _GuestAppBarContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar estático de visitante
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 38,
              height: 38,
              color: GlimpseColors.lightTextField,
              child: const Icon(Icons.person, color: Colors.grey),
            ),
          ),
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
                  color: GlimpseColors.textColorLight,
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
                  color: GlimpseColors.subtitleTextColorLight,
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
