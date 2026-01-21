import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Tipos de privacidade disponíveis
enum PrivacyType {
  open,
  private,
}

/// Widget de seleção de tipo de privacidade
/// Exibe dois cards: Aberto e Privado
class PrivacyTypeSelector extends StatelessWidget {
  const PrivacyTypeSelector({
    required this.selectedType,
    required this.onTypeSelected,
    super.key,
  });

  final PrivacyType? selectedType;
  final ValueChanged<PrivacyType> onTypeSelected;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Column(
      children: [
        _PrivacyTypeCard(
          type: PrivacyType.open,
          title: i18n.translate('privacy_type_open_title'),
          subtitle: i18n.translate('privacy_type_open_subtitle'),
          icon: IconsaxPlusLinear.people,
          isSelected: selectedType == PrivacyType.open,
          onTap: () => onTypeSelected(PrivacyType.open),
        ),

        const SizedBox(height: 12),

        _PrivacyTypeCard(
          type: PrivacyType.private,
          title: i18n.translate('privacy_type_private_title'),
          subtitle: i18n.translate('privacy_type_private_subtitle'),
          icon: IconsaxPlusLinear.lock,
          isSelected: selectedType == PrivacyType.private,
          onTap: () => onTypeSelected(PrivacyType.private),
        ),
      ],
    );
  }
}

/// Card individual de tipo de privacidade
class _PrivacyTypeCard extends StatelessWidget {
  const _PrivacyTypeCard({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final PrivacyType type;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? Border.all(
                  color: GlimpseColors.primary,
                  width: 2,
                )
              : Border.all(
                  color: Colors.transparent,
                  width: 2,
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Ícone à esquerda
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? GlimpseColors.primaryLight
                    : GlimpseColors.lightTextField,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: Colors.black,
                  size: 24,
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Textos à direita
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: GlimpseColors.primaryColorLight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: GlimpseColors.textSubTitle,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
