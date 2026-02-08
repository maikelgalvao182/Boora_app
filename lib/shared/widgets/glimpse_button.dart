import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Botão estilo Glimpse para ser reutilizado em todas as telas
class GlimpseButton extends StatelessWidget {

  const GlimpseButton({
    required this.text, super.key,
    this.onTap,
    this.onPressed,
    this.backgroundColor,
    this.textColor,
    this.width,
  this.height,
    this.fontSize,
    this.fontWeight = FontWeight.w700,
    this.outline = false,
    this.isProcessing = false,
    this.noPadding = false,
    this.icon,
    this.iconSize,
    this.hideProcessingText = false,
  });
  final String text;
  final VoidCallback? onTap;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? textColor;
  final double? width;
  final double? height;
  final double? fontSize;
  final FontWeight fontWeight;
  final bool outline;
  final bool isProcessing;
  final bool noPadding;
  final IconData? icon;
  final double? iconSize;
  final bool hideProcessingText;

  @override
  Widget build(BuildContext context) {
  final i18n = AppLocalizations.of(context);
  final hasCallback = (onTap ?? onPressed) != null;
  final isEnabled = hasCallback && !isProcessing;
  final baseBgColor = backgroundColor ?? GlimpseColors.primary;
  
  final effectiveBg = outline
    ? Colors.transparent
    : (isProcessing
      ? baseBgColor.withValues(alpha: 0.8) // 80% transparência ao processar
      : (hasCallback
        ? baseBgColor
        : GlimpseColors.disabledButtonColorLight));
  
  final effectiveTextColor = outline
    ? (hasCallback
      ? (textColor ?? baseBgColor)
      : GlimpseColors.disabledButtonColorLight)
    : (textColor ?? Colors.white);
    
    return Padding(
      padding: noPadding ? EdgeInsets.zero : EdgeInsets.symmetric(vertical: 10.h),
      child: GestureDetector(
        onTap: isEnabled ? () {
          HapticFeedback.lightImpact();
          (onTap ?? onPressed)?.call();
        } : null,
        child: Container(
          width: width ?? double.maxFinite,
          height: height ?? 52.h,
          decoration: BoxDecoration(
            color: effectiveBg,
            borderRadius: BorderRadius.circular(12.r),
            border: outline 
        ? Border.all(
          color: isEnabled
            ? baseBgColor
            : GlimpseColors.disabledButtonColorLight,
          width: 1.5.w,
          )
                : null,
          ),
          child: Center(
            child: isProcessing
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoActivityIndicator(
                        color: effectiveTextColor,
                      ),
                      if (!hideProcessingText) ...[
                        SizedBox(width: 12.w),
                        Text(
                          i18n.translate('processing'),
                          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                            fontWeight: fontWeight,
                            color: effectiveTextColor,
                            fontSize: fontSize ?? 16.sp,
                          ),
                        ),
                      ],
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: iconSize ?? 16.sp,
                          color: effectiveTextColor,
                        ),
                        SizedBox(width: 8.w),
                      ],
                      Flexible(
                        child: Text(
                          text,
                          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                            fontWeight: fontWeight,
                            color: effectiveTextColor,
                            fontSize: fontSize ?? 16.sp,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
