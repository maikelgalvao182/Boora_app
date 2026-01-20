import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Tipos de horário disponíveis
enum TimeType {
  flexible,
  specific,
}

/// Widget de seleção de tipo de horário
/// Exibe dois cards: Flexível e Específico
class TimeTypeSelector extends StatelessWidget {
  const TimeTypeSelector({
    required this.selectedType,
    required this.onTypeSelected,
    super.key,
  });

  final TimeType? selectedType;
  final ValueChanged<TimeType> onTypeSelected;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          child: _TimeTypeCard(
            type: TimeType.flexible,
            title: i18n.translate('flexible_time'),
            subtitle: i18n.translate('time_type_flexible_subtitle'),
            icon: IconsaxPlusLinear.clock,
            isSelected: selectedType == TimeType.flexible,
            onTap: () => onTypeSelected(TimeType.flexible),
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: _TimeTypeCard(
            type: TimeType.specific,
            title: i18n.translate('specific_time'),
            subtitle: i18n.translate('time_type_specific_subtitle'),
            icon: IconsaxPlusLinear.timer,
            isSelected: selectedType == TimeType.specific,
            onTap: () => onTypeSelected(TimeType.specific),
          ),
        ),
      ],
    );
  }
}

/// Card individual de tipo de horário
class _TimeTypeCard extends StatelessWidget {
  const _TimeTypeCard({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final TimeType type;
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
