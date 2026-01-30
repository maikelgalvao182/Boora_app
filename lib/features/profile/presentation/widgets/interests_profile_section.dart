import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/constants/glimpse_variables.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/tag_vendor.dart';

/// Interests section widget exibindo tags com TagVendor
/// 
/// - Espaçamento superior: 24px
/// - Espaçamento inferior: 36px  
/// - Padding horizontal: 20px
/// - Auto-oculta se lista vazia
class InterestsProfileSection extends StatelessWidget {

  const InterestsProfileSection({
    required this.interests,
    super.key,
    this.title,
    this.titleColor,
  });
  
  final List<String>? interests;
  final String? title;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final effectiveTitleColor = titleColor ?? GlimpseColors.primaryColorLight;
    
    // ✅ AUTO-OCULTA: não renderiza seção vazia
    if (interests == null || interests!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Container(
      padding: GlimpseStyles.profileSectionPadding,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            title ?? i18n.translate('interests_section_title'),
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: effectiveTitleColor,
            ),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 12),
          
          // Tags with Wrap
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: interests!.map((interestId) {
              final normalizedInterestId = interestId.trim();
              final tag = getInterestById(normalizedInterestId);
              final translated = tag != null ? i18n.translate(tag.nameKey).trim() : '';
              final fallbackText = _humanizeInterestId(normalizedInterestId);
              final label = tag != null
                  ? '${tag.icon} ${translated.isNotEmpty ? translated : fallbackText}'
                  : fallbackText;
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

  String _humanizeInterestId(String interestId) {
    final normalized = interestId.trim();
    if (normalized.isEmpty) return normalized;

    final parts = normalized
        .split(RegExp(r'[_\\s]+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();

    if (parts.isEmpty) return normalized;

    return parts
        .map((part) => part.length == 1
            ? part.toUpperCase()
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
