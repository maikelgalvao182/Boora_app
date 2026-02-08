import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
  final bool showLogo;

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
    this.showLogo = false,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final textColor = whiteMode ? Colors.white : GlimpseColors.textSubTitle;
    final titleStyle = whiteMode 
        ? TextStyles.headerTitle.copyWith(color: Colors.white) 
        : TextStyles.headerTitle.copyWith(color: GlimpseColors.primaryColorLight);
    final subtitleStyle = whiteMode 
        ? TextStyles.headerSubtitle.copyWith(color: Colors.white.withValues(alpha: 0.9)) 
        : TextStyles.headerSubtitle.copyWith(color: GlimpseColors.textSubTitle);
    
    final continueButtonStyle = GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
      fontSize: 14.sp,
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
            // Lado esquerdo: Logo e Botão Voltar
            Row(
              children: [
                // Logo (condicional)
                if (showLogo) ...[
                  Image.asset(
                    'assets/images/logo.png',
                    width: 65.w,
                    height: 65.h,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(width: 12.w),
                ],
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
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: isProcessing
                    ? SizedBox(
                        height: 20.h,
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
        SizedBox(height: 20.h),
        
        // Título
        if (title.isNotEmpty)
          Text(
            title,
            style: titleStyle,
          ),
        
        // Subtítulo (opcional)
        if (subtitle != null) ...[
          SizedBox(height: 6.h),
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
          child: Icon(
            IconsaxPlusLinear.arrow_left,
            size: 24.w,
            color: GlimpseColors.primaryColorLight,
          ),
        ),
        SizedBox(height: 24.h),
        
                // Título
        Text(
          title,
          style: TextStyles.headerTitle,
        ),
        
        // Subtítulo (opcional)
        if (subtitle != null) ...[
          SizedBox(height: 12.h),
          Text(
            subtitle!,
            style: TextStyles.headerSubtitle,
          ),
        ],
        SizedBox(height: 20.h),
      ],
    );
  }
}