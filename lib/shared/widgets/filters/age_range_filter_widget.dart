import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget de filtro de faixa etária
class AgeRangeFilterWidget extends StatelessWidget {
  const AgeRangeFilterWidget({
    super.key,
    required this.ageRange,
    required this.onChanged,
  });

  final RangeValues ageRange;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.translate('age'),
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: GlimpseColors.primaryColorLight,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${i18n.translate('from')} ${ageRange.start.toInt()} ${i18n.translate('to')} ${ageRange.end.toInt()} ${i18n.translate('years')}',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 14,
            color: GlimpseColors.textSubTitle,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: GlimpseColors.primary,
            inactiveTrackColor: GlimpseColors.textSubTitle.withOpacity(0.2),
            thumbColor: GlimpseColors.primary,
            overlayColor: GlimpseColors.primary.withOpacity(0.2),
            valueIndicatorColor: GlimpseColors.primary,
          ),
          child: RangeSlider(
            values: ageRange,
            min: 18,
            max: 60,
            divisions: 42,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
