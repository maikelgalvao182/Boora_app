import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;

/// Horizontal, scrollable filter chips used to select a notification category
///
/// Unselected: light background, black text
/// Selected: primary background, white text
class NotificationFilter extends StatelessWidget {
  NotificationFilter({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
    EdgeInsetsGeometry? padding,
    this.selectedBackgroundColor = GlimpseColors.primary,
    this.unselectedBackgroundColor = GlimpseColors.lightTextField,
  }) : padding = padding ?? EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h);
  
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;
  final Color selectedBackgroundColor;
  final Color unselectedBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final effectiveSelectedIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompactScreen = screenWidth <= 360;
    final isLargeScreen = screenWidth > 390;
    final chipFontSize = (isCompactScreen ? 12 : 13).sp;
    final filterHeight = isLargeScreen ? math.min(32.0, 32.h) : 40.h;
    final chipVerticalPadding = isLargeScreen ? math.min(6.0, 6.h) : 8.h;

    return SizedBox(
      height: filterHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: 4.w),
        itemBuilder: (_, i) => _NotificationChipButton(
          title: items[i],
          selected: effectiveSelectedIndex == i,
          onTap: () => onSelected(i),
          selectedBackgroundColor: selectedBackgroundColor,
          unselectedBackgroundColor: unselectedBackgroundColor,
          fontSize: chipFontSize,
          verticalPadding: chipVerticalPadding,
        ),
      ),
    );
  }
}

class _NotificationChipButton extends StatelessWidget {
  const _NotificationChipButton({
    required this.title,
    required this.selected,
    required this.onTap,
    required this.selectedBackgroundColor,
    required this.unselectedBackgroundColor,
    required this.fontSize,
    required this.verticalPadding,
  });
  
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedBackgroundColor;
  final Color unselectedBackgroundColor;
  final double fontSize;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? selectedBackgroundColor : unselectedBackgroundColor;
    final fg = selected ? Colors.white : Colors.black;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 5.w),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(50.r),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(18.w, verticalPadding, 18.w, verticalPadding),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

