import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart' show DateFormat;

/// Badge indicando que o usuário tem assinatura VIP ativa
/// 
/// Responsabilidades:
/// - Mostrar status "Wedconnex Pro Ativo"
/// - Exibir data de expiração se disponível
/// - Estilo visual com ícone de verificação
/// 
/// Uso:
/// ```dart
/// if (hasVipAccess) {
///   SubscriptionActiveBadge(
///     expirationDate: customerInfo?.latestExpirationDate,
///   )
/// }
/// ```
class SubscriptionActiveBadge extends StatelessWidget {

  const SubscriptionActiveBadge({
    super.key,
    this.expirationDate,
  });
  final String? expirationDate;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          // Ícone de verificação
          const Icon(
            IconsaxPlusLinear.verify,
            color: Colors.green,
            size: 24,
          ),
          
          const SizedBox(width: 12),
          
          // Informações de status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status principal
                Text(
                  i18n.translate('wedconnex_pro_active'),
                  style: const TextStyle(
                    fontFamily: FONT_PLUS_JAKARTA_SANS,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                
                // Data de expiração (se disponível)
                if (expirationDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${i18n.translate('expires_on')}: ${_formatExpirationDate(expirationDate)}',
                      style: TextStyle(
                        fontFamily: FONT_PLUS_JAKARTA_SANS,
                        fontSize: 12,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Formata data de expiração de forma segura
  String _formatExpirationDate(String? rawDate) {
    if (rawDate == null) return '--';
    
    try {
      final date = DateTime.parse(rawDate);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (_) {
      // Se não conseguir parsear, retorna string original
      return rawDate;
    }
  }
}
