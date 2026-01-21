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

    return Column(
      children: [
        _TimeTypeCard(
          type: TimeType.flexible,
          title: i18n.translate('flexible_time'),
          subtitle: i18n.translate('time_type_flexible_subtitle'),
          icon: IconsaxPlusLinear.clock,
          isSelected: selectedType == TimeType.flexible,
          onTap: () => onTypeSelected(TimeType.flexible),
        ),
        
        const SizedBox(height: 12),
        
        _TimeTypeCard(
          type: TimeType.specific,
          title: i18n.translate('specific_time'),
          subtitle: i18n.translate('time_type_specific_subtitle'),
          icon: IconsaxPlusLinear.timer,
          isSelected: selectedType == TimeType.specific,
          onTap: () => onTypeSelected(TimeType.specific),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? GlimpseColors.primary : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Ícone dentro de container circular
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? GlimpseColors.primary.withValues(alpha: 0.12)
                    : GlimpseColors.lightTextField,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: Colors.black,
                size: 24,
              ),
            ),
            
            const SizedBox(width: 12),

            // Textos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: GlimpseColors.primaryColorLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
