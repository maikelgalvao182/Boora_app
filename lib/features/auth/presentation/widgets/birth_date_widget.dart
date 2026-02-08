import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_date_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Widget de seleção de data de nascimento com cálculo de idade
/// Extraído de TelaDataNascimento para reutilização no wizard
class BirthDateWidget extends StatelessWidget {
  const BirthDateWidget({
    required this.initialDate,
    required this.onDateChanged,
    super.key,
  });

  final DateTime? initialDate;
  final ValueChanged<DateTime?> onDateChanged;

  /// Calcula a idade baseada na data de nascimento
  int? _calculateAge(DateTime? birthDate) {
    if (birthDate == null) return null;
    
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    
    // Ajusta se ainda não fez aniversário este ano
    if (now.month < birthDate.month || 
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    
    return age;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final age = _calculateAge(initialDate);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label com idade na mesma row
        Padding(
          padding: EdgeInsets.only(bottom: 0.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                i18n.translate('birth_date'),
                style: GlimpseStyles.fieldLabelStyle(
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
              if (age != null && age >= 0)
                Text(
                  i18n.translate('age_years').replaceAll('{age}', age.toString()),
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: GlimpseColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        
        // Seletor de data de nascimento estilo Glimpse com i18n automático
        GlimpseDatePickerField(
          initialDate: initialDate,
          onDateChanged: onDateChanged,
          minYear: 1960,
          maxYear: DateTime.now().year,
          // hintText agora é gerado automaticamente baseado no locale
          // en: MM-DD-YYYY, pt/es: DD-MM-AAAA
        ),
      ],
    );
  }
}
