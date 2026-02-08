import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Botão de fechar padrão usado em modals e telas full-screen.
/// 
/// Fornece consistência visual em toda a aplicação para o botão de fechar/voltar.
/// Estilo baseado no DialogStyles para manter consistência visual.
class GlimpseCloseButton extends StatelessWidget {
  const GlimpseCloseButton({
    this.onPressed,
    this.color,
    this.size,
    super.key,
  });

  final VoidCallback? onPressed;
  final Color? color;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final effectiveSize = size ?? 32.w;
    return Container(
      width: effectiveSize,
      height: effectiveSize,
      decoration: BoxDecoration(
        color: GlimpseColors.lightTextField,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        splashRadius: 18,
        icon: Icon(
          Icons.close,
          size: 24.sp,
          color: color ?? Colors.black,
        ),
        onPressed: () {
          HapticFeedback.lightImpact();
          if (onPressed != null) {
            onPressed!();
          } else {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }
}
