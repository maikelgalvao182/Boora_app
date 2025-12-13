import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Widget de estado de carregamento para planos de assinatura
/// 
/// Responsabilidades:
/// - Mostrar indicador de loading
/// - Exibir mensagem informativa
/// 
/// Uso:
/// ```dart
/// if (isLoading) {
///   return const SubscriptionLoadingState();
/// }
/// ```
class SubscriptionLoadingState extends StatelessWidget {
  const SubscriptionLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Center(
        child: Column(
          children: [
            const CupertinoActivityIndicator(
              radius: 14,
              color: Colors.black,
            ),
            const SizedBox(height: 16),
            Text(
              i18n.translate('loading_subscription_plans'),
              style: const TextStyle(
                fontFamily: FONT_PLUS_JAKARTA_SANS,
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget de estado de erro para planos de assinatura
/// 
/// Responsabilidades:
/// - Mostrar ícone de erro
/// - Exibir mensagem de erro
/// - (Opcional) Botão para tentar novamente
/// 
/// Uso:
/// ```dart
/// if (error != null) {
///   return SubscriptionErrorState(
///     error: error,
///     onRetry: () => loadPlans(),
///   );
/// }
/// ```
class SubscriptionErrorState extends StatelessWidget {

  const SubscriptionErrorState({
    required this.error, super.key,
    this.onRetry,
  });
  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              i18n.translate('error_loading_plans'),
              style: const TextStyle(
                fontFamily: FONT_PLUS_JAKARTA_SANS,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                fontFamily: FONT_PLUS_JAKARTA_SANS,
                fontSize: 13,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            
            // Botão de retry (se fornecido)
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(i18n.translate('try_again')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget de estado vazio (sem planos disponíveis)
/// 
/// Responsabilidades:
/// - Mostrar ícone de sacola de compras
/// - Exibir mensagem informativa
/// 
/// Uso:
/// ```dart
/// if (plans.isEmpty) {
///   return const SubscriptionEmptyState();
/// }
/// ```
class SubscriptionEmptyState extends StatelessWidget {
  const SubscriptionEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.shopping_bag_outlined,
              size: 48,
              color: Colors.black38,
            ),
            const SizedBox(height: 16),
            Text(
              i18n.translate('no_plans_available'),
              style: const TextStyle(
                fontFamily: FONT_PLUS_JAKARTA_SANS,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              i18n.translate('please_try_again_later'),
              style: const TextStyle(
                fontFamily: FONT_PLUS_JAKARTA_SANS,
                fontSize: 13,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
