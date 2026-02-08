import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Layout base para as telas de cadastro estilo Glimpse
class GlimpseSignupLayout extends StatelessWidget {

  const GlimpseSignupLayout({
    required this.header,
    required this.content,
    super.key,
    this.bottomButton,
    this.padding,
    this.backgroundColor,
  });
  
  final Widget header;
  final Widget content;
  final Widget? bottomButton;
  final EdgeInsets? padding;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        // Android: dark icons (black)
        statusBarIconBrightness: Brightness.dark,
        // iOS: set light brightness to get dark icons/text
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor ?? Colors.white,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Padding(
            padding: padding ?? EdgeInsets.only(left: GlimpseStyles.horizontalMargin, top: 30.h, right: GlimpseStyles.horizontalMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabeçalho
                header,
                
                // Conteúdo principal
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: bottomButton != null ? 100.h : 20.h,
                    ),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const BouncingScrollPhysics(),
                    child: content,
                  ),
                ),
                
                // Botão fixo na parte inferior
                if (bottomButton != null)
                  Container(
                    padding: EdgeInsets.only(bottom: 20.h),
                    child: bottomButton,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
