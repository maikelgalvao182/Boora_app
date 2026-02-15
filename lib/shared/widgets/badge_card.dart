import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/reviews/domain/constants/review_badges.dart';

/// Card vertical para exibir badge no perfil
class BadgeCard extends StatelessWidget {
  const BadgeCard({
    required this.badgeKey,
    required this.count,
    super.key,
  });

  final String badgeKey;
  final int count;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final badge = ReviewBadge.fromKey(badgeKey);
    if (badge == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: badge.color.withValues(alpha: 0.3),
          width: 1.w,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Emoji com contador sobreposto
          Stack(
            clipBehavior: Clip.none,
            children: [
              Text(
                badge.emoji,
                style: TextStyle(fontSize: 30.sp),
              ),
              Positioned(
                bottom: -3.h,
                right: -3.w,
                child: Container(
                  padding: EdgeInsets.all(5.r),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: GlimpseColors.primaryColorLight,
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: 8.h),
          
          // Título
          SizedBox(
            height: 34.h,
            child: Align(
              alignment: Alignment.center,
              child: Text(
                badge.localizedTitle(i18n),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.primaryColorLight,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
