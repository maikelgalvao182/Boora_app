import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/common/utils/app_logger.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/profile/presentation/styles/discover_common_styles.dart';

/// DEBUG logger helper (namespaced) to make filtering logs easy to grep
void _phtLog(String msg) => AppLogger.info('[ProfileHorizontalTabs] $msg');

/// Horizontal list of profile tabs with EXACT same UI as WeddingFilter
/// Uses DiscoverCommonStyles for consistent styling across the app
class ProfileHorizontalTabs extends StatelessWidget {

  const ProfileHorizontalTabs({
    required this.selectedIndex, required this.onTabChanged, required this.isBride, super.key,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.spacingAbove = 16,
  });
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;
  final bool isBride;
  final EdgeInsets padding;
  final double spacingAbove;

  List<String> _getTabLabels(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return [
      i18n.translate('personal'),
      i18n.translate('interests'),
      i18n.translate('gallery'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (isBride) {
      // Hide tabs completely for bride profiles
      return const SizedBox.shrink();
    }

    final tabLabels = _getTabLabels(context);
    _phtLog('build() tabs=${tabLabels.length} selectedIndex=$selectedIndex selectedLabel=${selectedIndex >= 0 && selectedIndex < tabLabels.length ? tabLabels[selectedIndex] : 'OUT_OF_RANGE'}');

    return Padding(
      padding: EdgeInsets.only(top: spacingAbove.h),
      child: Row(
        children: [
          for (int i = 0; i < tabLabels.length; i++)
            Flexible(
              flex: 27,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                child: _TabChip(
                  key: ValueKey('tab_$i'),
                  title: tabLabels[i],
                  selected: selectedIndex == i,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _phtLog('onTabChanged index=$i label=${tabLabels[i]}');
                    onTabChanged(i);
                  },
                ),
              ),
            ),
          if (tabLabels.isEmpty)
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// Individual tab chip component - EXACT same style as WeddingFilter chips
class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.title,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = DiscoverCommonStyles.getFilterChipDecoration(selected);
    final textStyle = DiscoverCommonStyles.getFilterChipTextStyle(selected);
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.all(Radius.circular(DiscoverCommonStyles.filterChipBorderRadius)),
          child: Ink(
            decoration: decoration,
            child: Padding(
              padding: DiscoverCommonStyles.filterChipPadding,
              child: Center(
                child: Text(
                  title,
                  style: textStyle.copyWith(
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
