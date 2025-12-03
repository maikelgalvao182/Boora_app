import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/services/location/radius_controller.dart';

/// Widget de filtro de raio/distância
class RadiusFilterWidget extends StatelessWidget {
  const RadiusFilterWidget({
    super.key,
    required this.controller,
  });

  final RadiusController controller;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  i18n.translate('distance'),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: GlimpseColors.primaryColorLight,
                  ),
                ),
                if (controller.isUpdating)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${i18n.translate('up_to')} ${controller.radiusKm.toInt()} km',
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
              child: Slider(
                value: controller.radiusKm,
                min: RadiusController.minRadius,
                max: RadiusController.maxRadius,
                divisions: 99,
                onChanged: (value) {
                  controller.updateRadius(value);
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Os eventos no mapa serão atualizados automaticamente',
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 12,
                color: GlimpseColors.textSubTitle.withOpacity(0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        );
      },
    );
  }
}
