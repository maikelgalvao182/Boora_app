import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Botão flutuante horizontal para exibir lista de atividades
class ListButton extends StatelessWidget {
  const ListButton({
    required this.onPressed,
    super.key,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Material(
      color: GlimpseColors.bgColorLight,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(30.r),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(30.r),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Iconsax.sort,
                size: 20.sp,
                color: GlimpseColors.primaryColorLight,
              ),
              SizedBox(width: 8.w),
              Text(
                i18n.translate('activities_list'),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
