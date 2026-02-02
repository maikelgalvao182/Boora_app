import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Card de plano de assinatura (mensal ou anual)
/// 
/// Responsabilidades:
/// - Exibir informações do plano (título, descrição, preço)
/// - Indicar visualmente se está selecionado
/// - Responder a taps para seleção
/// 
/// Uso:
/// ```dart
/// SubscriptionPlanCard(
///   package: annualPackage,
///   isSelected: selectedPlan == SubscriptionPlan.annual,
///   onTap: () => setState(() => selectedPlan = SubscriptionPlan.annual),
/// )
/// ```
class SubscriptionPlanCard extends StatelessWidget {

  const SubscriptionPlanCard({
    required this.package, required this.isSelected, required this.onTap, super.key,
  });
  final Package package;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final product = package.storeProduct;
    
    // Cores dinâmicas baseadas no estado de seleção
    final borderColor = isSelected ? GlimpseColors.primary : Colors.grey.shade300;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
          color: Colors.white,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Título do plano
            Text(
              _getTitle(i18n),
              style: const TextStyle(
                fontFamily: FONT_PLUS_JAKARTA_SANS,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            
            const SizedBox(height: 8),
            
            // Preço
            Text(
              product.priceString,
              style: const TextStyle(
                fontFamily: FONT_PLUS_JAKARTA_SANS,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 6),
            
            // Descrição do plano
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                _getDescription(i18n, product),
                style: const TextStyle(
                  fontFamily: FONT_PLUS_JAKARTA_SANS,
                  fontSize: 12,
                  color: GlimpseColors.primary,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Retorna o título do plano baseado no tipo de pacote
  String _getTitle(AppLocalizations i18n) {
    switch (package.packageType) {
      case PackageType.weekly:
        return i18n.translate('weekly_plan_title');
      case PackageType.monthly:
        return i18n.translate('monthly_plan_title');
      case PackageType.annual:
        return i18n.translate('annual_plan_title');
      default:
        return package.storeProduct.title;
    }
  }

  /// Retorna descrição do plano (usa description do produto ou fallback)
  String _getDescription(AppLocalizations i18n, StoreProduct product) {
    if (product.description.isNotEmpty) {
      return product.description;
    }

    // Fallback baseado no tipo de pacote
    switch (package.packageType) {
      case PackageType.weekly:
        return i18n.translate('auto_renews_weekly');
      case PackageType.monthly:
        return i18n.translate('auto_renews_monthly');
      case PackageType.annual:
        return i18n.translate('auto_renews_annually');
      default:
        return product.description;
    }
  }
}
