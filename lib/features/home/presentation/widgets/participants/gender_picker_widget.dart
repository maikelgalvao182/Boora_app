import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget de seleção de gênero estilo "wheel" (iOS picker)
class GenderPickerWidget extends StatelessWidget {
  const GenderPickerWidget({
    required this.selectedGender,
    required this.onGenderChanged,
    super.key,
  });

  final String selectedGender;
  final ValueChanged<String> onGenderChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    // Lista de gêneros disponíveis para seleção (excluindo 'All' que é tratado pelo tipo)
    final genders = [
      GENDER_MAN,
      GENDER_WOMAN,
      GENDER_TRANS,
      GENDER_OTHER,
    ];

    // Encontrar índice inicial
    int initialIndex = genders.indexOf(selectedGender);
    if (initialIndex == -1) initialIndex = 0;

    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: GlimpseColors.lightTextField,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CupertinoTheme(
        data: CupertinoThemeData(
          textTheme: CupertinoTextThemeData(
            pickerTextStyle: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: GlimpseColors.primaryColorLight,
            ),
          ),
        ),
        child: CupertinoPicker(
          scrollController: FixedExtentScrollController(initialItem: initialIndex),
          itemExtent: 32,
          onSelectedItemChanged: (index) {
            onGenderChanged(genders[index]);
          },
          children: genders.map((gender) {
            return Center(
              child: Text(
                _translateGender(gender, i18n),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _translateGender(String gender, AppLocalizations i18n) {
    switch (gender) {
      case GENDER_MAN:
        return i18n.translate('gender_male');
      case GENDER_WOMAN:
        return i18n.translate('gender_female');
      case GENDER_TRANS:
        return i18n.translate('gender_trans');
      case GENDER_OTHER:
        return i18n.translate('gender_non_binary');
      default:
        return gender;
    }
  }
}
