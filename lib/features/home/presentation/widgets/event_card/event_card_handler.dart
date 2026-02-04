import 'package:flutter/material.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/dialogs/vip_dialog.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';
import 'package:partiu/shared/widgets/confetti_celebration.dart';

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
    
    // 💎 NOVO: Se está fora da área e não é VIP, abrir VipDialog
    if (controller.isOutsideAreaNonVip) {
      debugPrint('💎 [EventCardHandler] Fora da área + não-VIP: abrindo VipDialog');
      final result = await VipBottomSheet.show(context);
      
      // Se comprou VIP (dialog retorna true), verificar novamente e permitir entrada
      if (result == true && context.mounted) {
        debugPrint('✅ [EventCardHandler] Usuário comprou VIP, verificando status...');
        // Aguarda um momento para VIP status ser atualizado
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Se agora é VIP, permitir aplicar
        if (controller.isUserVip) {
          debugPrint('✅ [EventCardHandler] VIP confirmado, aplicando ao evento');
          // Aplicar normalmente (fluxo padrão abaixo)
          if (!controller.hasApplied) {
            await _applyToEvent(context, controller, onActionSuccess);
          }
        }
      }
      return;
    }
    
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
      await _applyToEvent(context, controller, onActionSuccess);
    } else {
      debugPrint('⚠️ Usuário já aplicou anteriormente');
    }
  }
  
  /// Extrai lógica de aplicação para reutilizar após compra VIP
  static Future<void> _applyToEvent(
    BuildContext context,
    EventCardController controller,
    VoidCallback onActionSuccess,
  ) async {
    debugPrint('🔄 Aplicando para o evento...');
      
      // 🎯 Verificar se é evento open (será auto-aprovado)
      final isOpenEvent = controller.privacyType == 'open';
      final i18n = AppLocalizations.of(context);
      
      // 🎉 Disparar confetti E dialog SIMULTANEAMENTE para evento open
      // Isso evita race condition - ambos aparecem instantaneamente
      if (isOpenEvent && context.mounted) {
        debugPrint('🎊 Evento OPEN: Disparando confetti + dialog instantaneamente');
        
        // Confetti imediato
        ConfettiOverlay.show(context);
        
        // Dialog imediato (não espera applyToEvent)
        // ignore: unawaited_futures
        GlimpseCupertinoDialog.show(
          context: context,
          title: i18n.translate('success'),
          message: i18n.translate('application_approved_redirect_to_chat'),
          confirmText: i18n.translate('go_to_chat'),
          cancelText: i18n.translate('later'),
        ).then((confirmed) {
          if (confirmed == true) {
            debugPrint('✅ Usuário confirmou, entrando no chat');
            onActionSuccess();
          } else {
            debugPrint('⏸️ Usuário optou por entrar depois');
          }
        });
        
        // Aplicar em background (fire-and-forget para não bloquear UI)
        controller.applyToEvent().catchError((e) {
          debugPrint('❌ Erro ao aplicar (background): $e');
          if (context.mounted) {
            ToastService.showError(
              message: i18n.translate('error_applying_to_event'),
            );
          }
        });
        
      } else if (context.mounted) {
        // Evento fechado - precisa aguardar aprovação
        debugPrint('🔒 Evento FECHADO: Disparando confetti, aplicação pendente');
        
        // Confetti imediato
        ConfettiOverlay.show(context);
        
        try {
          await controller.applyToEvent();
          debugPrint('✅ Aplicação realizada com sucesso (pendente aprovação)');
        } catch (e) {
          debugPrint('❌ Erro ao aplicar: $e');
          if (context.mounted) {
            ToastService.showError(
              message: i18n.translate('error_applying_to_event'),
            );
          }
        }
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
        message: i18n.translate('event_deleted_successfully'),
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
        message: i18n.translate('failed_to_delete_event'),
      );
    }
  }

  /// Lida com a saída do evento
  /// 
  /// NOTA: Este método só deve ser chamado para participantes (não criadores).
  /// O criador tem botão "Delete" ao invés de "Leave" no EventCard.
  static Future<void> handleLeaveEvent({
    required BuildContext context,
    required EventCardController controller,
  }) async {
    debugPrint('🚪 EventCardHandler.handleLeaveEvent iniciado');
    debugPrint('📋 EventId: ${controller.eventId}');
    debugPrint('👤 Has Applied: ${controller.hasApplied}');
    debugPrint('👤 Is Approved: ${controller.isApproved}');
    debugPrint('👤 Is Creator: ${controller.isCreator}');
    debugPrint('🔄 Is Leaving: ${controller.isLeaving}');
    
    // Segurança: se for o criador, redirecionar para deletar
    if (controller.isCreator) {
      debugPrint('⚠️ Criador tentando sair - redirecionando para delete');
      await handleDeleteEvent(context: context, controller: controller);
      return;
    }
    
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
        message: i18n.translate('left_event_successfully').replaceAll('{event}', eventName),
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
        message: i18n.translate('failed_to_leave_event'),
      );
    }
  }
}