import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/animated_expandable.dart';

/// Widget de seleção de número de pessoas para a atividade
/// Card horizontal que expande para mostrar o picker (Aberto ou 1-20)
class PeoplePicker extends StatelessWidget {
  const PeoplePicker({
    required this.isExpanded,
    required this.selectedCount,
    required this.onToggle,
    required this.onCountChanged,
    super.key,
  });

  final bool isExpanded;
  final int selectedCount; // 0 = Aberto, 1-20 = específico
  final VoidCallback onToggle;
  final ValueChanged<int> onCountChanged;

  String get _displayText {
    if (selectedCount == 0) return 'Aberto';
    return '$selectedCount ${selectedCount == 1 ? 'pessoa' : 'pessoas'}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Card horizontal
        GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: GlimpseColors.lightTextField,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Ícone
                Icon(
                  IconsaxPlusLinear.profile_2user,
                  color: (isExpanded || selectedCount > 0)
                      ? GlimpseColors.primary
                      : GlimpseColors.textSubTitle,
                  size: 24,
                ),

                const SizedBox(width: 16),

                // Título
                Expanded(
                  child: Text(
                    'Definir vagas',
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: GlimpseColors.primaryColorLight,
                    ),
                  ),
                ),

                // Valor selecionado (direita)
                Text(
                  _displayText,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: GlimpseColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Number Picker (aparece quando expandido)
        AnimatedExpandable(
          isExpanded: isExpanded,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: GlimpseColors.lightTextField,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                    initialItem: selectedCount,
                  ),
                  itemExtent: 40,
                  onSelectedItemChanged: (index) {
                    onCountChanged(index); // 0 = Aberto, 1-20 = específico
                  },
                  children: [
                    // Primeiro item: "Aberto"
                    Center(
                      child: Text(
                        'Aberto',
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: GlimpseColors.primaryColorLight,
                        ),
                      ),
                    ),
                    // Itens 1-20
                    ...List.generate(
                      20,
                      (index) => Center(
                        child: Text(
                          '${index + 1} ${index == 0 ? 'pessoa' : 'pessoas'}',
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: GlimpseColors.primaryColorLight,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
