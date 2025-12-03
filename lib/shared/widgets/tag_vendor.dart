import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Widget de tag para exibição de categorias de vendor
class TagVendor extends StatelessWidget {
  final String label;
  final String? value;
  final bool isSelected;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? borderColor;

  const TagVendor({
    super.key,
    required this.label,
    this.value,
    this.isSelected = false,
    this.onTap,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    // Quando selecionado: borda 1px primaryLight + fundo primaryLight
    // Quando não selecionado: borda borderColorLight + fundo transparente
    final defaultBorderColor = isSelected
        ? GlimpseColors.primaryLight
        : GlimpseColors.borderColorLight;

    final bgColor = isSelected
        ? GlimpseColors.primaryLight
        : Colors.transparent;

    final txtColor = GlimpseColors.primaryColorLight;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor ?? bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor ?? defaultBorderColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor ?? txtColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
