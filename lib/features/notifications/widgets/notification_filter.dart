import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Horizontal, scrollable filter chips used to select a notification category
///
/// Unselected: light background, black text
/// Selected: primary background, white text
class NotificationFilter extends StatelessWidget {
  const NotificationFilter({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.selectedBackgroundColor = GlimpseColors.primary,
    this.unselectedBackgroundColor = GlimpseColors.lightTextField,
  });
  
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;
  final Color selectedBackgroundColor;
  final Color unselectedBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final effectiveSelectedIndex = selectedIndex < 0 ? 0 : selectedIndex;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) => _NotificationChipButton(
          title: items[i],
          selected: effectiveSelectedIndex == i,
          onTap: () => onSelected(i),
          selectedBackgroundColor: selectedBackgroundColor,
          unselectedBackgroundColor: unselectedBackgroundColor,
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
  });
  
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedBackgroundColor;
  final Color unselectedBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? selectedBackgroundColor : unselectedBackgroundColor;
    final fg = selected ? Colors.white : Colors.black;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
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

