import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/dialogs/report_user_dialog.dart';

/// Widget de denúncia/bloqueio de usuário
/// Exibe ícone de flag apenas para visitantes (não para o dono do perfil)
class ReportWidget extends StatelessWidget {
  const ReportWidget({
    super.key,
    required this.userId,
    this.iconSize = 24.0,
    this.iconColor,
    this.onBlockSuccess,
  });

  final String userId;
  final double iconSize;
  final Color? iconColor;
  final VoidCallback? onBlockSuccess;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(
          Iconsax.flag,
          size: iconSize,
          color: iconColor ?? Theme.of(context).iconTheme.color,
        ),
        onPressed: () => _showReportDialog(context),
        tooltip: 'Denunciar ou Bloquear',
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    ReportDialog(
      userId: userId,
      onBlockSuccess: onBlockSuccess,
    ).show(context);
  }
}
