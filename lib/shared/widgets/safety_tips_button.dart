import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget com ícone de segurança e dialog de dicas
class SafetyTipsButton extends StatelessWidget {
  const SafetyTipsButton({super.key});

  void _showSafetyBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return const _SafetyTipsBottomSheet();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: const Icon(
          IconsaxPlusLinear.shield_tick,
          size: 24,
          color: GlimpseColors.textSubTitle,
        ),
        onPressed: () => _showSafetyBottomSheet(context),
      ),
    );
  }
}

class _SafetyTipsBottomSheet extends StatelessWidget {
  const _SafetyTipsBottomSheet();

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 20, right: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: GlimpseColors.borderColorLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    i18n.translate('safety_tips_title'),
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: GlimpseColors.primaryColorLight,
                    ),
                    maxLines: 2,
                    textAlign: TextAlign.left,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    i18n.translate('safety_tips_subtitle'),
                    textAlign: TextAlign.left,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GlimpseColors.textSubTitle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    _SafetyTipItem(
                      icon: IconsaxPlusBold.verify,
                      title: i18n.translate('onboarding_verified_title'),
                      description: 'Prefira conversar e marcar encontros com perfis verificados. Se algo não bater, melhor não marcar e seguir em frente.',
                    ),
                    const SizedBox(height: 16),
                    _SafetyTipItem(
                      icon: IconsaxPlusBold.star_1,
                      title: i18n.translate('onboarding_reputation_title'),
                      description: i18n.translate('onboarding_reputation_text'),
                    ),
                    const SizedBox(height: 16),
                    _SafetyTipItem(
                      icon: IconsaxPlusBold.shield_tick,
                      title: i18n.translate('onboarding_safety_title'),
                      description: i18n.translate('onboarding_safety_text'),
                    ),
                    const SizedBox(height: 16),
                    _SafetyTipItem(
                      icon: IconsaxPlusBold.flag_2,
                      title: i18n.translate('onboarding_report_title'),
                      description: 'Viu comportamento estranho, perfil suspeito ou algo inadequado no mapa ou nos chats? Denuncie e bloqueie pelo app.',
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GlimpseButton(
                text: i18n.translate('safety_tips_learn_more'),
                backgroundColor: GlimpseColors.primary,
                height: 52,
                noPadding: true,
                onTap: () => _launchUrl(BOORA_SAFETY_ETIQUETTE_URL),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}

class _SafetyTipItem extends StatelessWidget {
  const _SafetyTipItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: GlimpseColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: GlimpseColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: GlimpseColors.textSubTitle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
