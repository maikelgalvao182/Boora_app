import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/text_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';

import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/typing_indicator.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';

/// Componente de cabeçalho com botões de navegação estilo Glimpse
/// 
/// Layout: [Cancelar] ← Título/Subtítulo → [Continuar]
class GlimpseProgressHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onBackTap;
  final VoidCallback? onCancelTap;
  final VoidCallback? onContinueTap;
  final String? cancelText;
  final String? continueText;
  final bool whiteMode;
  final bool isContinueEnabled;
  final bool isProcessing;
  final bool showBackButton;

  const GlimpseProgressHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.onBackTap,
    this.onCancelTap,
    this.onContinueTap,
    this.cancelText,
    this.continueText,
    this.whiteMode = false,
    this.isContinueEnabled = true,
    this.isProcessing = false,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final textColor = whiteMode ? Colors.white : GlimpseColors.textSubTitle;
    final titleStyle = whiteMode 
        ? TextStyles.headerTitle.copyWith(color: Colors.white) 
        : TextStyles.headerTitle;
    final subtitleStyle = whiteMode 
        ? TextStyles.headerSubtitle.copyWith(color: Colors.white.withValues(alpha: 0.9)) 
        : TextStyles.headerSubtitle;
    
    final continueButtonStyle = GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: isContinueEnabled ? GlimpseColors.primary : GlimpseColors.disabledButtonColorLight,
    );
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Barra de navegação: [Voltar] [Cancelar] <-> [Continuar]
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Lado esquerdo: Botão Voltar
            Row(
              children: [
                // Botão Voltar (condicional)
                if (showBackButton)
                  GlimpseBackButton(
                    onTap: onBackTap,
                    color: textColor,
                  ),
              ],
            ),
            
            // Botão Continuar (direita) - sempre visível
            GestureDetector(
              onTap: (isContinueEnabled && !isProcessing)
                  ? () {
                      HapticFeedback.lightImpact();
                      onContinueTap?.call();
                    }
                  : null,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: isProcessing
                    ? SizedBox(
                        height: 20,
                        child: TypingIndicator(
                          color: textColor,
                          dotSize: 6,
                        ),
                      )
                    : Text(
                        continueText ?? i18n.translate('continue'),
                        style: continueButtonStyle,
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        
        // Título
        if (title.isNotEmpty)
          Text(
            title,
            style: titleStyle,
          ),
        
        // Subtítulo (opcional)
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: subtitleStyle,
          ),
        ],
      ],
    );
  }
}

/// Componente de título e subtítulo sem indicador de progresso
class GlimpseScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onBackTap;

  const GlimpseScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.onBackTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Botão de voltar
        GestureDetector(
          onTap: onBackTap,
          child: const Icon(
            IconsaxPlusLinear.arrow_left,
            size: 24,
            color: GlimpseColors.textSubTitle,
          ),
        ),
        const SizedBox(height: 24),
        
                // Título
        Text(
          title,
          style: TextStyles.headerTitle,
        ),
        
        // Subtítulo (opcional)
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          Text(
            subtitle!,
            style: TextStyles.headerSubtitle,
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}