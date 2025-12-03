import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_variables.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/tag_vendor.dart';

/// Widget compartilhável de seleção de interesses do usuário
/// 
/// Exibe os interesses salvos do usuário (campo interests da coleção Users)
/// e permite selecionar/desselecionar para usar como filtro.
class InterestTagsSelector extends StatelessWidget {
  const InterestTagsSelector({
    super.key,
    required this.userInterests,
    required this.selectedInterests,
    required this.onChanged,
  });

  /// Lista de interesses do usuário (vem do Firestore Users/{userId}/interests)
  final List<String> userInterests;
  
  /// Interesses atualmente selecionados para o filtro
  final Set<String> selectedInterests;
  
  /// Callback chamado quando a seleção muda
  final ValueChanged<Set<String>> onChanged;

  void _toggleInterest(String interestId) {
    final newSelection = Set<String>.from(selectedInterests);
    
    if (newSelection.contains(interestId)) {
      newSelection.remove(interestId);
    } else {
      newSelection.add(interestId);
    }
    
    onChanged(newSelection);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    if (userInterests.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GlimpseColors.lightTextField,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          i18n.translate('no_interests_saved'),
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 14,
            color: GlimpseColors.textSubTitle,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: userInterests.map((interestId) {
        final isSelected = selectedInterests.contains(interestId);
        final tag = getInterestById(interestId.trim());
        final displayLabel = tag != null 
            ? '${tag.icon} ${i18n.translate(tag.nameKey)}'
            : interestId.trim();
        
        return TagVendor(
          label: displayLabel,
          value: interestId,
          isSelected: isSelected,
          onTap: () => _toggleInterest(interestId),
        );
      }).toList(),
    );
  }
}
