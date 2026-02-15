import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Estilos centralizados compartilhados entre as telas de descoberta
class DiscoverCommonStyles {
  DiscoverCommonStyles._();

  // CORES
  static const Color backgroundColor = Colors.white;
  static const Color textSubTitle = GlimpseColors.textSubTitle;
  static const Color lightTextField = GlimpseColors.lightTextField;
  static const Color primaryColorLight = GlimpseColors.primaryColorLight;
  static const Color textColor = GlimpseColors.textSubTitle;
  static const Color subtitleTextColor = GlimpseColors.textSubTitle;
  static const Color filterButtonColor = GlimpseColors.primaryColorLight;
  
  // Cores específicas para tabs do profile
  static const Color primary = Color(0xFF5BAD46);
  static const Color primaryLight = Color(0xFFEBF6E6);

  // ESTILOS DE TEXTO
  static final TextStyle pageTitleStyle = GoogleFonts.getFont(
    FONT_PLUS_JAKARTA_SANS,
    fontSize: 28.sp,
    fontWeight: FontWeight.w900,
    color: textColor,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static final TextStyle filterChipTextStyle = GoogleFonts.getFont(
    FONT_PLUS_JAKARTA_SANS,
    fontSize: 13.sp,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );

  static final TextStyle filterChipSelectedTextStyle = GoogleFonts.getFont(
    FONT_PLUS_JAKARTA_SANS,
    fontSize: 13.sp,
    fontWeight: FontWeight.w700,
    color: primary,
  );

  // DIMENSÕES
  static double get filterChipHeight => 40.h;
  static double get filterChipBorderRadius => 12.r;
  static EdgeInsets get filterChipPadding => EdgeInsets.fromLTRB(18.w, 10.h, 18.w, 10.h);
  static EdgeInsets get filterChipMargin => EdgeInsets.symmetric(horizontal: 5.w);

  // DECORAÇÕES
  static BoxDecoration filterChipDecoration() {
    return BoxDecoration(
      color: lightTextField,
      borderRadius: BorderRadius.circular(filterChipBorderRadius),
    );
  }

  static BoxDecoration filterChipSelectedDecoration() {
    return BoxDecoration(
      color: primaryLight,
      borderRadius: BorderRadius.circular(filterChipBorderRadius),
    );
  }

  // MÉTODOS AUXILIARES
  static BoxDecoration getFilterChipDecoration(bool isSelected) {
    return isSelected ? filterChipSelectedDecoration() : filterChipDecoration();
  }

  static TextStyle getFilterChipTextStyle(bool isSelected) {
    return isSelected ? filterChipSelectedTextStyle : filterChipTextStyle;
  }
}
