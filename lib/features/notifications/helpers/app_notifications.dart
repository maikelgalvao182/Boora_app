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
    debugPrint('🔔 [AppNotifications] Handling click: type=$nType, relatedId=$nRelatedId, deepLink=$deepLink');
    
    // 🚀 PRIORIDADE: Se tem deepLink, usa ele diretamente
    if (deepLink != null && deepLink.isNotEmpty) {
      await _handleDeepLink(context, deepLink);
      return;
    }
    
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
  Future<void> _handleDeepLink(BuildContext context, String deepLink) async {
    debugPrint('🔗 [AppNotifications] Processing deepLink: $deepLink');
    
    // Parse deep link: partiu://path/to/screen?param=value
    final uri = Uri.tryParse(deepLink);
    if (uri == null) {
      debugPrint('⚠️ [AppNotifications] Invalid deepLink format');
      return;
    }
    
    final scheme = uri.scheme; // partiu
    final host = uri.host; // path (primeira parte)
    final path = uri.path; // /to/screen
    final queryParams = uri.queryParameters;
    
    // Combina host + path para rota completa
    final fullPath = host + path;
    debugPrint('🔗 [AppNotifications] scheme=$scheme, fullPath=$fullPath, params=$queryParams');
    
    if (!context.mounted) return;
    
    switch (fullPath) {
      // Chat 1-1: partiu://chat/{userId}
      case String p when p.startsWith('chat/'):
        final chatUserId = p.replaceFirst('chat/', '');
        debugPrint('💬 [AppNotifications] Opening chat with: $chatUserId');
        // TODO: Navegar para conversa específica
        _goToConversationsTab(context);
        break;
      
      // Event Chat: partiu://event-chat/{eventId}
      case String p when p.startsWith('event-chat/'):
        final eventId = p.replaceFirst('event-chat/', '');
        debugPrint('💬 [AppNotifications] Opening event chat: $eventId');
        await _handleActivityNotification(context, eventId);
        break;
      
      // Group Info: partiu://group-info/{eventId}?tab=requests
      case String p when p.startsWith('group-info/'):
        final eventId = p.replaceFirst('group-info/', '');
        final tab = queryParams['tab'];
        debugPrint('ℹ️ [AppNotifications] Opening group info: $eventId, tab=$tab');
        if (context.mounted) {
          context.push('${AppRoutes.groupInfo}/$eventId');
        }
        break;
      
      // Home com evento: partiu://home?event={eventId}
      case 'home':
        final eventId = queryParams['event'];
        final tab = queryParams['tab'];
        if (eventId != null && eventId.isNotEmpty) {
          debugPrint('🗺️ [AppNotifications] Opening home with event: $eventId');
          await _handleActivityNotification(context, eventId);
        } else if (tab != null) {
          debugPrint('🏠 [AppNotifications] Opening home tab: $tab');
          if (context.mounted) {
            context.go('${AppRoutes.home}?tab=$tab');
          }
        } else {
          if (context.mounted) {
            context.go(AppRoutes.home);
          }
        }
        break;
      
      // Profile Visits: partiu://profile-visits
      case 'profile-visits':
        debugPrint('👀 [AppNotifications] Opening profile visits');
        if (context.mounted) {
          // 🔒 Check VIP antes de navegar
          final hasAccess = await VipAccessService.checkAccessOrShowDialog(
            context,
            source: 'deeplink_profile_visits',
          );
          if (hasAccess && context.mounted) {
            context.push(AppRoutes.profileVisits);
          }
        }
        break;
      
      // Reviews: partiu://reviews/{userId}
      case String p when p.startsWith('reviews/'):
        final userId = p.replaceFirst('reviews/', '');
        debugPrint('⭐ [AppNotifications] Opening reviews for: $userId');
        // TODO: Navegar para tela de reviews quando implementada
        if (context.mounted) {
          context.go(AppRoutes.home);
        }
        break;
      
      // Activity/Event: partiu://activity/{activityId}
      case String p when p.startsWith('activity/'):
        final activityId = p.replaceFirst('activity/', '');
        debugPrint('🎯 [AppNotifications] Opening activity: $activityId');
        await _handleActivityNotification(context, activityId);
        break;
      
      // Profile: partiu://profile/{userId}
      case String p when p.startsWith('profile/'):
        final userId = p.replaceFirst('profile/', '');
        debugPrint('👤 [AppNotifications] Opening profile: $userId');
        // TODO: Implementar navegação para perfil
        if (context.mounted) {
          context.go(AppRoutes.home);
        }
        break;
      
      default:
        debugPrint('⚠️ [AppNotifications] Unknown deepLink path: $fullPath');
        break;
    }
  }

  /// Handle screen navigation by name
  void _handleScreenNavigation(BuildContext context, String screenName) {
    // Navegar para tela específica
    // TODO: Implementar conforme rotas do app
  }
}
