import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/features/home/presentation/services/map_navigation_service.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/subscription/services/vip_access_service.dart';

/// Helper para navegação baseada em notificações
/// 
/// SIMPLIFICADO: Remove lógica específica de casamento/VIP/aplicações
/// Mantém apenas message, alert, custom e activity types
class AppNotifications {
  /// Handle notification click for push and database notifications
  Future<void> onNotificationClick(
    BuildContext context, {
    required String nType,
    required String nSenderId,
    String? nRelatedId,
    String? deepLink,
    String? screen,
  }) async {
    debugPrint('🔔 [AppNotifications] Handling click: type=$nType, relatedId=$nRelatedId');
    
    /// Control notification type
    switch (nType) {
      case NOTIF_TYPE_MESSAGE:
      case 'new_message':
        // Navigate to conversations tab
        if (context.mounted) {
          _goToConversationsTab(context);
        }
      
      case 'alert':
        // Alertas não precisam de ação específica aqui
        // A mensagem já foi processada e exibida via NotificationMessageTranslator
        break;
      
      case 'custom':
        // Para notificações customizadas, pode-se processar deepLink ou screen
        if (deepLink != null && deepLink.isNotEmpty) {
          _handleDeepLink(context, deepLink);
        } else if (screen != null && screen.isNotEmpty) {
          _handleScreenNavigation(context, screen);
        }
        break;
      
      // Notificação de visitas ao perfil
      case 'profile_views_aggregated':
        if (context.mounted) {
          // 🔒 Check VIP antes de navegar (UX apenas - Rules validam no Firestore)
          final hasAccess = await VipAccessService.checkAccessOrShowDialog(
            context,
            source: 'profile_views_notification',
          );
          if (hasAccess && context.mounted) {
            context.push(AppRoutes.profileVisits);
          }
        }
        break;
      
      // Notificações de atividades/eventos
      case ActivityNotificationTypes.activityCreated:
      case ActivityNotificationTypes.activityJoinRequest:
      case ActivityNotificationTypes.activityJoinApproved:
      case ActivityNotificationTypes.activityJoinRejected:
      case ActivityNotificationTypes.activityNewParticipant:
      case ActivityNotificationTypes.activityHeatingUp:
      case ActivityNotificationTypes.activityExpiringSoon:
      case ActivityNotificationTypes.activityCanceled:
      case 'event_chat_message': // Mensagens de chat de evento
        if (nRelatedId != null && nRelatedId.isNotEmpty) {
          await _handleActivityNotification(context, nRelatedId);
        }
        break;
      
      default:
        debugPrint('⚠️ [AppNotifications] Tipo de notificação desconhecido: $nType');
        break;
    }
  }

  /// Trata notificações relacionadas a atividades/eventos
  /// 
  /// Usa o MapNavigationService singleton para:
  /// 1. Registrar navegação pendente
  /// 2. Navegar para a aba do mapa (Discover)
  /// 3. Quando o mapa estiver pronto, executar navegação automaticamente
  Future<void> _handleActivityNotification(
    BuildContext context,
    String eventId,
  ) async {
    debugPrint('🗺️ [AppNotifications] Opening activity: $eventId');
    
    if (!context.mounted) return;
    
    // 1. Registrar navegação pendente no singleton ANTES de navegar
    MapNavigationService.instance.navigateToEvent(eventId);
    
    // 2. Agendar navegação para o próximo frame para evitar Navigator lock
    // Isso garante que a navegação aconteça quando o Navigator estiver disponível
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        context.go(AppRoutes.home);
      }
    });
    
    // NOTA: O GoogleMapView vai registrar o handler quando estiver pronto
    // e executar a navegação automaticamente (mover câmera + abrir card)
  }

  /// Navigate to conversations tab
  /// 
  /// NOTA: Ajuste o índice conforme a estrutura da sua HomeScreen
  void _goToConversationsTab(BuildContext context) {
    // TODO: Ajustar navegação conforme estrutura do Partiu
    // Exemplo: NavigationService.instance.pushAndRemoveAll(HomeScreen(initialIndex: 2));
    
    // Por enquanto, apenas navega de volta
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Handle deepLink navigation
  void _handleDeepLink(BuildContext context, String deepLink) {
    // Parse deep link e navegar
    // Exemplo: app://profile/userId -> ProfileScreen
    // Exemplo: app://event/eventId -> EventScreen
    
    // TODO: Implementar lógica de deep linking conforme necessário
  }

  /// Handle screen navigation by name
  void _handleScreenNavigation(BuildContext context, String screenName) {
    // Navegar para tela específica
    // TODO: Implementar conforme rotas do app
  }
}
