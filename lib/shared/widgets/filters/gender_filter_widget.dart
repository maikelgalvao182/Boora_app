import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_dropdown.dart';

/// Widget de filtro de gênero
class GenderFilterWidget extends StatelessWidget {
  const GenderFilterWidget({
    super.key,
    required this.selectedGender,
    required this.onChanged,
  });

  final String? selectedGender;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.translate('gender_label'),
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
          hintText: i18n.translate('gender'),
          items: [
            i18n.translate('all_genders'),
            i18n.translate('male'),
            i18n.translate('female'),
            i18n.translate('gender_non_binary'),
          ],
          selectedValue: _getGenderDisplayValue(i18n),
          onChanged: (value) {
            String? newGender;
            if (value == i18n.translate('all_genders')) {
              newGender = 'all';
            } else if (value == i18n.translate('male')) {
              newGender = 'male';
            } else if (value == i18n.translate('female')) {
              newGender = 'female';
            } else if (value == i18n.translate('gender_non_binary')) {
              newGender = 'non_binary';
            }
            onChanged(newGender);
          },
        ),
      ],
    );
  }

  String? _getGenderDisplayValue(AppLocalizations i18n) {
    switch (selectedGender) {
      case 'all':
        return i18n.translate('all_genders');
      case 'male':
        return i18n.translate('male');
      case 'female':
        return i18n.translate('female');
      case 'non_binary':
        return i18n.translate('gender_non_binary');
      default:
        return null;
    }
  }
}
