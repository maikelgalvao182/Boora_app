import 'package:flutter/cupertino.dart';
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
    this.isApplying = false,
    this.isLeaving = false,
    this.isDeleting = false,
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
  final bool isApplying;
  final bool isLeaving;
  final bool isDeleting;

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
                onPressed: () {
                  debugPrint('🔘 Chat button pressed (creator)');
                  onChatPressed();
                },
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
              onPressed: () {
                debugPrint('🗑️ Delete button pressed');
                onDeletePressed();
              },
              noPadding: true,
              height: 48,
              fontSize: 14,
              isProcessing: isDeleting,
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
                onPressed: () {
                  debugPrint('🔘 Chat button pressed (participant)');
                  onChatPressed();
                },
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
              iconSize: 18,
              backgroundColor: Colors.red,
              textColor: Colors.white,
              onPressed: () {
                debugPrint('🚪 Leave button pressed');
                onLeavePressed();
              },
              noPadding: true,
              height: 48,
              fontSize: 14,
              isProcessing: isLeaving,
            ),
          ),
        ],
      );
    }
    // Botão único (outros casos)
    return GlimpseButton(
      text: buttonText,
      onPressed: (isEnabled && !isApplying) ? onSingleButtonPressed : null,
      isProcessing: isApplying,
    );
  }
}
