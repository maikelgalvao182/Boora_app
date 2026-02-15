import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Diálogo de confirmação para exclusão de conta
class DeleteAccountConfirmDialog {
  static Future<bool?> show(
    BuildContext context, {
    required IconData iconData,
    required String title,
    required String message,
    required String negativeText,
    required String positiveText,
    required VoidCallback negativeAction,
    required VoidCallback positiveAction,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final isCompactScreen = MediaQuery.sizeOf(dialogContext).width <= 360;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          title: Row(
            children: [
              Icon(
                iconData,
                color: Colors.red,
                size: 28.sp,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: (isCompactScreen ? 18 : 20).sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: TextStyle(
              fontSize: (isCompactScreen ? 15 : 16).sp,
              color: Color(0xFF6F6E6E),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: negativeAction,
              style: TextButton.styleFrom(
                foregroundColor: Color(0xFF6F6E6E),
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
              ),
              child: Text(
                negativeText,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: (isCompactScreen ? 13 : 14).sp,
                ),
              ),
            ),
            TextButton(
              onPressed: positiveAction,
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
              ),
              child: Text(
                positiveText,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: (isCompactScreen ? 13 : 14).sp,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
