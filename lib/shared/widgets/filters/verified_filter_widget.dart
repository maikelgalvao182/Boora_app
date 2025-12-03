import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget de filtro de usuários verificados
class VerifiedFilterWidget extends StatelessWidget {
  const VerifiedFilterWidget({
    super.key,
    required this.isVerified,
    required this.onChanged,
  });

  final bool isVerified;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.translate('other_filters'),
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: GlimpseColors.primaryColorLight,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: GlimpseColors.lightTextField,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: GlimpseColors.borderColorLight.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                i18n.translate('only_verified'),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
              CupertinoSwitch(
                value: isVerified,
                activeColor: GlimpseColors.primary,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
