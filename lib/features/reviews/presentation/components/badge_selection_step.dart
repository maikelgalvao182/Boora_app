import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/reviews/domain/constants/review_badges.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Step de seleção de badges (Step 2)
class BadgeSelectionStep extends StatelessWidget {
  final List<String> selectedBadges;
  final Function(String) onBadgeToggle;

  const BadgeSelectionStep({
    required this.selectedBadges,
    required this.onBadgeToggle,
    super.key,
  });

  String _badgesSelectedLabel(AppLocalizations i18n, int count) {
    final template = count == 1
        ? i18n.translate('badges_selected_count_singular')
        : i18n.translate('badges_selected_count_plural');
    return template.replaceAll('{count}', count.toString());
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Column(
      children: [
        // Grid de badges
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: availableBadges.length,
          itemBuilder: (context, index) {
            final badge = availableBadges[index];
            final isSelected = selectedBadges.contains(badge.key);

            return _BadgeItem(
              badge: badge,
              isSelected: isSelected,
              onTap: () => onBadgeToggle(badge.key),
            );
          },
        ),
        
        SizedBox(height: 16.h),
        
        // Contador de badges selecionados
        if (selectedBadges.isNotEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: GlimpseColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Text(
                _badgesSelectedLabel(i18n, selectedBadges.length),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BadgeItem extends StatelessWidget {
  final ReviewBadge badge;
  final bool isSelected;
  final VoidCallback onTap;

  const _BadgeItem({
    required this.badge,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? GlimpseColors.primaryLight : Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isSelected 
                ? GlimpseColors.primary
                : GlimpseColors.borderColorLight,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Emoji
            Text(
              badge.emoji,
              style: const TextStyle(fontSize: 28),
            ),
            SizedBox(height: 6.h),
            
            // Título
            Text(
              badge.localizedTitle(i18n),
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? GlimpseColors.primary
                    : GlimpseColors.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
