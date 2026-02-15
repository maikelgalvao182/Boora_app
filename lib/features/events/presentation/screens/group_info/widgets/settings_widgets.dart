import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget de configuração genérica (usado para silenciar notificações)
class SettingTileWidget extends StatelessWidget {
  const SettingTileWidget({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.trailing,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4.h),
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24.sp,
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: GlimpseColors.primaryColorLight,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// Widget específico do switch de privacidade
class PrivacySwitchWidget extends StatelessWidget {
  const PrivacySwitchWidget({
    required this.isPrivate,
    required this.isCreator,
    required this.onToggle,
    super.key,
  });

  final bool isPrivate;
  final bool isCreator;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4.h),
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
      decoration: BoxDecoration(
        color: GlimpseColors.bgColorLight,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          Container(
            width: 48.w,
            height: 48.w,
            decoration: const BoxDecoration(
              color: GlimpseColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPrivate ? IconsaxPlusBold.lock : IconsaxPlusBold.global,
              size: 20.sp,
              color: GlimpseColors.primary,
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Text(
              isPrivate 
                  ? i18n.translate('private_event') 
                  : i18n.translate('open_event'),
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: GlimpseColors.primaryColorLight,
              ),
            ),
          ),
          CupertinoSwitch(
            value: isPrivate,
            onChanged: isCreator ? onToggle : null,
            activeColor: GlimpseColors.primary,
          ),
        ],
      ),
    );
  }
}
