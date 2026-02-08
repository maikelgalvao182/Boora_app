import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/interest_tags_selector.dart';

/// Widget de filtro de interesses
class InterestsFilterWidget extends StatelessWidget {
  const InterestsFilterWidget({
    super.key,
    required this.availableInterests,
    required this.selectedInterests,
    required this.onChanged,
    this.showCount = true,
  });

  final List<String> availableInterests;
  final Set<String> selectedInterests;
  final ValueChanged<Set<String>> onChanged;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.translate('interests'),
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: GlimpseColors.primaryColorLight,
          ),
        ),
        SizedBox(height: 8.h),
        if (showCount) ...[
          Text(
            selectedInterests.isEmpty
                ? i18n.translate('tap_to_filter_by_interest')
                : '${selectedInterests.length} ${i18n.translate('interests_selected')}',
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 14,
              color: GlimpseColors.textSubTitle,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4.h),
        ],
        InterestTagsSelector(
          userInterests: availableInterests,
          selectedInterests: selectedInterests,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
