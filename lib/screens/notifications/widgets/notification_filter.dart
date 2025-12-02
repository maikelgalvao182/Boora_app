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
  });
  
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++)
            _NotificationChipButton(
              title: items[i],
              selected: selectedIndex == i,
              onTap: () => onSelected(i),
            ),
          if (items.isEmpty) const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _NotificationChipButton extends StatelessWidget {
  const _NotificationChipButton({
    required this.title,
    required this.selected,
    required this.onTap,
  });
  
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected 
        ? GlimpseColors.primaryColorLight 
        : GlimpseColors.lightTextField;
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
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: Text(
              title,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
