import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Badge genérico para exibir números com sufixo opcional
/// Pode ser usado para contadores, percentuais, rankings, etc.
/// 
/// Uso:
/// ```dart
/// NumberBadge(
///   value: 75,
///   suffix: '%', // Opcional - para percentuais
///   backgroundColor: Colors.red,
/// )
/// 
/// NumberBadge(
///   value: 5,
///   suffix: '', // Sem sufixo - apenas número
///   backgroundColor: Colors.blue,
/// )
/// 
/// NumberBadge(
///   value: 10,
///   suffix: 'x', // Multiplicador
/// )
/// ```
class NumberBadge extends StatelessWidget {
  NumberBadge({
    required this.value,
    this.suffix = '',
    this.backgroundColor = const Color(0xFFE53935),
    this.textColor = Colors.white,
    this.fontSize = 10,
    this.fontWeight = FontWeight.w700,
    EdgeInsets? padding,
    this.borderColor = Colors.white,
    this.borderWidth = 2,
    super.key,
  }) : padding = padding ?? EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h);

  final int value;
  final String suffix;
  final Color backgroundColor;
  final Color textColor;
  final double fontSize;
  final FontWeight fontWeight;
  final EdgeInsets padding;
  final Color borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final template = i18n.translate('number_badge_value_suffix');
    final text = template.isNotEmpty
        ? template.replaceAll('{value}', value.toString()).replaceAll('{suffix}', suffix)
        : '$value$suffix';

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(100.r),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
