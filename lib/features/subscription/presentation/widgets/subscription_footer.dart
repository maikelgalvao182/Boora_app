import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:partiu/shared/widgets/terms_and_privacy_links.dart';

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
      child: TermsAndPrivacyLinks(
        prefixText: i18n.translate('subscription_renews_automatically_at_the_same'),
        suffixText: i18n.translate('have_you_signed_before'),
        trailingSpan: TextSpan(
          text: i18n.translate('restore_subscription_link'),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
          recognizer: TapGestureRecognizer()..onTap = onRestore,
        ),
      ),
    );
  }
}
