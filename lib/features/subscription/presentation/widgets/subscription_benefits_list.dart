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
      // Desbloqueie a lista completa de pessoas
      _Benefit(
        icon: IconsaxPlusLinear.people,
        title: 'Desbloqueie a lista completa de pessoas',
        subtitle: 'Veja quem está por perto e também quem estará nos seus próximos destinos.',
      ),

      // Mais visibilidade no app
      _Benefit(
        icon: IconsaxPlusLinear.chart,
        title: 'Mais visibilidade no app',
        subtitle: 'Seu perfil aparece com prioridade no topo da lista de pessoas próximas.',
      ),

      // Veja quem visitou seu perfil
      _Benefit(
        icon: IconsaxPlusLinear.eye,
        title: 'Veja quem visitou seu perfil',
        subtitle: 'Descubra quem se interessou por você e acessou seu perfil recentemente.',
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
            backgroundColor: GlimpseColors.primary,
            child: Icon(
              benefit.icon,
              color: Colors.white,
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
