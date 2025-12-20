import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/screens/chat/services/event_application_removal_service.dart';
import 'package:partiu/features/conversations/widgets/conversation_tile.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';

/// Widget que adiciona funcionalidade de swipe-to-delete nas conversas
/// 
/// **Comportamento:**
/// - Chat 1x1: Swipe deleta a conversa
/// - Chat de grupo/evento: Swipe sai do evento
/// 
/// **Recursos:**
/// - ✅ Swipe para esquerda revela botão de ação
/// - ✅ Dismiss animado ao deslizar completamente
/// - ✅ Feedback háptico ao abrir/fechar
/// - ✅ Dialog de confirmação antes da ação
class SwipeableConversationTile extends StatelessWidget {
  const SwipeableConversationTile({
    required this.conversationId,
    required this.rawData,
    required this.isVipEffective,
    required this.isLast,
    required this.onTap,
    required this.chatService,
    required this.onDeleted,
    super.key,
  });

  final String conversationId;
  final Map<String, dynamic> rawData;
  final bool isVipEffective;
  final bool isLast;
  final VoidCallback onTap;
  final ChatService chatService;
  final VoidCallback onDeleted;

  /// Verifica se é uma conversa de evento (grupo)
  bool get isEventChat {
    return rawData['is_event_chat'] == true || 
           (rawData['event_id']?.toString().isNotEmpty ?? false);
  }

  /// Obtém o eventId se for chat de evento
  String? get eventId {
    final id = rawData['event_id']?.toString();
    return (id != null && id.isNotEmpty) ? id : null;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    // Label e ícone dependem do tipo de conversa
    final actionLabel = isEventChat 
        ? i18n.translate('leave') 
        : i18n.translate('delete');
    
    final actionIcon = isEventChat 
        ? IconsaxPlusBold.logout 
        : IconsaxPlusBold.trash;

    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Slidable(
          key: ValueKey(conversationId),
          
          // Ação ao deslizar para esquerda
          endActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.25,
            dismissible: DismissiblePane(
              onDismissed: () {
                HapticFeedback.mediumImpact();
                _handleAction(context);
              },
              closeOnCancel: true,
            ),
            openThreshold: 0.2,
            closeThreshold: 0.6,
            children: [
              CustomSlidableAction(
                onPressed: (_) {
                  HapticFeedback.mediumImpact();
                  _handleAction(context);
                },
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      actionIcon,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      actionLabel,
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
          
          child: ConversationTile(
            conversationId: conversationId,
            rawData: rawData,
            isVipEffective: isVipEffective,
            isLast: isLast,
            onTap: onTap,
            chatService: chatService,
          ),
        ),
      ),
    );
  }

  /// Executa a ação apropriada baseado no tipo de conversa
  void _handleAction(BuildContext context) {
    if (isEventChat && eventId != null) {
      _handleLeaveEvent(context);
    } else {
      _handleDeleteConversation(context);
    }
  }

  /// Sai do evento (para chats de grupo)
  void _handleLeaveEvent(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);
    final removalService = EventApplicationRemovalService();

    removalService.handleLeaveEvent(
      context: context,
      eventId: eventId!,
      i18n: i18n,
      progressDialog: progressDialog,
      onSuccess: onDeleted,
    );
  }

  /// Deleta a conversa (para chats 1x1)
  Future<void> _handleDeleteConversation(BuildContext context) async {
    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);

    // Mostrar dialog de confirmação
    final confirmed = await GlimpseCupertinoDialog.showDestructive(
      context: context,
      title: i18n.translate('delete_conversation'),
      message: i18n.translate('are_you_sure_you_want_to_delete_conversation'),
      destructiveText: i18n.translate('delete'),
      cancelText: i18n.translate('cancel'),
    );

    if (confirmed != true || !context.mounted) return;

    // Mostrar loading
    progressDialog.show(i18n.translate('processing'));

    // Deletar conversa
    await chatService.deleteChat(conversationId);

    // Esconder loading
    await progressDialog.hide();

    // Callback de sucesso
    onDeleted();

    // Toast de sucesso
    ToastService.showSuccess(
      message: i18n.translate('conversation_deleted_successfully'),
    );
  }
}
