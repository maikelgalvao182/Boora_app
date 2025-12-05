import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/dialogs/dialog_styles.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';

/// Widget burro que exibe botões de ação do evento
/// 
/// Decide qual layout usar baseado no estado (aprovado vs não aprovado)
class EventActionButtons extends StatelessWidget {
  const EventActionButtons({
    required this.isApproved,
    required this.isCreator,
    required this.isEnabled,
    required this.buttonText,
    required this.chatButtonText,
    required this.leaveButtonText,
    required this.deleteButtonText,
    required this.onChatPressed,
    required this.onLeavePressed,
    required this.onDeletePressed,
    required this.onSingleButtonPressed,
    super.key,
  });

  final bool isApproved;
  final bool isCreator;
  final bool isEnabled;
  final String buttonText;
  final String chatButtonText;
  final String leaveButtonText;
  final String deleteButtonText;
  final VoidCallback onChatPressed;
  final VoidCallback onLeavePressed;
  final VoidCallback onDeletePressed;
  final VoidCallback onSingleButtonPressed;

  @override
  Widget build(BuildContext context) {
    // Debug: verificar valores
    debugPrint('🔘 EventActionButtons.build()');
    debugPrint('   chatButtonText: "$chatButtonText"');
    debugPrint('   leaveButtonText: "$leaveButtonText"');
    debugPrint('   deleteButtonText: "$deleteButtonText"');
    debugPrint('   isApproved: $isApproved, isCreator: $isCreator');
    
    // Dois botões: Chat e Deletar (quando é criador aprovado)
    if (isApproved && isCreator) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onChatPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlimpseColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  elevation: 0,
                ),
                icon: const Icon(Iconsax.message, size: 20),
                label: Text(
                  chatButtonText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlimpseButton(
              text: deleteButtonText,
              icon: Iconsax.trash,
              backgroundColor: Colors.red,
              textColor: Colors.white,
              onPressed: onDeletePressed,
              noPadding: true,
              fontSize: 14,
            ),
          ),
        ],
      );
    }
    
    // Dois botões: Chat e Sair (quando aprovado e não é criador)
    if (isApproved && !isCreator) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onChatPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlimpseColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  elevation: 0,
                ),
                icon: const Icon(Iconsax.message, size: 20),
                label: Text(
                  chatButtonText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlimpseButton(
              text: leaveButtonText,
              icon: Iconsax.logout_1,
              backgroundColor: Colors.red,
              textColor: Colors.white,
              onPressed: onLeavePressed,
              noPadding: true,
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    // Botão único (outros casos)
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isEnabled ? onSingleButtonPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: GlimpseColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: GlimpseColors.disabledButtonColorLight,
          disabledForegroundColor: GlimpseColors.textHint,
          shape: RoundedRectangleBorder(
            borderRadius: DialogStyles.buttonBorderRadius,
          ),
          padding: DialogStyles.buttonPadding,
          elevation: 0,
        ),
        child: Text(
          buttonText,
          style: DialogStyles.buttonTextStyle.copyWith(
            color: isEnabled ? Colors.white : GlimpseColors.textHint,
          ),
        ),
      ),
    );
  }
}
