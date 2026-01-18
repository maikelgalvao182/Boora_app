import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';

class ProfileActionsSection extends StatelessWidget {
  const ProfileActionsSection({
    super.key,
    this.onAddFriend,
    this.onMessage,
  });

  final VoidCallback? onAddFriend;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final label = i18n.translate('send_message').isNotEmpty
        ? i18n.translate('send_message')
        : 'Enviar mensagem';

    return Container(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 22),
      child: GlimpseButton(
        text: label,
        backgroundColor: GlimpseColors.primary,
        textColor: Colors.white,
        icon: Iconsax.message,
        onTap: onMessage ?? () {},
      ),
    );
  }
}
