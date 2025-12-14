import 'package:flutter/material.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';

/// Handler externo para ações do EventCard
/// 
/// Centraliza toda lógica de UI/fluxo, mantendo o widget limpo
class EventCardHandler {
  EventCardHandler._();

  /// Lida com o press do botão baseado no estado atual
  static Future<void> handleButtonPress({
    required BuildContext context,
    required EventCardController controller,
    required VoidCallback onActionSuccess,
  }) async {
    debugPrint('🔘 EventCardHandler.handleButtonPress iniciado');
    
    // Se é o criador, mostrar lista de participantes
    if (controller.isCreator) {
      debugPrint('✅ Usuário é criador, chamando onActionSuccess');
      onActionSuccess();
      return;
    }

    // Se já foi aprovado, entrar no chat
    if (controller.isApproved) {
      debugPrint('✅ Usuário aprovado, entrando no chat');
      onActionSuccess();
      return;
    }

    // Se ainda não aplicou, aplicar agora
    if (!controller.hasApplied) {
      debugPrint('🔄 Aplicando para o evento...');
      try {
        await controller.applyToEvent();
        debugPrint('✅ Aplicação realizada com sucesso!');
        
        // Se foi auto-aprovado (evento aberto), entrar no chat
        if (controller.isApproved) {
          debugPrint('✅ Auto-aprovado, entrando no chat');
          onActionSuccess();
        } else {
          debugPrint('⏳ Aplicação pendente de aprovação');
        }
      } catch (e) {
        debugPrint('❌ Erro ao aplicar: $e');
        if (context.mounted) {
          final i18n = AppLocalizations.of(context);
          ToastService.showError(
            message: i18n.translate('error_applying_to_event'),
          );
        }
      }
    } else {
      debugPrint('⚠️ Usuário já aplicou anteriormente');
    }
  }

  /// Lida com a deleção do evento (apenas para owner)
  static Future<void> handleDeleteEvent({
    required BuildContext context,
    required EventCardController controller,
  }) async {
    debugPrint('🗑️ EventCardHandler.handleDeleteEvent iniciado');
    debugPrint('📋 EventId: ${controller.eventId}');
    debugPrint('👤 Is Creator: ${controller.isCreator}');
    debugPrint('🔄 Is Deleting: ${controller.isDeleting}');
    
    final i18n = AppLocalizations.of(context);
    final eventName = controller.activityText ?? i18n.translate('this_event');
    
    debugPrint('📝 Event Name: $eventName');
    
    // Mostrar dialog de confirmação Cupertino
    final confirmed = await GlimpseCupertinoDialog.showDestructive(
      context: context,
      title: i18n.translate('delete_event'),
      message: i18n.translate('delete_event_confirmation')
          .replaceAll('{event}', eventName),
      destructiveText: i18n.translate('delete'),
      cancelText: i18n.translate('cancel'),
    );
    
    debugPrint('❓ User confirmed deletion: $confirmed');
    
    if (confirmed != true) {
      debugPrint('❌ Deletion cancelled by user');
      return;
    }
    
    debugPrint('✅ User confirmed, proceeding with deletion...');
    
    try {
      debugPrint('🔄 Calling controller.deleteEvent()...');
      await controller.deleteEvent();
      
      debugPrint('✅ Delete method completed successfully');
      
      if (!context.mounted) {
        debugPrint('⚠️ Context not mounted after deletion');
        return;
      }
      
      ToastService.showSuccess(
        message: i18n.translate('event_deleted_successfully') ?? 'Evento deletado com sucesso',
      );
      
      debugPrint('🚪 Closing event card...');
      // Fechar o card após deletar
      Navigator.of(context).pop();
      debugPrint('✅ Event card closed');
    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao deletar evento: $e');
      debugPrint('📚 StackTrace: $stackTrace');
      
      if (!context.mounted) return;
      
      ToastService.showError(
        message: i18n.translate('failed_to_delete_event') ?? 'Erro ao deletar evento',
      );
    }
  }

  /// Lida com a saída do evento
  static Future<void> handleLeaveEvent({
    required BuildContext context,
    required EventCardController controller,
  }) async {
    debugPrint('🚪 EventCardHandler.handleLeaveEvent iniciado');
    debugPrint('📋 EventId: ${controller.eventId}');
    debugPrint('👤 Has Applied: ${controller.hasApplied}');
    debugPrint('👤 Is Approved: ${controller.isApproved}');
    debugPrint('🔄 Is Leaving: ${controller.isLeaving}');
    
    final i18n = AppLocalizations.of(context);
    final eventName = controller.activityText ?? i18n.translate('this_event');
    
    debugPrint('📝 Event Name: $eventName');
    
    // Mostrar dialog de confirmação Cupertino
    final confirmed = await GlimpseCupertinoDialog.show(
      context: context,
      title: i18n.translate('leave_event'),
      message: i18n.translate('leave_event_confirmation')
          .replaceAll('{event}', eventName),
      confirmText: i18n.translate('leave'),
      cancelText: i18n.translate('cancel'),
    );
    
    debugPrint('❓ User confirmed leave: $confirmed');
    
    if (confirmed != true) {
      debugPrint('❌ Leave cancelled by user');
      return;
    }
    
    debugPrint('✅ User confirmed, proceeding with leave...');
    
    try {
      debugPrint('🔄 Calling controller.leaveEvent()...');
      await controller.leaveEvent();
      
      debugPrint('✅ Leave method completed successfully');
      
      if (!context.mounted) {
        debugPrint('⚠️ Context not mounted after leaving');
        return;
      }
      
      ToastService.showSuccess(
        message: i18n.translate('left_event_successfully')?.replaceAll('{event}', eventName) ?? 'Você saiu do evento',
      );
      
      debugPrint('🚪 Closing event card...');
      // Fechar o card após sair
      Navigator.of(context).pop();
      debugPrint('✅ Event card closed');
    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao sair do evento: $e');
      debugPrint('📚 StackTrace: $stackTrace');
      
      if (!context.mounted) return;
      
      ToastService.showError(
        message: i18n.translate('failed_to_leave_event') ?? 'Erro ao sair do evento',
      );
    }
  }
}
