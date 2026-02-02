import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Constantes de estilos de texto e espaçamentos baseados no projeto Glimpse
/// Este arquivo contém os estilos de texto, espaçamentos e decorações utilizados no aplicativo
class GlimpseStyles {
  // Estilos de texto para títulos
  static TextStyle titleStyle({Color? color}) => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: color ?? Colors.black,
      );
      
  // Estilo para o título de páginas
  static TextStyle messagesTitleStyle({Color? color}) => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: 20, // Alterado de 24 para 20
        fontWeight: FontWeight.w700,
        color: color ?? GlimpseColors.textSubTitle,
      );

  // Estilos de texto para subtítulos
  static TextStyle subtitleStyle({Color? color}) => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: color ?? GlimpseColors.textSubTitle,
      );

  // Estilos de texto para campos de texto
  static TextStyle inputTextStyle({Color? color}) => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: color ?? Colors.black,
      );

  // Estilos de texto para dicas em campos de texto
  static TextStyle hintTextStyle({Color? color}) => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: color ?? GlimpseColors.textSubTitle,
      );

  // Estilos de texto para botões
  static TextStyle buttonTextStyle({Color? color}) => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: color ?? Colors.white,
      );

  // Estilos de texto para textos pequenos
  static TextStyle smallTextStyle({Color? color}) => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color ?? GlimpseColors.textSubTitle,
      );

  // Estilo para labels de campos de formulário (baseado no personal_tab.dart)
  static TextStyle fieldLabelStyle({Color? color}) => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontWeight: FontWeight.w800,
        fontSize: 14,
        color: color,
      );

  // Estilo alternativo para labels menores (usado em campos específicos como Month, Day, Year)
  static TextStyle smallFieldLabelStyle({Color? color}) => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        color: GlimpseColors.textSubTitle,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      );

  // Decoração para campos de texto
  static InputDecoration textFieldDecoration({
    required String hintText,
    Color? borderColor,
    Color? focusedBorderColor,
    Widget? prefixIcon,
    Widget? suffixIcon,
    double? borderRadius,
  }) {
    final radius = borderRadius ?? 40;
    final focusedRadius = borderRadius ?? 30;
    
    return InputDecoration(
      contentPadding: const EdgeInsetsDirectional.symmetric(
        horizontal: 25,
        vertical: 20,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(
          color: borderColor ?? GlimpseColors.borderColorLight,
        ),
      ),
      hintText: hintText,
      hintStyle: hintTextStyle(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: focusedBorderColor ?? GlimpseColors.primaryColorLight,
        ),
        borderRadius: BorderRadius.circular(focusedRadius),
      ),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon != null
          ? Padding(
              padding: const EdgeInsets.only(right: 20),
              child: suffixIcon,
            )
          : null,
    );
  }

  // Decoração para botões
  static BoxDecoration buttonDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? GlimpseColors.primaryColorLight,
      borderRadius: BorderRadius.circular(40),
    );
  }

  // Espaçamentos padrão
  static const double smallSpacing = 8;
  static const double mediumSpacing = 12;
  static const double defaultSpacing = 16;
  static const double largeSpacing = 20;
  static const double extraLargeSpacing = 36;
  static const double hugeSpacing = 32;

  // Padding padrão
  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(20, 30, 20, 0);
  static const EdgeInsets buttonPadding = EdgeInsets.fromLTRB(20, 10, 20, 0);
  static const EdgeInsets textFieldPadding = EdgeInsets.fromLTRB(2, 10, 2, 10);
  
  // Margins horizontais padronizadas
  static const double horizontalMargin = 20;
  static const EdgeInsets screenHorizontalPadding = EdgeInsets.symmetric(horizontal: horizontalMargin);
  static const EdgeInsets screenAllPadding = EdgeInsets.all(horizontalMargin);
  
  // ✅ Espaçamentos para seções de perfil
  static const double profileSectionBottomSpacing = 36;
  static const double profileAboutMeTopSpacing = 24;
  static const EdgeInsets profileSectionPadding = EdgeInsets.only(
    left: horizontalMargin,
    right: horizontalMargin,
    bottom: profileSectionBottomSpacing,
  );
  static const EdgeInsets profileAboutMePadding = EdgeInsets.only(
    left: horizontalMargin,
    right: horizontalMargin,
    bottom: profileSectionBottomSpacing,
  );
  
  // AppBar spacing padrão
  static const double appBarTitleSpacing = horizontalMargin;

  // Tamanhos padrão
  static const double buttonHeight = 55;
  static const double progressIndicatorHeight = 5;
  static const double borderRadius = 40;
  static const double smallBorderRadius = 5;
  
  // Física de rolagem padrão (efeito de bounce)
  // Usamos AlwaysScrollableScrollPhysics como parent para garantir comportamento consistente
  static const ScrollPhysics scrollPhysics = BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
