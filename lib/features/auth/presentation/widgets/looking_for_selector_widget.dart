import 'package:partiu/core/constants/glimpse_variables.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/tag_vendor.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Opções do que o usuário está procurando
class LookingForOption {
  const LookingForOption({
    required this.id,
    required this.nameKey,
    required this.icon,
  });

  final String id;
  final String nameKey;
  final String icon;
}

/// Lista de opções disponíveis
const List<LookingForOption> lookingForOptions = [
  LookingForOption(id: 'friendship', nameKey: 'looking_for_friendship', icon: '👋'),
  LookingForOption(id: 'networking', nameKey: 'looking_for_networking', icon: '💼'),
  LookingForOption(id: 'serious_relationship', nameKey: 'looking_for_serious_relationship', icon: '❤️'),
  LookingForOption(id: 'casual', nameKey: 'looking_for_casual', icon: '✨'),
];

/// Widget de seleção do que o usuário está procurando
/// Permite selecionar até 2 opções
class LookingForSelectorWidget extends StatefulWidget {
  const LookingForSelectorWidget({
    required this.initialSelection,
    required this.onSelectionChanged,
    super.key,
  });

  final String initialSelection;
  final ValueChanged<String?> onSelectionChanged;

  @override
  State<LookingForSelectorWidget> createState() => _LookingForSelectorWidgetState();
}

class _LookingForSelectorWidgetState extends State<LookingForSelectorWidget> {
  final Set<String> _selectedOptions = {};
  bool _hasInitialized = false;
  static const int maxOptions = 2;

  @override
  void initState() {
    super.initState();
    
    // Inicializa com valores do ViewModel se existirem (separados por vírgula)
    if (widget.initialSelection.isNotEmpty && !_hasInitialized) {
      final options = widget.initialSelection.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
      _selectedOptions.addAll(options);
      _hasInitialized = true;
    }
  }

  void _toggleOption(String optionId) {
    setState(() {
      if (_selectedOptions.contains(optionId)) {
        // Remove se já selecionado
        _selectedOptions.remove(optionId);
      } else {
        // Adiciona apenas se não atingiu o limite
        if (_selectedOptions.length < maxOptions) {
          _selectedOptions.add(optionId);
        }
      }
    });
    
    // Notifica mudança com lista separada por vírgulas
    final optionsString = _selectedOptions.join(',');
    widget.onSelectionChanged(optionsString.isNotEmpty ? optionsString : null);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final remaining = maxOptions - _selectedOptions.length;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Contador de selecionados
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: _selectedOptions.isEmpty 
                ? GlimpseColors.lightTextField 
                : GlimpseColors.primaryLight.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _selectedOptions.isEmpty 
                  ? Colors.transparent 
                  : GlimpseColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedOptions.isEmpty
                      ? i18n.translate('choose_up_to_x_options').replaceAll('{max}', maxOptions.toString())
                      : remaining > 0
                          ? i18n.translate('choose_x_more_options').replaceAll('{remaining}', remaining.toString())
                          : i18n.translate('max_options_selected').replaceAll('{max}', maxOptions.toString()),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: GlimpseColors.primaryColorLight,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Tags das opções
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: lookingForOptions.map((option) {
            final isSelected = _selectedOptions.contains(option.id);
            final isDisabled = !isSelected && _selectedOptions.length >= maxOptions;
            final displayLabel = '${option.icon} ${i18n.translate(option.nameKey)}';
            
            return Opacity(
              opacity: isDisabled ? 0.4 : 1.0,
              child: TagVendor(
                label: displayLabel,
                value: option.id,
                isSelected: isSelected,
                onTap: isDisabled ? null : () => _toggleOption(option.id),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
