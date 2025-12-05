import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/features/home/presentation/widgets/user_card.dart';

/// Widget compartilhável que adiciona funcionalidade de swipe-to-delete
/// 
/// Envolve qualquer widget (tipicamente UserCard) com flutter_slidable.
/// Mostra um card vermelho com ícone branco ao deslizar para esquerda.
/// 
/// **Recursos:**
/// - ✅ Swipe para esquerda revela botão de remover
/// - ✅ Long press também revela o botão
/// - ✅ Dismiss animado ao deslizar completamente
/// - ✅ Feedback háptico ao abrir/fechar
/// - ✅ Ícone do Iconsax
/// - ✅ Callback de delete customizável
/// 
/// **Uso básico:**
/// ```dart
/// SwipeableMemberCard(
///   userId: userId,
///   onDelete: () => _handleDelete(userId),
/// )
/// ```
/// 
/// **Uso avançado (widget customizado):**
/// ```dart
/// SwipeableMemberCard(
///   userId: userId,
///   deleteLabel: 'Remover',
///   onDelete: () => _handleDelete(userId),
///   child: CustomCard(userId: userId),
/// )
/// ```
class SwipeableMemberCard extends StatelessWidget {
  const SwipeableMemberCard({
    required this.userId,
    required this.onDelete,
    this.deleteLabel = 'Remover',
    this.child,
    this.onTap,
    super.key,
  });

  final String userId;
  final VoidCallback onDelete;
  final String deleteLabel;
  final Widget? child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Slidable(
        key: ValueKey(userId),
        
        // Ação ao deslizar para esquerda
        endActionPane: ActionPane(
          motion: const BehindMotion(), // Card desliza revelando ação por trás
          extentRatio: 0.30, // Largura da ação revelada
          dismissible: DismissiblePane(
            onDismissed: () {
              HapticFeedback.mediumImpact();
              onDelete();
            },
            closeOnCancel: true,
          ),
          openThreshold: 0.2, // Facilita abertura
          closeThreshold: 0.6, // Facilita fechamento
          children: [
            CustomSlidableAction(
              onPressed: (_) {
                HapticFeedback.mediumImpact();
                onDelete();
              },
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    IconsaxPlusBold.trash,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deleteLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        child: GestureDetector(
          onLongPress: () {
            // Feedback háptico ao segurar
            HapticFeedback.mediumImpact();
            
            // Abre o slidable programaticamente
            final slidableController = Slidable.of(context);
            slidableController?.openEndActionPane();
          },
          child: child ?? UserCard(
            userId: userId,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
