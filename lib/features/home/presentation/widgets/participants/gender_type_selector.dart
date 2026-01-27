import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Enum para definir o tipo de seleção de gênero
enum GenderType {
  all,
  specific,
}

/// Widget seletor de tipo de gênero (Todos vs Específico)
class GenderTypeSelector extends StatelessWidget {
  const GenderTypeSelector({
    required this.selectedType,
    required this.onTypeSelected,
    super.key,
  });

  final GenderType selectedType;
  final ValueChanged<GenderType> onTypeSelected;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.translate('gender_preference_title'),
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: GlimpseColors.textSubTitle,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildOptionCard(
                context: context,
                type: GenderType.all,
                title: i18n.translate('gender_all'),
                isSelected: selectedType == GenderType.all,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildOptionCard(
                context: context,
                type: GenderType.specific,
                title: i18n.translate('gender_specific'),
                isSelected: selectedType == GenderType.specific,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required GenderType type,
    required String title,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => onTypeSelected(type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected 
              ? GlimpseColors.primaryColorLight.withValues(alpha: 0.1) 
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? GlimpseColors.primaryColorLight 
                : GlimpseColors.borderColorLight,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected 
                  ? GlimpseColors.primaryColorLight 
                  : GlimpseColors.textSubTitle,
            ),
          ),
        ),
      ),
    );
  }
}
