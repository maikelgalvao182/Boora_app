import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Botão flutuante horizontal para exibir lista de atividades
class ListButton extends StatelessWidget {
  const ListButton({
    required this.onPressed,
    super.key,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Material(
      color: GlimpseColors.bgColorLight,
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.3),
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Iconsax.sort,
                size: 20,
                color: GlimpseColors.primaryColorLight,
              ),
              const SizedBox(width: 8),
              Text(
                i18n.translate('activities_list'),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
