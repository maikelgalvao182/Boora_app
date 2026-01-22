import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Lista de benefícios da assinatura VIP
/// 
/// Responsabilidades:
/// - Exibir lista de benefícios do Wedconnex Pro
/// - Ícones e descrições dos recursos
/// 
/// Uso:
/// ```dart
/// const SubscriptionBenefitsList()
/// ```
class SubscriptionBenefitsList extends StatelessWidget {
  const SubscriptionBenefitsList({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final benefits = _getBenefits(i18n);

    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: benefits
              .map((benefit) => _BenefitItem(benefit: benefit))
              .toList(),
        ),
      ),
    );
  }

  List<_Benefit> _getBenefits(AppLocalizations i18n) {
    return [
      // 👀 Veja quem se interessou por você
      _Benefit(
        icon: IconsaxPlusLinear.eye,
        title: i18n.translate('subscription_benefit_profile_visits_title'),
        subtitle: i18n.translate('subscription_benefit_profile_visits_subtitle'),
      ),

      // ⭐ Apareça primeiro no mapa
      _Benefit(
        icon: IconsaxPlusLinear.star,
        title: i18n.translate('subscription_benefit_more_visibility_title'),
        subtitle: i18n.translate('subscription_benefit_more_visibility_subtitle'),
      ),

      // 🗺️ Acesse todos os perfis da área
      _Benefit(
        icon: IconsaxPlusLinear.people,
        title: i18n.translate('subscription_benefit_unlock_people_list_title'),
        subtitle: i18n.translate('subscription_benefit_unlock_people_list_subtitle'),
      ),

      // 🚀 Destaque seus eventos no topo do mapa
      _Benefit(
        icon: IconsaxPlusLinear.map,
        title: i18n.translate('subscription_benefit_event_promo_title'),
        subtitle: i18n.translate('subscription_benefit_event_promo_subtitle'),
      ),
    ];
  }
}

/// Modelo de benefício
class _Benefit {

  const _Benefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
}

/// Widget individual de benefício
class _BenefitItem extends StatelessWidget {

  const _BenefitItem({required this.benefit});
  final _Benefit benefit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: GlimpseColors.primaryLight,
            child: Icon(
              benefit.icon,
              color: GlimpseColors.primary,
            ),
          ),
          title: Text(
            benefit.title,
            style: const TextStyle(
              fontFamily: FONT_PLUS_JAKARTA_SANS,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          subtitle: Text(benefit.subtitle),
        ),
        const Divider(height: 10),
      ],
    );
  }
}
