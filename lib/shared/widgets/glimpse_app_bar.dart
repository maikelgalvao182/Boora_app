import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/typing_indicator.dart';

/// AppBar compartilhada para telas com título e botão de voltar
class GlimpseAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlimpseAppBar({
    required this.title,
    super.key,
    this.onBack,
    this.onAction,
    this.actionText,
    this.actionWidget,
    this.isBackEnabled = true,
    this.isActionLoading = false,
  });

  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onAction;
  final String? actionText;
  final Widget? actionWidget;
  final bool isBackEnabled;
  final bool isActionLoading;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          titleSpacing: 0,
          title: Text(
            title,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: GlimpseColors.primaryColorLight,
            ),
          ),
          leading: SizedBox(
            width: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                IconsaxPlusLinear.arrow_left,
                size: 24,
                color: isBackEnabled
                    ? GlimpseColors.primaryColorLight
                    : GlimpseColors.primaryColorLight.withValues(alpha: 0.3),
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                if (isBackEnabled) {
                  if (onBack != null) {
                    onBack!();
                  } else {
                    Navigator.of(context).pop();
                  }
                }
              },
            ),
          ),
          leadingWidth: 28,
          actions: [
            if (actionWidget != null)
              actionWidget!
            else if (onAction != null)
              isActionLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: TypingIndicator(
                          color: GlimpseColors.primary,
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
                      onPressed: onAction,
                      child: Text(
                        actionText ?? 'Save',
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: GlimpseColors.primary,
                        ),
                      ),
                    ),
          ],
          elevation: 0,
          backgroundColor: Colors.white,
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
