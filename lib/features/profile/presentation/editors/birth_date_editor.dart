import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_text_field.dart';
import 'package:flutter/material.dart';

/// Editor para o campo "Birth Date"
class BirthDateEditor extends StatelessWidget {
  const BirthDateEditor({
    required this.dayController,
    required this.monthController,
    required this.yearController,
    super.key,
  });

  final TextEditingController dayController;
  final TextEditingController monthController;
  final TextEditingController yearController;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.translate('birth_date'),
          style: const TextStyle(
            color: GlimpseColors.textSubTitle,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
              Expanded(
                child: GlimpseTextField(
                  labelText: i18n.translate('month'),
                  hintText: 'MM',
                  controller: monthController,
                  keyboardType: TextInputType.number,
                  labelStyle: const TextStyle(
                    color: GlimpseColors.textSubTitle,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlimpseTextField(
                  labelText: i18n.translate('day'),
                  hintText: 'DD',
                  controller: dayController,
                  keyboardType: TextInputType.number,
                  labelStyle: const TextStyle(
                    color: GlimpseColors.textSubTitle,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlimpseTextField(
                  labelText: i18n.translate('year'),
                  hintText: 'YYYY',
                  controller: yearController,
                  keyboardType: TextInputType.number,
                  labelStyle: const TextStyle(
                    color: GlimpseColors.textSubTitle,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
  }
}
