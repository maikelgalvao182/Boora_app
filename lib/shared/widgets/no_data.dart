import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/svg_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

class NoData extends StatelessWidget {

  const NoData({
    required this.text, super.key, 
    this.svgName, 
    this.icon, 
    this.tabType,
    this.fontSize = 18,
    this.svgSize,
  });

  final String? svgName;
  final Widget? icon;
  final String text;
  final String? tabType;
  final double fontSize;
  final double? svgSize;

  @override
  Widget build(BuildContext context) {
    Widget? localIcon;
    
    if (tabType != null) {
      String iconPath;
      
      switch (tabType) {
        case 'discover':
          iconPath = 'assets/svg/tab-discover.svg';
        case 'matches':
          iconPath = 'assets/svg/tab-matches.svg';
        case 'conversations':
          iconPath = 'assets/svg/tab-conversation.svg';
        case 'profile':
          iconPath = 'assets/svg/tab-profile.svg';
        default:
          iconPath = 'assets/svg/tab-discover.svg';
      }
      
      localIcon = SvgIcon(
        iconPath,
        width: 60, 
        height: 60, 
        color: Colors.grey,
      );
    }
    else if (svgName != null) {
      final isIcon = svgName!.endsWith('_icon');
      final path = isIcon
          ? 'assets/icons/$svgName.svg'
          : 'assets/svg/$svgName.svg';
      final size = svgSize ?? (isIcon ? 100 : 120);
      
      localIcon = AnimatedOpacity(
        opacity: 1,
        duration: const Duration(milliseconds: 200),
        child: SvgIcon(
          path,
          width: size,
          height: size,
          color: isIcon ? GlimpseColors.primaryColorLight : null,
        ),
      );
    } else {
      localIcon = icon;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (localIcon != null) localIcon,
          const SizedBox(height: 20),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Text(
              text,
              style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
