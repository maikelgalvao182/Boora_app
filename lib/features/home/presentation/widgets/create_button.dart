import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
    return Hero(
      tag: heroTag ?? UniqueKey(),
      child: Material(
        elevation: 8.r,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: const CircleBorder(),
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onPressed();
          },
          customBorder: const CircleBorder(),
          child: Container(
            width: 56.w,
            height: 56.h,
            decoration: const BoxDecoration(
              color: GlimpseColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                Icons.add,
                color: Colors.white,
                size: 28.sp,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
