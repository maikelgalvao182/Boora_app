import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';

/// Widget de seleção de orientação sexual
class SexualOrientationWidget extends StatelessWidget {
  const SexualOrientationWidget({
    required this.initialOrientation,
    required this.onOrientationChanged,
    super.key,
  });

  final String initialOrientation;
  final ValueChanged<String?> onOrientationChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    // Constantes para orientação sexual
    const orientationHeterosexual = 'Heterossexual';
    const orientationHomosexual = 'Homossexual';
    const orientationBisexual = 'Bissexual';
    const orientationOther = 'Outro';
    const orientationPreferNotToSay = 'Prefiro não informar';
    
    // Lista de opções
    final orientationOptions = [
      orientationHeterosexual,
      orientationHomosexual,
      orientationBisexual,
      orientationOther,
      orientationPreferNotToSay,
    ];
    
    return GlimpseDropdown(
      labelText: i18n.translate('sexual_orientation_label'),
      hintText: i18n.translate('sexual_orientation_hint'),
      items: orientationOptions,
      selectedValue: initialOrientation.isNotEmpty ? initialOrientation : null,
      labelStyle: GlimpseStyles.fieldLabelStyle(
        color: Theme.of(context).textTheme.titleMedium?.color,
      ).copyWith(fontSize: 14.sp),
      itemBuilder: (item) {
        if (item == orientationHeterosexual) {
          return i18n.translate('sexual_orientation_heterosexual');
        }
        if (item == orientationHomosexual) {
          return i18n.translate('sexual_orientation_homosexual');
        }
        if (item == orientationBisexual) {
          return i18n.translate('sexual_orientation_bisexual');
        }
        if (item == orientationOther) {
          return i18n.translate('sexual_orientation_other');
        }
        if (item == orientationPreferNotToSay) {
          return i18n.translate('sexual_orientation_prefer_not_to_say');
        }
        return item;
      },
      onChanged: onOrientationChanged,
    );
  }
}
