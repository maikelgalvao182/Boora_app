import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Footer do dialog de assinatura com termos, privacidade e restore
/// 
/// Responsabilidades:
/// - Exibir texto sobre renovação automática
/// - Links para termos de serviço e privacidade
/// - Link para restaurar compras
/// 
/// Uso:
/// ```dart
/// SubscriptionFooter(
///   onRestore: () async {
///     await provider.restorePurchases();
///     if (provider.hasVipAccess) {
///       showSuccess();
///       closeDialog();
///     }
///   },
/// )
/// ```
class SubscriptionFooter extends StatelessWidget {

  const SubscriptionFooter({
    required this.onRestore, super.key,
  });
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 0, bottom: 16),
      child: Text.rich(
        textAlign: TextAlign.center,
        TextSpan(
          style: const TextStyle(
            fontFamily: FONT_PLUS_JAKARTA_SANS,
            fontSize: 12,
            color: Colors.black87,
          ),
          children: [
            // Texto sobre renovação automática
            TextSpan(
              text: i18n.translate('subscription_renews_automatically_at_the_same'),
            ),
            
            // Link para termos
            TextSpan(
              text: i18n.translate('terms'),
              style: const TextStyle(
                fontFamily: FONT_PLUS_JAKARTA_SANS,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchUrl(
                    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'),
            ),
            
            // Separador "e"
            TextSpan(
              text: i18n.translate('and_separator'),
            ),
            
            // Link para privacidade
            TextSpan(
              text: i18n.translate('privacy'),
              style: const TextStyle(
                fontFamily: FONT_PLUS_JAKARTA_SANS,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchUrl('https://partiu.app/privacy'),
            ),
            
            // Texto antes do restore
            TextSpan(
              text: i18n.translate('have_you_signed_before'),
            ),
            
            // Link para restaurar
            TextSpan(
              text: i18n.translate('restore_subscription_link'),
              style: const TextStyle(
                fontFamily: FONT_PLUS_JAKARTA_SANS,
                fontWeight: FontWeight.w700,
              ),
              recognizer: TapGestureRecognizer()..onTap = onRestore,
            ),
          ],
        ),
      ),
    );
  }

  /// Abre URL em navegador externo
  Future<void> _launchUrl(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
