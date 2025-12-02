import 'package:partiu/screens/notifications/widgets/notification_filter.dart';
import 'package:flutter/material.dart';

/// Horizontal list of notification categories
class NotificationHorizontalFilters extends StatelessWidget {
  const NotificationHorizontalFilters({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.spacingAbove = 0,
  });
  
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsets padding;
  final double spacingAbove;

  @override
  Widget build(BuildContext context) {
    return NotificationFilter(
      items: items,
      selectedIndex: selectedIndex,
      onSelected: (i) {
        onSelected(i);
      },
      padding: padding.copyWith(
        top: 4,
        bottom: 4,
      ),
    );
  }
}
