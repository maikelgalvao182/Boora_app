import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/reviews/presentation/dialogs/review_dialog_controller.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';
import 'package:provider/provider.dart';

/// Header do ReviewDialog com handle, botão voltar, título e botão fechar
/// 
/// Componente reutilizável que encapsula toda a lógica de navegação
/// e apresentação do cabeçalho do modal de review.
class ReviewDialogHeader extends StatelessWidget {
  final VoidCallback onClose;

  const ReviewDialogHeader({
    required this.onClose,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.read<ReviewDialogController>();

    return Padding(
      padding: const EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: GlimpseColors.borderColorLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Header: Back + Título + Close
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Botão voltar
              Selector<ReviewDialogController, bool>(
                selector: (_, c) => c.canGoBack,
                builder: (_, canGoBack, __) {
                  if (canGoBack) {
                    return GlimpseBackButton(
                      onTap: controller.previousStep,
                    );
                  }
                  return const SizedBox(width: 32);
                },
              ),

              // Título centralizado
              Expanded(
                child: Selector<ReviewDialogController, String>(
                  selector: (_, c) => c.currentStepLabel,
                  builder: (_, label, __) {
                    return Text(
                      label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w800,
                        color: GlimpseColors.primaryColorLight,
                      ),
                    );
                  },
                ),
              ),

              // Botão fechar
              GlimpseCloseButton(
                size: 32,
                onPressed: onClose,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
