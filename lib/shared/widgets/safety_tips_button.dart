import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget com ícone de segurança e dialog de dicas
class SafetyTipsButton extends StatelessWidget {
  const SafetyTipsButton({super.key});

  void _showSafetyDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: FadeTransition(
            opacity: curvedAnimation,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.all(20),
                  constraints: const BoxConstraints(maxWidth: 500),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const _SafetyDialogContent(),
                ),
              ),
            ),
          ),
        );
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
        onPressed: () => _showSafetyDialog(context),
      ),
    );
  }
}

class _SafetyDialogContent extends StatelessWidget {
  const _SafetyDialogContent();

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Título
          Text(
            'Dicas de Segurança',
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: GlimpseColors.primaryColorLight,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Fique seguro durante os encontros',
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: GlimpseColors.primaryColorLight,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Dicas
          _SafetyTipItem(
            icon: IconsaxPlusLinear.people,
            title: 'Priorize locais públicos',
            description: 'Prefira locais públicos, bem iluminados e com outras pessoas por perto.',
          ),
          const SizedBox(height: 16),
          _SafetyTipItem(
            icon: IconsaxPlusLinear.car,
            title: 'Tenha controle sobre seu transporte',
            description: 'Vá e volte por conta própria, assim você pode ir embora quando quiser.',
          ),
          const SizedBox(height: 16),
          _SafetyTipItem(
            icon: Iconsax.eye,
            title: 'Fique atenta(o) às bebidas',
            description: 'Cuide da sua bebida e não aceite bebidas de desconhecidos.',
          ),
          const SizedBox(height: 16),
          _SafetyTipItem(
            icon: IconsaxPlusLinear.message_text,
            title: 'Mantenha a conversa dentro do app',
            description: 'Use o chat do app para ter conversas mais seguras e moderadas.',
          ),
          const SizedBox(height: 16),
          _SafetyTipItem(
            icon: IconsaxPlusLinear.user_tag,
            title: 'Avise alguém de confiança',
            description: 'Compartilhe os detalhes do encontro e a localização com um amigo ou familiar.',
          ),
          const SizedBox(height: 24),

          // Link para mais informações
          GestureDetector(
            onTap: () => _launchUrl(BOORA_SAFETY_ETIQUETTE_URL),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  IconsaxPlusLinear.info_circle,
                  size: 18,
                  color: GlimpseColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Saiba mais sobre dicas de segurança',
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: GlimpseColors.primary,
                    decoration: TextDecoration.underline,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Botão Fechar
          GlimpseButton(
            text: 'Fechar',
            backgroundColor: GlimpseColors.primary,
            textColor: Colors.white,
            height: 52,
            noPadding: true,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
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
        // Ícone com fundo
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
        // Título e descrição
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
