import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/force_update_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dialog de atualização obrigatória
/// 
/// Exibe um dialog não-dismissível que força o usuário a atualizar o app.
/// Só pode ser fechado atualizando o app ou fechando o app completamente.
class ForceUpdateDialog extends StatelessWidget {
  final UpdateInfo updateInfo;
  final bool isRequired;

  const ForceUpdateDialog({
    required this.updateInfo,
    this.isRequired = true,
    super.key,
  });

  /// Mostra o dialog de atualização obrigatória
  /// 
  /// [context] - BuildContext
  /// [updateInfo] - Informações sobre a atualização
  /// [isRequired] - Se true, o dialog não pode ser fechado
  static Future<void> show(
    BuildContext context, {
    required UpdateInfo updateInfo,
    bool isRequired = true,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: !isRequired,
      barrierColor: Colors.black87,
      builder: (context) => PopScope(
        // Bloqueia o botão voltar se for obrigatório
        canPop: !isRequired,
        child: ForceUpdateDialog(
          updateInfo: updateInfo,
          isRequired: isRequired,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        width: size.width * 0.85,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícone
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isRequired
                    ? Colors.red.withOpacity(0.1)
                    : GlimpseColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRequired ? Icons.system_update : Icons.upgrade,
                size: 40,
                color: isRequired ? Colors.red : GlimpseColors.primary,
              ),
            ),
            const SizedBox(height: 20),

            // Título
            Text(
              isRequired
                  ? i18n.translate('force_update_title')
                  : i18n.translate('update_available_title'),
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: GlimpseColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Mensagem
            Text(
              updateInfo.updateMessage ?? 
                  (isRequired
                      ? i18n.translate('force_update_message')
                      : i18n.translate('update_available_message')),
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 14,
                color: GlimpseColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Versões
            Text(
              'v${updateInfo.currentVersion} → v${updateInfo.minimumVersion}',
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 12,
                color: GlimpseColors.textSecondary.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),

            // Botão de atualizar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _openStore(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlimpseColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  i18n.translate('update_now'),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // Botão de "Depois" (só se não for obrigatório)
            if (!isRequired) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  i18n.translate('update_later'),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 14,
                    color: GlimpseColors.textSecondary,
                  ),
                ),
              ),
            ],

            // Botão de fechar app (só se for obrigatório)
            if (isRequired) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _closeApp(),
                child: Text(
                  i18n.translate('close_app'),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 14,
                    color: GlimpseColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openStore(BuildContext context) async {
    final url = updateInfo.storeUrl;
    if (url == null || url.isEmpty) {
      // Fallback para URLs padrão
      final fallbackUrl = Platform.isIOS
          ? 'https://apps.apple.com/app/boora'
          : 'https://play.google.com/store/apps/details?id=com.boora.partiu';
      await _launchUrl(fallbackUrl);
    } else {
      await _launchUrl(url);
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir loja: $e');
    }
  }

  void _closeApp() {
    // Fecha o app
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    } else if (Platform.isIOS) {
      exit(0);
    }
  }
}
