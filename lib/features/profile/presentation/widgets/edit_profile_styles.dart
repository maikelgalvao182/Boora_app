import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:flutter/material.dart';

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
  static const double profilePhotoSize = 100;
  static const double cameraButtonSize = 35;
  static const double cameraButtonRadius = 17.5;
  static const double profilePhotoBorderRadius = 12;
  static const double cameraButtonBorderWidth = 1.5;
  
  // Camera button positioning
  static const double cameraButtonRight = -12;
  static const double cameraButtonBottom = -4;
  
  // AppBar dimensions
  static const double appBarIconSize = 24;
  static const double appBarIconWidth = 28;
  static const double appBarRightPadding = 20;
  
  // Icon sizes
  static const double cameraIconSize = 18;
  
  // =============================================================================
  // SPACING
  // =============================================================================
  static EdgeInsets get screenPadding => GlimpseStyles.screenAllPadding;
  static double get horizontalMargin => GlimpseStyles.horizontalMargin;
  
  static const EdgeInsets profilePhotoSpacing = EdgeInsets.only(bottom: 8);
  static const EdgeInsets tabSpacing = EdgeInsets.only(bottom: 16);
  static const EdgeInsets contentSpacing = EdgeInsets.only(bottom: 20);
  
  // =============================================================================
  // TEXT STYLES
  // =============================================================================
  static TextStyle get appBarTitleStyle => const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );
  
  static TextStyle get saveButtonStyle => TextStyle(
    fontSize: 16,
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
    color: primaryColorLight,
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
    fontSize: 14,
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
  static Color get snackBarColor => GlimpseColors.primaryColorLight;
  
  // Form spacing
  static const EdgeInsets formPadding = EdgeInsets.all(16);
  static const SizedBox verticalSpacing = SizedBox(height: 16);
  static const double inputBorderRadius = 8;
  
  // Form text styles
  static const TextStyle labelTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: GlimpseColors.textSubTitle,
  );
  
  static const TextStyle inputTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: GlimpseColors.textSubTitle,
  );
  
  static const TextStyle placeholderTextStyle = TextStyle(
    fontSize: 16,
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
  
  // SnackBar styles
  static SnackBar successSnackBar(String message) {
    return SnackBar(
      content: Text(message),
      backgroundColor: GlimpseColors.primaryColorLight,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.all(16),
    );
  }
}
