import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';

class EventPhotoMoreMenuButton extends StatelessWidget {
  const EventPhotoMoreMenuButton({
    super.key,
    required this.title,
    required this.message,
    required this.destructiveText,
    required this.onConfirmed,
  });

  final String title;
  final String message;
  final String destructiveText;
  final Future<void> Function() onConfirmed;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () async {
        final ok = await GlimpseCupertinoDialog.showDestructive(
          context: context,
          title: title,
          message: message,
          destructiveText: destructiveText,
          cancelText: i18n.translate('cancel'),
        );
        if (ok == true) {
          await onConfirmed();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: const Icon(Iconsax.more, size: 18),
      ),
    );
  }
}
