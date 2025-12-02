import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';

/// Unified tab header component used across Applied and Likes tabs.
/// 
/// Provides two variants:
/// - `GlimpseTabHeader.simple()`: Basic header with title and search button
/// - `GlimpseTabHeader.withTabs()`: Header with title, search, and tab switcher
class GlimpseTabHeader extends StatelessWidget {

  const GlimpseTabHeader._({
    required this.title, required this.onSearchTap, required this.hasTabs, super.key,
    this.tabLabels,
    this.selectedTabIndex,
    this.onTabTap,
  });

  /// Creates a simple header with title and search button.
  /// 
  /// Used in Applied tab and other screens that don't need tab switching.
  factory GlimpseTabHeader.simple({
    required String title, required VoidCallback onSearchTap, Key? key,
  }) {
    return GlimpseTabHeader._(
      key: key,
      title: title,
      onSearchTap: onSearchTap,
      hasTabs: false,
    );
  }

  /// Creates a header with title, search button, and tab switcher.
  /// 
  /// Used in Likes tab where users can switch between different views.
  factory GlimpseTabHeader.withTabs({
    required String title, required VoidCallback onSearchTap, required List<String> tabLabels, required int selectedTabIndex, required ValueChanged<int> onTabTap, Key? key,
  }) {
    return GlimpseTabHeader._(
      key: key,
      title: title,
      onSearchTap: onSearchTap,
      hasTabs: true,
      tabLabels: tabLabels,
      selectedTabIndex: selectedTabIndex,
      onTabTap: onTabTap,
    );
  }

  /// Creates a standalone tab switcher (no header, no search button).
  /// 
  /// Used as filter tabs in Applied tab for status filtering (Active/Inactive, Pending/Accepted/Rejected).
  factory GlimpseTabHeader.tabsOnly({
    required List<String> tabLabels, required int selectedTabIndex, required ValueChanged<int> onTabTap, Key? key,
  }) {
    return GlimpseTabHeader._(
      key: key,
      title: '', // Not used for tabs-only mode
      onSearchTap: () {}, // Not used for tabs-only mode
      hasTabs: true,
      tabLabels: tabLabels,
      selectedTabIndex: selectedTabIndex,
      onTabTap: onTabTap,
    );
  }
  final String title;
  final VoidCallback onSearchTap;
  final bool hasTabs;
  
  // Tab-related properties (only used when hasTabs = true)
  final List<String>? tabLabels;
  final int? selectedTabIndex;
  final ValueChanged<int>? onTabTap;

  @override
  Widget build(BuildContext context) {
    // Tabs-only mode (no header)
    if (hasTabs && title.isEmpty) {
      return RepaintBoundary(child: _buildTabSwitcher());
    }

    // Simple header mode (no tabs)
    if (!hasTabs) {
      return RepaintBoundary(child: _buildSimpleHeader());
    }

    // Full mode (header + tabs)
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSimpleHeader(),
          _buildTabSwitcher(),
        ],
      ),
    );
  }

  Widget _buildSimpleHeader() {
    return Padding(
      padding: hasTabs 
          ? const EdgeInsets.fromLTRB(20, 8, 20, 0)
          : const EdgeInsets.fromLTRB(20, 30, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GlimpseStyles.messagesTitleStyle(),
            ),
          ),
          SizedBox(
            width: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                Iconsax.search_normal_1,
                size: 22,
                color: GlimpseColors.textSubTitle,
              ),
              onPressed: onSearchTap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    if (tabLabels == null || tabLabels!.isEmpty || selectedTabIndex == null || onTabTap == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          color: GlimpseColors.lightTextField,
        ),
        height: 56,
        padding: const EdgeInsets.all(4),
        child: Stack(
          children: [
            // Sliding Indicator
            AnimatedAlign(
              alignment: Alignment(
                (selectedTabIndex! / (tabLabels!.length - 1)) * 2 - 1,
                0,
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: FractionallySizedBox(
                widthFactor: 1 / tabLabels!.length,
                heightFactor: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40),
                    color: Colors.black,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Tab Labels
            Row(
              children: List.generate(
                tabLabels!.length,
                (index) => Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onTabTap?.call(index);
                    },
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: selectedTabIndex == index ? Colors.white : Colors.grey[600],
                        ),
                        child: Text(
                          tabLabels![index],
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
