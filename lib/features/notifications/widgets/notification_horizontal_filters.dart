import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/features/notifications/widgets/notification_filter.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Horizontal list of notification categories with i18n support
/// 
/// Supported filter types:
/// - All (null): All notifications
/// - Messages: Chat messages
/// - Activities: Activity-related (created, canceled, heating up, etc.)
/// - Requests: Join requests and approvals
/// - Social: Profile views, connections
/// - System: Alerts and system notifications
class NotificationHorizontalFilters extends StatelessWidget {
  NotificationHorizontalFilters({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
    EdgeInsetsGeometry? padding,
    this.spacingAbove = 0,
    this.icons,
    this.selectedBackgroundColor,
    this.unselectedBackgroundColor,
  }) : padding = padding ?? EdgeInsets.symmetric(horizontal: 20.w);
  
  /// List of translated filter labels
  final List<String> items;
  
  /// Currently selected filter index
  final int selectedIndex;
  
  /// Callback when a filter is selected
  final ValueChanged<int> onSelected;
  
  /// Padding around the filter list
  final EdgeInsetsGeometry padding;
  
  /// Spacing above the filter list
  final double spacingAbove;
  
  /// Optional icons for each filter
  final List<IconData>? icons;

  final Color? selectedBackgroundColor;
  final Color? unselectedBackgroundColor;

  @override
  Widget build(BuildContext context) {
    return NotificationFilter(
      items: items,
      selectedIndex: selectedIndex,
      onSelected: (i) {
        onSelected(i);
      },
      padding: (padding as EdgeInsets).copyWith(
        top: 4,
        bottom: 4,
      ),
      selectedBackgroundColor: selectedBackgroundColor ?? GlimpseColors.primary,
      unselectedBackgroundColor: unselectedBackgroundColor ?? GlimpseColors.lightTextField,
    );
  }
}
