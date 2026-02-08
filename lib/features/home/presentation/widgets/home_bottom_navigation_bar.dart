import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/presentation/widgets/auto_updating_badge.dart';
import 'package:partiu/common/services/notifications_counter_service.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:provider/provider.dart';

/// Ícones const pré-compilados para otimização
class _TabIcons {
  const _TabIcons._();

  static final double _size = 24.0.w;
  static final _selectedColor = Colors.black;
  static final _unselectedColor = Colors.grey;

  // Discover icons
  static final discoverNormal = Icon(Iconsax.location, size: _size, color: _unselectedColor);
  static final discoverBold = Icon(Iconsax.location5, size: _size, color: _selectedColor);

  // actions icons
  static final actionsNormal = Icon(IconsaxPlusLinear.flash_1, size: _size, color: _unselectedColor);
  static final actionsBold = Icon(IconsaxPlusBold.flash_1, size: _size, color: _selectedColor);

  // Ranking icons
  static final rankingNormal = Icon(Iconsax.cup, size: _size, color: _unselectedColor);
  static final rankingBold = Icon(Iconsax.cup5, size: _size, color: _selectedColor); // Iconsax might not have bold cup, using same or check for filled

  // Conversation icons
  static final conversationNormal = Icon(Iconsax.message, size: _size, color: _unselectedColor);
  static final conversationBold = Icon(Iconsax.message5, size: _size, color: _selectedColor);

  // Profile icons
  static final profileNormal = Icon(IconsaxPlusLinear.profile, size: _size, color: _unselectedColor);
  static final profileBold = Icon(IconsaxPlusBold.profile, size: _size, color: _selectedColor); // Iconsax user bold might be user_square or similar, or just user
}

/// Bottom Navigation Bar personalizado para a tela home
class HomeBottomNavigationBar extends StatelessWidget {
  const HomeBottomNavigationBar({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static final double _spacing = 2.0.h;
  static final _spacer = SizedBox(height: _spacing);

  static final TextStyle _selectedLabelStyle = GoogleFonts.getFont(
    FONT_PLUS_JAKARTA_SANS,
    fontSize: 10.sp,
    fontWeight: FontWeight.w600,
    color: Colors.black,
  );

  static final TextStyle _unselectedLabelStyle = GoogleFonts.getFont(
    FONT_PLUS_JAKARTA_SANS,
    fontSize: 10.sp,
    fontWeight: FontWeight.w400,
    color: GlimpseColors.textSubTitle,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    );

    return Theme(
      data: theme,
      child: _BottomNavBarContent(
        currentIndex: currentIndex,
        onTap: (index) {
          HapticFeedback.lightImpact();
          onTap(index);
        },
      ),
    );
  }
}

/// Widget interno do BottomNavigationBar
class _BottomNavBarContent extends StatelessWidget {
  const _BottomNavBarContent({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: currentIndex,
      onTap: onTap,
      elevation: 0,
      backgroundColor: Colors.white,
      selectedItemColor: Colors.black,
      unselectedItemColor: GlimpseColors.textSubTitle,
      selectedFontSize: 10.sp,
      selectedLabelStyle: HomeBottomNavigationBar._selectedLabelStyle,
      unselectedLabelStyle: HomeBottomNavigationBar._unselectedLabelStyle,
      iconSize: 22.w,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      items: [
        // Aba Descobrir
        _buildBottomNavigationBarItem(
          icon: currentIndex == 0 ? _TabIcons.discoverBold : _TabIcons.discoverNormal,
          label: i18n.translate('tab_discover'),
          index: 0,
        ),

        // Aba Feed
        BottomNavigationBarItem(
          icon: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                currentIndex == 1 ? 'assets/svg/fire2.svg' : 'assets/svg/fire.svg',
                width: 22.w,
                height: 22.h,
                colorFilter: ColorFilter.mode(
                  currentIndex == 1 ? Colors.black : Colors.grey,
                  BlendMode.srcIn,
                ),
              ),
              HomeBottomNavigationBar._spacer,
            ],
          ),
          label: i18n.translate('tab_feed'),
        ),

        // Aba Ranking
        _buildBottomNavigationBarItem(
          icon: currentIndex == 2 ? _TabIcons.rankingBold : _TabIcons.rankingNormal,
          label: i18n.translate('tab_ranking'),
          index: 2,
        ),

        // Aba Conversas (com badge)
        BottomNavigationBarItem(
          icon: Consumer<ConversationsViewModel>(
            builder: (context, viewModel, _) {
              return ValueListenableBuilder<int>(
                valueListenable: viewModel.visibleUnreadCount,
                builder: (context, count, _) {
                  final iconWidget = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      currentIndex == 3 ? _TabIcons.conversationBold : _TabIcons.conversationNormal,
                      HomeBottomNavigationBar._spacer,
                    ],
                  );

                  // Se não há contador, retorna só o ícone
                  if (count == 0) return iconWidget;

                  // Se há contador, adiciona badge
                  return AutoUpdatingBadge(
                    count: count,
                    badgeColor: GlimpseColors.actionColor,
                    top: -4.h,
                    right: -4.w,
                    child: iconWidget,
                  );
                },
              );
            },
          ),
          label: i18n.translate('tab_conversations'),
        ),

        // Aba Perfil
        _buildBottomNavigationBarItem(
          icon: currentIndex == 4 ? _TabIcons.profileBold : _TabIcons.profileNormal,
          label: i18n.translate('tab_profile'),
          index: 4,
        ),
      ],
    );
  }

  BottomNavigationBarItem _buildBottomNavigationBarItem({
    required Widget icon,
    required String label,
    required int index,
  }) {
    return BottomNavigationBarItem(
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [icon, HomeBottomNavigationBar._spacer],
      ),
      label: label,
    );
  }
}
