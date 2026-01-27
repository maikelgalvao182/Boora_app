import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget reutilizável para botões de navegação (Voltar + Continuar)
/// Usado em drawers e fluxos de criação
class NavigationButtons extends StatelessWidget {
  const NavigationButtons({
    super.key,
    required this.onBack,
    required this.onContinue,
    this.canContinue = true,
    this.showBackButton = true,
    this.isLoading = false,
  });

  final VoidCallback onBack;
  final VoidCallback onContinue;
  final bool canContinue;
  final bool showBackButton;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Botão voltar (TextButton)
          if (showBackButton)
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                onBack();
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                AppLocalizations.of(context).translate('back'),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.primary,
                ),
              ),
            )
          else
            const SizedBox.shrink(),
          
          // Botão continuar com arrow right
          GestureDetector(
            onTap: canContinue && !isLoading
                ? () {
                    HapticFeedback.lightImpact();
                    onContinue();
                  }
                : null,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: canContinue
                    ? GlimpseColors.primary 
                    : GlimpseColors.disabledButtonColorLight,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Center(
                child: isLoading
                    ? const CupertinoActivityIndicator(
                        radius: 12,
                        color: Colors.white,
                      )
                    : const Icon(
                        IconsaxPlusLinear.arrow_right,
                        size: 24,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
