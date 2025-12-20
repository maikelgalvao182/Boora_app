import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

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
    return Row(
      children: [
        Expanded(
          child: _PrivacyTypeCard(
            type: PrivacyType.open,
            title: 'Aberto',
            subtitle: 'Livre para participar',
            icon: IconsaxPlusLinear.people,
            isSelected: selectedType == PrivacyType.open,
            onTap: () => onTypeSelected(PrivacyType.open),
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: _PrivacyTypeCard(
            type: PrivacyType.private,
            title: 'Privado',
            subtitle: 'Precisa de aprovação',
            icon: IconsaxPlusLinear.lock,
            isSelected: selectedType == PrivacyType.private,
            onTap: () => onTypeSelected(PrivacyType.private),
          ),
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
          color: isSelected
              ? GlimpseColors.primaryLight
              : GlimpseColors.lightTextField,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(
                  color: GlimpseColors.primary,
                  width: 2,
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícone
            Icon(
              icon,
              color: isSelected
                  ? GlimpseColors.primary
                  : GlimpseColors.textSubTitle,
              size: 24,
            ),

            const SizedBox(height: 12),

            // Textos
            Column(
              children: [
                Text(
                  title,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: GlimpseColors.primaryColorLight,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: GlimpseColors.textSubTitle,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
