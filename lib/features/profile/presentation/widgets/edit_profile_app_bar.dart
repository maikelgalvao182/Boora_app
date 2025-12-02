import 'package:partiu/features/profile/presentation/widgets/edit_profile_styles.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/typing_indicator.dart';
import 'package:flutter/material.dart';
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
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(right: 20),
        child: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        titleSpacing: 0,
        title: Text(
          title,
          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
            fontSize: EditProfileStyles.appBarTitleStyle.fontSize,
            fontWeight: EditProfileStyles.appBarTitleStyle.fontWeight,
            color: EditProfileStyles.textSubTitle,
          ),
        ),
        leading: GlimpseBackButton.iconButton(
          padding: EdgeInsets.zero,
          constraints: EditProfileStyles.iconButtonConstraints,
          onPressed: isBackEnabled ? onBack : () {},
          color: isBackEnabled 
              ? EditProfileStyles.textSubTitle 
              : EditProfileStyles.textSubTitle.withValues(alpha: 0.3),
        ),
        leadingWidth: 56,
        actions: [
          if (onSave != null)
            isSaving
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: TypingIndicator(
                        color: Color(0xFFFF006B),
                        dotSize: 6.0,
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
                      'Save',
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
