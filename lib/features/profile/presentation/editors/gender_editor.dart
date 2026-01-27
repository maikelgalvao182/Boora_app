import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_dropdown.dart';
import 'package:flutter/material.dart';

/// Editor para o campo "Gender"
class GenderEditor extends StatelessWidget {
  const GenderEditor({
    required this.controller,
    super.key,
  });

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return GlimpseDropdown(
      labelText: i18n.translate('gender_label'),
      hintText: i18n.translate('select_your_gender_edit'),
      items: [
        _translateGender(context, GENDER_MAN),
        _translateGender(context, GENDER_WOMAN),
        _translateGender(context, GENDER_TRANS),
        _translateGender(context, GENDER_OTHER),
      ],
      selectedValue: _translateGender(context, controller.text),
      onChanged: (value) {
        final englishValue = _reverseTranslateGender(context, value ?? '');
        controller.text = englishValue;
      },
      labelStyle: GlimpseStyles.fieldLabelStyle(
        color: Theme.of(context).textTheme.titleMedium?.color,
      ),
    );
  }

  String _translateGender(BuildContext context, String gender) {
    final i18n = AppLocalizations.of(context);
    switch (gender) {
      case GENDER_MAN:
        return i18n.translate('male');
      case GENDER_WOMAN:
        return i18n.translate('female');
      case GENDER_TRANS:
        return i18n.translate('gender_trans');
      case GENDER_OTHER:
        return i18n.translate('gender_non_binary');
      default:
        return gender;
    }
  }

  String _reverseTranslateGender(BuildContext context, String translatedGender) {
    final i18n = AppLocalizations.of(context);
    if (translatedGender == i18n.translate('male')) {
      return GENDER_MAN;
    } else if (translatedGender == i18n.translate('female')) {
      return GENDER_WOMAN;
    } else if (translatedGender == i18n.translate('gender_trans')) {
      return GENDER_TRANS;
    } else if (translatedGender == i18n.translate('gender_non_binary')) {
      return GENDER_OTHER;
    }
    return translatedGender;
  }
}
