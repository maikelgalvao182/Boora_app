import 'package:flutter/material.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/dialogs/common_dialogs.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/screens/chat/services/event_deletion_service.dart';
import 'package:partiu/shared/services/toast_service.dart';

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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao aplicar: $e'),
              backgroundColor: Colors.red,
            ),
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
    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);
    final deletionService = EventDeletionService();
    
    // Chama o serviço de deleção que já tem toda a lógica
    await deletionService.handleDeleteEvent(
      context: context,
      eventId: controller.eventId,
      i18n: i18n,
      progressDialog: progressDialog,
      onSuccess: () {
        // Fechar o card após deletar
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  /// Lida com a saída do evento
  static Future<void> handleLeaveEvent({
    required BuildContext context,
    required EventCardController controller,
  }) async {
    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);
    
    final eventName = controller.activityText ?? i18n.translate('this_event');
    
    // Mostrar dialog de confirmação
    confirmDialog(
      context,
      title: i18n.translate('leave_event'),
      message: i18n.translate('leave_event_confirmation')
          .replaceAll('{event}', eventName),
      positiveText: i18n.translate('leave'),
      negativeAction: () => Navigator.of(context).pop(),
      positiveAction: () async {
        Navigator.of(context).pop();
        progressDialog.show(i18n.translate('leaving_event'));
        
        try {
          await controller.leaveEvent();
          await progressDialog.hide();
          
          if (!context.mounted) return;
          
          ToastService.showSuccess(
            context: context,
            title: i18n.translate('left_event'),
            subtitle: i18n.translate('left_event_successfully')
                .replaceAll('{event}', eventName),
          );
          
          // Fechar o card
          Navigator.of(context).pop();
        } catch (e) {
          await progressDialog.hide();
          
          if (!context.mounted) return;
          
          ToastService.showError(
            context: context,
            title: i18n.translate('error'),
            subtitle: i18n.translate('failed_to_leave_event'),
          );
        }
      },
    );
  }
}
