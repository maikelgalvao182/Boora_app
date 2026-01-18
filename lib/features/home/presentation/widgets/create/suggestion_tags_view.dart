import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_variables.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/tag_vendor.dart';

/// Widget que exibe uma nuvem de tags de sugestão de atividades
class SuggestionTagsView extends StatelessWidget {
  const SuggestionTagsView({
    required this.onSuggestionSelected,
    super.key,
  });

  final ValueChanged<ActivitySuggestion> onSuggestionSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Wrap(
        spacing: 8,
        runSpacing: 12,
        children: activitySuggestions.map((suggestion) {
          final labelText = AppLocalizations.of(context).translate(suggestion.textKey);
          return TagVendor(
            label: '${suggestion.emoji} $labelText',
            onTap: () => onSuggestionSelected(suggestion),
            isSelected: false,
            backgroundColor: GlimpseColors.primaryLight,
            borderColor: Colors.transparent,
          );
        }).toList(),
      ),
    );
  }
}
