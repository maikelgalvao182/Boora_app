import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_dropdown.dart';

/// Widget de filtro de orientação sexual
/// Segue o padrão visual dos outros filtros em shared/widgets/filters
class SexualOrientationFilterWidget extends StatelessWidget {
  const SexualOrientationFilterWidget({
    super.key,
    required this.selectedOrientation,
    required this.onChanged,
  });

  final String? selectedOrientation;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    // Opções disponíveis
    const optionAll = 'Todas';
    const optionHeterosexual = 'Heterossexual';
    const optionHomosexual = 'Homossexual';
    const optionBisexual = 'Bissexual';
    const optionOther = 'Outro';
    
    final displayItems = [
      optionAll,
      optionHeterosexual,
      optionHomosexual,
      optionBisexual,
      optionOther,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Orientação Sexual', // Idealmente viria do i18n
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: GlimpseColors.primaryColorLight,
          ),
        ),
        const SizedBox(height: 12),
        GlimpseDropdown(
          labelText: '',
          hintText: 'Selecione',
          items: displayItems,
          selectedValue: _getDisplayValue(selectedOrientation, optionAll),
          onChanged: (value) {
            if (value == optionAll) {
              onChanged('all');
            } else {
              onChanged(value);
            }
          },
        ),
      ],
    );
  }

  String _getDisplayValue(String? internalValue, String optionAll) {
    if (internalValue == null || internalValue == 'all' || internalValue.isEmpty) {
      return optionAll;
    }
    return internalValue;
  }
}
