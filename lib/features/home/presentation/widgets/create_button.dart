import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Botão flutuante para criar novas atividades
class CreateButton extends StatelessWidget {
  const CreateButton({
    required this.onPressed,
    this.heroTag,
    super.key,
  });

  final VoidCallback onPressed;
  
  /// Hero tag customizável para evitar conflitos quando múltiplos CreateButtons
  /// existem em diferentes telas na mesma árvore de navegação.
  /// Se não fornecido, usa um UniqueKey para garantir unicidade.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FloatingActionButton(
        heroTag: heroTag ?? UniqueKey(),
        onPressed: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        backgroundColor: GlimpseColors.primary,
        elevation: 0, // Elevation handled by Container shadow
        shape: const CircleBorder(),
        child: const Icon(
          Icons.add,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}
