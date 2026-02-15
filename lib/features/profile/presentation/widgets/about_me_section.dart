import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// About Me section widget com espaçamento interno
/// 
/// - Padding padrão: GlimpseStyles.profileSectionPadding (20px horizontal, 36px bottom)
/// - Padding customizado: Quando hasActionsBelow=true (16px bottom)
/// - Auto-oculta se bio vazia
class AboutMeSection extends StatelessWidget {

  const AboutMeSection({
    required this.bio,
    super.key,
    this.title,
    this.titleColor,
    this.textColor,
    this.hasActionsBelow = false,
  });
  
  final String? bio;
  final String? title;
  final Color? titleColor;
  final Color? textColor;
  final bool hasActionsBelow;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final effectiveTitleColor = titleColor ?? GlimpseColors.primaryColorLight;
    final effectiveTextColor = textColor ?? GlimpseColors.primaryColorLight;
    final isCompactScreen = MediaQuery.sizeOf(context).width <= 360;
    
    final trimmed = bio?.trim() ?? '';
    
    // ✅ AUTO-OCULTA: não renderiza seção vazia
    if (trimmed.isEmpty) return const SizedBox.shrink();
    
    return Container(
      padding: hasActionsBelow
        ? EdgeInsets.only(left: 20.w, right: 20.w, bottom: 16.h)
        : GlimpseStyles.profileSectionPadding,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            title ?? i18n.translate('about_me_title'),
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              fontWeight: FontWeight.w700,
              fontSize: (isCompactScreen ? 17 : 18).sp,
              color: GlimpseColors.primaryColorLight,
            ),
            textAlign: TextAlign.left,
          ),
          SizedBox(height: 8.h),

          Text(
            trimmed,
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              fontSize: (isCompactScreen ? 13 : 14).sp,
              color: effectiveTextColor,
            ),
            textAlign: TextAlign.left,
          ),
        ],
      ),
    );
  }
}
