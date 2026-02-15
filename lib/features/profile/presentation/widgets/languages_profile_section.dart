import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/constants/glimpse_variables.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/tag_vendor.dart';

/// Languages section widget exibindo tags com TagVendor
/// 
/// - Espaçamento superior: 24px
/// - Espaçamento inferior: 36px  
/// - Padding horizontal: 20px
/// - Auto-oculta se string vazia
class LanguagesProfileSection extends StatelessWidget {

  const LanguagesProfileSection({
    required this.languages,
    super.key,
    this.title,
    this.titleColor,
  });
  
  final String? languages;
  final String? title;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final effectiveTitleColor = titleColor ?? GlimpseColors.primaryColorLight;
    final isCompactScreen = MediaQuery.sizeOf(context).width <= 360;
    
    // ✅ AUTO-OCULTA: não renderiza seção vazia
    if (languages == null || languages!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Parse comma-separated string
    final languagesList = languages!
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    
    if (languagesList.isEmpty) return const SizedBox.shrink();
    
    return Container(
      padding: GlimpseStyles.profileSectionPadding,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            title ?? i18n.translate('languages_section_title'),
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              fontWeight: FontWeight.w700,
              fontSize: (isCompactScreen ? 17 : 18).sp,
              color: effectiveTitleColor,
            ),
            textAlign: TextAlign.left,
          ),
          SizedBox(height: 12.h),
          
          // Tags with Wrap
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: languagesList.map((language) {
              final languageInfo = getLanguageInfo(language);
              final label = languageInfo != null 
                  ? '${languageInfo.flag} ${i18n.translate(languageInfo.translationKey)}'
                  : language; // Fallback: exibe o nome original
              return TagVendor(
                label: label,
                isSelected: false,
                onTap: null,
                backgroundColor: GlimpseColors.lightTextField,
                textColor: Colors.black,
                borderColor: Colors.transparent,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
