import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Centralized styles for EditProfile components
/// Following Flutter best practices for style separation
class EditProfileStyles {
  // Private constructor to prevent instantiation
  EditProfileStyles._();

  // =============================================================================
  // COLORS
  // =============================================================================
  static const Color backgroundColor = Colors.white;
  static Color get textSubTitle => GlimpseColors.textSubTitle;
  static Color get actionColor => GlimpseColors.actionColor;
  static Color get primaryColorLight => GlimpseColors.primaryColorLight;
  
  // =============================================================================
  // DIMENSIONS & SPACING
  // =============================================================================
  static double get profilePhotoSize => 88.w;
  static double get cameraButtonSize => 35.w;
  static double get cameraButtonRadius => 17.5.r;
  static double get profilePhotoBorderRadius => 12.r;
  static double get cameraButtonBorderWidth => 1.5.w;
  
  // Camera button positioning
  static double get cameraButtonRight => -5.w;
  static double get cameraButtonBottom => -4.h;
  
  // AppBar dimensions
  static double get appBarIconSize => 24.sp;
  static double get appBarIconWidth => 28.w;
  static double get appBarRightPadding => 20.w;
  
  // Icon sizes
  static double get cameraIconSize => 18.sp;
  
  // =============================================================================
  // SPACING
  // =============================================================================
  static EdgeInsets get screenPadding => GlimpseStyles.screenAllPadding;
  static double get horizontalMargin => GlimpseStyles.horizontalMargin;
  
  static EdgeInsets get profilePhotoSpacing => EdgeInsets.only(bottom: 8.h);
  static EdgeInsets get tabSpacing => EdgeInsets.only(bottom: 16.h);
  static EdgeInsets get contentSpacing => EdgeInsets.only(bottom: 20.h);
  
  // =============================================================================
  // TEXT STYLES
  // =============================================================================
  static TextStyle get appBarTitleStyle => TextStyle(
    fontSize: 20.sp,
    fontWeight: FontWeight.w700,
  );
  
  static TextStyle get saveButtonStyle => TextStyle(
    fontSize: 16.sp,
    fontWeight: FontWeight.w600,
    color: actionColor,
  );
  
  // =============================================================================
  // DECORATIONS
  // =============================================================================
  static BoxDecoration get profilePhotoDecoration => BoxDecoration(
    borderRadius: BorderRadius.circular(profilePhotoBorderRadius),
  );
  
  static BoxDecoration get cameraButtonDecoration => BoxDecoration(
    color: GlimpseColors.primaryColorLight,
    borderRadius: BorderRadius.circular(cameraButtonRadius),
    border: Border.all(color: Colors.white, width: cameraButtonBorderWidth),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ],
  );
  
  // =============================================================================
  // BUTTON STYLES
  // =============================================================================
  static TextStyle get saveButtonTextStyle => TextStyle(
    fontSize: 14.sp,
    fontWeight: FontWeight.w600,
    color: actionColor,
  );
  
  // =============================================================================
  // CONSTRAINTS & SIZING
  // =============================================================================
  static const BoxConstraints iconButtonConstraints = BoxConstraints();
  static const Size minimumButtonSize = Size.zero;
  
  // =============================================================================
  // ASSETS
  // =============================================================================
  static const String cameraIcon = 'assets/svg/camera.svg';

  // =============================================================================
  // FORM STYLES
  // =============================================================================
  
  // Form colors
  static Color get labelTextColor => GlimpseColors.textSubTitle;
  static Color get inputTextColor => GlimpseColors.textSubTitle;
  static Color get borderColor => GlimpseColors.borderColorLight;
  
  // Form spacing
  static EdgeInsets get formPadding => EdgeInsets.all(16.w);
  static SizedBox get verticalSpacing => SizedBox(height: 16.h);
  static double get inputBorderRadius => 8.r;
  
  // Form text styles
  static TextStyle get labelTextStyle => TextStyle(
    fontSize: 14.sp,
    fontWeight: FontWeight.w500,
    color: GlimpseColors.textSubTitle,
  );
  
  static TextStyle get inputTextStyle => TextStyle(
    fontSize: 16.sp,
    fontWeight: FontWeight.w500,
    color: GlimpseColors.textSubTitle,
  );
  
  static TextStyle get placeholderTextStyle => TextStyle(
    fontSize: 16.sp,
    fontWeight: FontWeight.w400,
    color: GlimpseColors.textSubTitle,
  );
  
  // Form configurations
  static const int aboutMaxLines = 3;
  
  // Input decorations
  static InputDecoration baseInputDecoration({
    required String labelText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: labelTextStyle,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputBorderRadius),
        borderSide: const BorderSide(color: GlimpseColors.borderColorLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputBorderRadius),
        borderSide: const BorderSide(color: GlimpseColors.borderColorLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputBorderRadius),
        borderSide: const BorderSide(color: GlimpseColors.primaryColorLight, width: 2),
      ),
      suffixIcon: suffixIcon,
    );
  }
  
  static InputDecoration nameInputDecoration(String labelText) {
    return baseInputDecoration(labelText: labelText);
  }
  
  static InputDecoration aboutInputDecoration(String labelText) {
    return baseInputDecoration(labelText: labelText);
  }
  
  static InputDecoration locationInputDecoration(String labelText) {
    return baseInputDecoration(
      labelText: labelText,
      suffixIcon: const Icon(Icons.location_on),
    );
  }
  
  static InputDecoration phoneInputDecoration(String labelText) {
    return baseInputDecoration(labelText: labelText);
  }
}
