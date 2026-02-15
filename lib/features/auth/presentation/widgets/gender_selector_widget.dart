import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Widget de seleção de gênero
/// Extraído para reutilização no wizard
class GenderSelectorWidget extends StatelessWidget {
  const GenderSelectorWidget({
    required this.initialGender,
    required this.onGenderChanged,
    super.key,
  });

  final String initialGender;
  final ValueChanged<String?> onGenderChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    // Mapeamento constante -> chave de tradução
    final genderTranslationMap = {
      GENDER_MAN: i18n.translate('gender_male'),
      GENDER_WOMAN: i18n.translate('gender_female'),
      GENDER_TRANS: i18n.translate('gender_trans'),
      GENDER_OTHER: i18n.translate('gender_non_binary'),
    };
    
    // Lista de opções traduzidas
    final genderOptions = [
      GENDER_MAN,
      GENDER_WOMAN,
      GENDER_TRANS,
      GENDER_OTHER,
    ];
    
    return GlimpseDropdown(
      labelText: i18n.translate('gender_label'),
      hintText: i18n.translate('select_gender'),
      items: genderOptions,
      selectedValue: initialGender.isNotEmpty ? initialGender : null,
      onChanged: onGenderChanged,
      labelStyle: GlimpseStyles.fieldLabelStyle(
        color: Theme.of(context).textTheme.titleMedium?.color,
      ).copyWith(fontSize: 14.sp),
      // Usar itemBuilder para exibir traduzido
      itemBuilder: (item) => genderTranslationMap[item] ?? item,
    );
  }
}
