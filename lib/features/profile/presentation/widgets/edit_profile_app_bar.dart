import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/profile/presentation/widgets/edit_profile_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/typing_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// StatelessWidget AppBar for EditProfile screen
/// Optimized for performance with RepaintBoundary isolation
class EditProfileAppBar extends StatelessWidget implements PreferredSizeWidget {

  const EditProfileAppBar({
    required this.onBack,
    required this.title,
    super.key,
    this.onSave,
    this.isBackEnabled = true,
    this.isSaving = false,
  });
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final String title;
  final bool isBackEnabled;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.only(right: EditProfileStyles.appBarRightPadding),
        child: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        titleSpacing: 0,
        title: Text(
          title,
          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
            fontSize: EditProfileStyles.appBarTitleStyle.fontSize,
            fontWeight: EditProfileStyles.appBarTitleStyle.fontWeight,
            color: GlimpseColors.primaryColorLight,
          ),
        ),
        leading: GlimpseBackButton.iconButton(
          padding: EdgeInsets.zero,
          constraints: EditProfileStyles.iconButtonConstraints,
          onPressed: isBackEnabled ? onBack : () {},
          color: isBackEnabled 
              ? GlimpseColors.primaryColorLight 
              : GlimpseColors.primaryColorLight.withValues(alpha: 0.3),
        ),
        leadingWidth: 56,
        actions: [
          if (onSave != null)
            isSaving
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: TypingIndicator(
                        color: Color(0xFFFF006B),
                        dotSize: 6.w,
                      ),
                    ),
                  )
                : TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onSave,
                    child: Text(
                      i18n.translate('save'),
                      style: EditProfileStyles.saveButtonTextStyle,
                    ),
                  ),
        ],
        elevation: 0,
        backgroundColor: EditProfileStyles.backgroundColor,
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
