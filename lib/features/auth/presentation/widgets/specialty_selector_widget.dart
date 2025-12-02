import 'package:partiu/core/constants/glimpse_variables.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/tag_vendor.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Widget de seleção de interesses organizados por categoria
/// Permite selecionar até 6 interesses
class SpecialtySelectorWidget extends StatefulWidget {
  const SpecialtySelectorWidget({
    required this.initialSpecialty,
    required this.onSpecialtyChanged,
    super.key,
  });

  final String initialSpecialty;
  final ValueChanged<String?> onSpecialtyChanged;

  @override
  State<SpecialtySelectorWidget> createState() => _SpecialtySelectorWidgetState();
}

class _SpecialtySelectorWidgetState extends State<SpecialtySelectorWidget> {
  final Set<String> _selectedInterests = {};
  bool _hasInitialized = false;
  static const int maxInterests = 10;

  @override
  void initState() {
    super.initState();
    
    // Inicializa com valores do ViewModel se existirem (separados por vírgula)
    if (widget.initialSpecialty.isNotEmpty && !_hasInitialized) {
      final interests = widget.initialSpecialty.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
      _selectedInterests.addAll(interests);
      _hasInitialized = true;
    }
  }

  void _toggleInterest(String interestId) {
    setState(() {
      if (_selectedInterests.contains(interestId)) {
        // Remove se já selecionado
        _selectedInterests.remove(interestId);
      } else {
        // Adiciona apenas se não atingiu o limite
        if (_selectedInterests.length < maxInterests) {
          _selectedInterests.add(interestId);
        }
      }
    });
    
    // Notifica mudança com lista separada por vírgulas
    final interestsString = _selectedInterests.join(',');
    widget.onSpecialtyChanged(interestsString.isNotEmpty ? interestsString : null);
  }

  Widget _buildCategorySection(BuildContext context, String category) {
    final i18n = AppLocalizations.of(context);
    final categoryTags = getInterestsByCategory(category);
    
    if (categoryTags.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título da categoria
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Text(
            i18n.translate('category_$category'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        
        // Tags da categoria
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: categoryTags.map((tag) {
            final isSelected = _selectedInterests.contains(tag.id);
            final isDisabled = !isSelected && _selectedInterests.length >= maxInterests;
            final displayLabel = '${tag.icon} ${i18n.translate(tag.nameKey)}';
            
            return Opacity(
              opacity: isDisabled ? 0.4 : 1.0,
              child: TagVendor(
                label: displayLabel,
                value: tag.id,
                isSelected: isSelected,
                onTap: isDisabled ? null : () => _toggleInterest(tag.id),
              ),
            );
          }).toList(),
        ),
        
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = maxInterests - _selectedInterests.length;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Contador de selecionados
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: _selectedInterests.isEmpty 
                ? GlimpseColors.lightTextField 
                : GlimpseColors.primaryLight.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _selectedInterests.isEmpty 
                  ? Colors.transparent 
                  : GlimpseColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedInterests.isEmpty
                      ? 'Escolha até $maxInterests interesses'
                      : remaining > 0
                          ? 'Escolha mais $remaining interesses'
                          : 'Máximo de $maxInterests interesses selecionados',
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _selectedInterests.length >= maxInterests
                        ? GlimpseColors.primary
                        : GlimpseColors.textSubTitle,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Lista de interesses
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Seções por categoria
                _buildCategorySection(context, InterestCategory.food),
                _buildCategorySection(context, InterestCategory.nightlife),
                _buildCategorySection(context, InterestCategory.culture),
                _buildCategorySection(context, InterestCategory.outdoor),
                _buildCategorySection(context, InterestCategory.sports),
                _buildCategorySection(context, InterestCategory.work),
                _buildCategorySection(context, InterestCategory.wellness),
                _buildCategorySection(context, InterestCategory.values),
                
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
