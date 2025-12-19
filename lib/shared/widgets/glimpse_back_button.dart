import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Componente reutilizável de botão voltar estilo Glimpse
/// Mantém a aparência e comportamento exatos do botão original
class GlimpseBackButton extends StatelessWidget {

  const GlimpseBackButton({
    required this.onTap, super.key,
    this.width = 24,
    this.height = 24,
    this.color,
  });
  final VoidCallback onTap;
  final double? width;
  final double? height;
  final Color? color;

  /// Factory para criar um IconButton compatível com AppBar
  static Widget iconButton({
    required VoidCallback onPressed,
    double? width = 24,
    double? height = 24,
    Color? color,
    EdgeInsetsGeometry? padding,
    BoxConstraints? constraints,
  }) {
    return SizedBox(
      width: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(
          IconsaxPlusLinear.arrow_left,
          size: 24,
          color: color ?? GlimpseColors.primaryColorLight,
        ),
        onPressed: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Icon(
        IconsaxPlusLinear.arrow_left,
        size: width ?? 24,
        color: color ?? GlimpseColors.primaryColorLight,
      ),
    );
  }
}
