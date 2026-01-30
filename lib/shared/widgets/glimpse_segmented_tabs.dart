import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

class GlimpseSegmentedTabs extends StatelessWidget {
  const GlimpseSegmentedTabs({
    super.key,
    required this.labels,
    required this.currentIndex,
    required this.onChanged,
    this.backgroundColor,
    this.selectedTabColor,
    this.selectedTextColor,
    this.unselectedTextColor,
    this.margin,
    this.padding,
  });

  final List<String> labels;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final Color? backgroundColor;
  final Color? selectedTabColor;
  final Color? selectedTextColor;
  final Color? unselectedTextColor;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: padding ?? const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: backgroundColor ?? GlimpseColors.lightTextField,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final isActive = currentIndex == index;
          return _SegmentedTabItem(
            label: labels[index],
            isActive: isActive,
            onTap: () => onChanged(index),
            selectedTabColor: selectedTabColor,
            selectedTextColor: selectedTextColor,
            unselectedTextColor: unselectedTextColor,
          );
        }),
      ),
    );
  }
}

class _SegmentedTabItem extends StatelessWidget {
  const _SegmentedTabItem({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.selectedTabColor,
    this.selectedTextColor,
    this.unselectedTextColor,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Color? selectedTabColor;
  final Color? selectedTextColor;
  final Color? unselectedTextColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? (selectedTabColor ?? Colors.white) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isActive
                    ? (selectedTextColor ?? GlimpseColors.primaryColorLight)
                    : (unselectedTextColor ?? GlimpseColors.textSubTitle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
