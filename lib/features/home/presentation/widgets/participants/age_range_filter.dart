import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget de filtro de idade com RangeSlider
class AgeRangeFilter extends StatelessWidget {
  const AgeRangeFilter({
    required this.minAge,
    required this.maxAge,
    required this.onRangeChanged,
    super.key,
  });

  final double minAge;
  final double maxAge;
  final ValueChanged<RangeValues> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GlimpseColors.primaryLight,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ícone + Título + Range atual
          Row(
            children: [
              // Ícone em container redondo
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: GlimpseColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    IconsaxPlusLinear.cake,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Título
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.translate('age_range'),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: GlimpseColors.primaryColorLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${minAge.round()} - ${maxAge.round()} ${i18n.translate('years')}',
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: GlimpseColors.textSubTitle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Range Slider simplificado
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: GlimpseColors.primary,
              inactiveTrackColor: GlimpseColors.borderColorLight,
              thumbColor: GlimpseColors.primary,
              overlayColor: GlimpseColors.primary.withOpacity(0.1),
              rangeThumbShape: const RoundRangeSliderThumbShape(
                enabledThumbRadius: 8,
                elevation: 0,
              ),
              rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
              trackHeight: 4,
            ),
            child: RangeSlider(
              values: RangeValues(minAge, maxAge),
              min: 18,
              max: 80,
              divisions: 62,
              onChanged: onRangeChanged,
            ),
          ),
        ],
      ),
    );
  }
}
