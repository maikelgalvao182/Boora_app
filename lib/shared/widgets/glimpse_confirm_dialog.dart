import 'package:partiu/shared/widgets/dialogs/dialog_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Shows a custom-styled confirmation dialog consistent with Glimpse UI.
/// Returns true if confirmed, false if cancelled, and null if dismissed.
Future<bool?> showGlimpseConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  IconData? icon,
  bool isDestructive = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _GlimpseConfirmPanel(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      icon: icon,
      isDestructive: isDestructive,
    ),
  );
}

class _GlimpseConfirmPanel extends StatelessWidget {

  const _GlimpseConfirmPanel({
    required this.title,
    required this.confirmLabel, required this.cancelLabel, required this.isDestructive, this.message,
    this.icon,
  });
  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final IconData? icon;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: DialogStyles.containerMargin,
        decoration: DialogStyles.containerDecoration,
        padding: DialogStyles.containerPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon at top (fixed red trash icon from Iconsax)
            Padding(
              padding: EdgeInsets.only(top: 8.h),
              child: Container(
                height: 56.h,
                width: 56.w,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    IconsaxPlusLinear.trash,
                    color: Colors.red,
                    size: 28.sp,
                  ),
                ),
              ),
            ),
            const SizedBox(height: DialogStyles.spacingAfterIcon),
            // Icon (if provided)
            if (icon != null) ...[
              DialogStyles.buildIconContainer(
                icon: isDestructive
                    ? DialogStyles.buildDeleteIcon(icon: icon!, iconSize: 24.sp)
                    : DialogStyles.buildInfoIcon(icon: icon!, iconSize: 24),
              ),
              const SizedBox(height: DialogStyles.spacingAfterIcon),
            ],
            // Title
            DialogStyles.buildTitle(title),
            if (message != null) ...[
              const SizedBox(height: DialogStyles.spacingAfterTitle),
              DialogStyles.buildMessage(message!),
            ],
            const SizedBox(height: DialogStyles.spacingBeforeButtons),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: DialogStyles.negativeButtonStyle,
                    child: Text(
                      cancelLabel,
                      style: DialogStyles.negativeButtonTextStyle,
                    ),
                  ),
                ),
                const SizedBox(width: DialogStyles.buttonSpacing),
                if (isDestructive)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: DialogStyles.positiveButtonStyle,
                      child: Text(
                        confirmLabel,
                        style: DialogStyles.positiveButtonTextStyle,
                      ),
                    ),
                  )
                else
                  DialogStyles.buildInfoButton(
                    text: confirmLabel,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}