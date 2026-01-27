import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

class EventPhotoFeedTabs extends StatelessWidget {
  const EventPhotoFeedTabs({
    super.key,
    required this.currentIndex,
    required this.onChanged,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: GlimpseColors.lightTextField,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          _TabItem(
            label: i18n.translate('event_photo_tab_global'),
            isActive: currentIndex == 0,
            onTap: () => onChanged(0),
          ),
          _TabItem(
            label: i18n.translate('event_photo_tab_following'),
            isActive: currentIndex == 1,
            onTap: () => onChanged(1),
          ),
          _TabItem(
            label: i18n.translate('event_photo_tab_my_posts'),
            isActive: currentIndex == 2,
            onTap: () => onChanged(2),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isActive ? GlimpseColors.primaryColorLight : GlimpseColors.textSubTitle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
