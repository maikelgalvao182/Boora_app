import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/home/presentation/widgets/auto_updating_badge.dart';

/// Ícones const pré-compilados para otimização
class _TabIcons {
  const _TabIcons._();

  static const double _size = 26.0;
  static const _selectedColor = Colors.black;
  static const _unselectedColor = Colors.grey;

  // Discover icons
  static const discoverNormal = Icon(Iconsax.location, size: _size, color: _unselectedColor);
  static const discoverBold = Icon(Iconsax.location5, size: _size, color: _selectedColor);

  // actions icons
  static const actionsNormal = Icon(IconsaxPlusLinear.flash, size: _size, color: _unselectedColor);
  static const actionsBold = Icon(IconsaxPlusBold.flash, size: _size, color: _selectedColor);

  // Ranking icons
  static const rankingNormal = Icon(Iconsax.cup, size: _size, color: _unselectedColor);
  static const rankingBold = Icon(Iconsax.cup5, size: _size, color: _selectedColor); // Iconsax might not have bold cup, using same or check for filled

  // Conversation icons
  static const conversationNormal = Icon(Iconsax.message, size: _size, color: _unselectedColor);
  static const conversationBold = Icon(Iconsax.message5, size: _size, color: _selectedColor);

  // Profile icons
  static const profileNormal = Icon(IconsaxPlusLinear.profile, size: _size, color: _unselectedColor);
  static const profileBold = Icon(IconsaxPlusBold.profile, size: _size, color: _selectedColor); // Iconsax user bold might be user_square or similar, or just user
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

  static const double _spacing = 2.0;
  static const _spacer = SizedBox(height: _spacing);

  static final TextStyle _selectedLabelStyle = GoogleFonts.getFont(
    FONT_PLUS_JAKARTA_SANS,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Colors.black,
  );

  static final TextStyle _unselectedLabelStyle = GoogleFonts.getFont(
    FONT_PLUS_JAKARTA_SANS,
    fontSize: 12,
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
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: currentIndex,
      onTap: onTap,
      elevation: 0,
      backgroundColor: Colors.white,
      selectedItemColor: Colors.black,
      unselectedItemColor: GlimpseColors.textSubTitle,
      selectedFontSize: 12,
      selectedLabelStyle: HomeBottomNavigationBar._selectedLabelStyle,
      unselectedLabelStyle: HomeBottomNavigationBar._unselectedLabelStyle,
      iconSize: 26,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      items: [
        // Aba Descobrir
        _buildBottomNavigationBarItem(
          icon: currentIndex == 0 ? _TabIcons.discoverBold : _TabIcons.discoverNormal,
          label: 'Descobrir',
          index: 0,
        ),

        // Aba actions
        _buildBottomNavigationBarItem(
          icon: currentIndex == 1 ? _TabIcons.actionsBold : _TabIcons.actionsNormal,
          label: 'Ações',
          index: 1,
        ),

        // Aba Ranking
        _buildBottomNavigationBarItem(
          icon: currentIndex == 2 ? _TabIcons.rankingBold : _TabIcons.rankingNormal,
          label: 'Ranking',
          index: 2,
        ),

        // Aba Conversas (com badge)
        BottomNavigationBarItem(
          icon: MessagesBadge(
            count: 0, // TODO: Implementar contador real
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                currentIndex == 3 ? _TabIcons.conversationBold : _TabIcons.conversationNormal,
                HomeBottomNavigationBar._spacer,
              ],
            ),
          ),
          label: 'Conversas',
        ),

        // Aba Perfil
        _buildBottomNavigationBarItem(
          icon: currentIndex == 4 ? _TabIcons.profileBold : _TabIcons.profileNormal,
          label: 'Perfil',
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
