import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/features/home/presentation/services/map_navigation_service.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/subscription/services/vip_access_service.dart';
import 'package:partiu/screens/chat/chat_screen_refactored.dart';
import 'package:partiu/core/models/user.dart' as app_models;

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
  break;

      // Mensagem do chat de evento (push)
      case 'event_chat_message':
        if (nRelatedId != null && nRelatedId.isNotEmpty) {
          await _handleEventChatNotification(context, nRelatedId);
        } else {
          debugPrint('⚠️ [AppNotifications] event_chat_message sem relatedId');
        }
        break;
      
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
        await _handleChatNotification(context, chatUserId);
        break;
      
      // Event Chat: partiu://event-chat/{eventId}
      case String p when p.startsWith('event-chat/'):
        final eventId = p.replaceFirst('event-chat/', '');
        debugPrint('💬 [AppNotifications] Opening event chat: $eventId');
        await _handleEventChatNotification(context, eventId);
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

  /// Handle chat 1x1 navigation
  /// 
  /// Navega diretamente para o ChatScreenRefactored sem depender de Providers
  /// 
  /// NOTA: Usa rootNavigatorKey para garantir acesso ao Navigator global.
  Future<void> _handleChatNotification(BuildContext context, String otherUserId) async {
    debugPrint('💬 [AppNotifications] _handleChatNotification iniciado para: $otherUserId');
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        debugPrint('❌ [AppNotifications] User not logged in');
        return;
      }
      debugPrint('✅ [AppNotifications] currentUserId: $currentUserId');

      // Buscar conversa do Firestore para obter dados do usuário
      debugPrint('🔍 [AppNotifications] Buscando conversa em Connections/$currentUserId/Conversations/$otherUserId');
      final conversationDoc = await FirebaseFirestore.instance
          .collection('Connections')
          .doc(currentUserId)
          .collection('Conversations')
          .doc(otherUserId)
          .get();

      if (!conversationDoc.exists) {
        debugPrint('❌ [AppNotifications] Conversation not found for user: $otherUserId');
        debugPrint('   - Path: Connections/$currentUserId/Conversations/$otherUserId');
        return;
      }
      
      final data = conversationDoc.data() ?? {};
      debugPrint('✅ [AppNotifications] Conversa encontrada, dados: ${data.keys}');

      // Criar objeto User a partir dos dados da conversa
      final user = _createUserFromData(data, otherUserId);

      // Navegar diretamente usando rootNavigatorKey (não precisa agendar)
      debugPrint('🚀 [AppNotifications] Navegando para ChatScreenRefactored...');
      _navigateToChat(context, user, currentUserId, otherUserId);
    } catch (e, stack) {
      debugPrint('❌ [AppNotifications] Error opening chat: $e');
      debugPrint('   Stack: $stack');
    }
  }
  
  /// Navega para o chat 1-1 usando o rootNavigatorKey global
  void _navigateToChat(
    BuildContext context,
    app_models.User user,
    String currentUserId,
    String otherUserId,
  ) {
    try {
      // Usar rootNavigatorKey para garantir acesso ao Navigator
      final navigator = rootNavigatorKey.currentState;
      
      if (navigator != null) {
        debugPrint('✅ [AppNotifications] rootNavigator encontrado, navegando...');
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ChatScreenRefactored(
              user: user,
              isEvent: false,
              eventId: null,
            ),
          ),
        );
        debugPrint('✅ [AppNotifications] Navegação para chat completada');
        
        // Marcar como lido em background
        _markAsReadInBackground(currentUserId, otherUserId);
      } else {
        // Fallback: Tentar com context.mounted
        debugPrint('⚠️ [AppNotifications] rootNavigator null, tentando com context...');
        if (context.mounted) {
          final contextNavigator = Navigator.maybeOf(context);
          if (contextNavigator != null) {
            contextNavigator.push(
              MaterialPageRoute(
                builder: (_) => ChatScreenRefactored(
                  user: user,
                  isEvent: false,
                  eventId: null,
                ),
              ),
            );
            _markAsReadInBackground(currentUserId, otherUserId);
          } else {
            _goToConversationsTab(context);
          }
        }
      }
    } catch (e, stack) {
      debugPrint('❌ [AppNotifications] Error in _navigateToChat: $e');
      debugPrint('   Stack: $stack');
      
      // Fallback de emergência
      try {
        if (context.mounted) _goToConversationsTab(context);
      } catch (_) {}
    }
  }

  /// Handle event chat navigation
  /// 
  /// Navega diretamente para o ChatScreenRefactored sem depender de Providers
  /// 
  /// NOTA: Usa SchedulerBinding para garantir que a navegação aconteça
  /// após o frame atual, quando o Navigator estiver disponível.
  Future<void> _handleEventChatNotification(BuildContext context, String eventId) async {
    debugPrint('💬 [AppNotifications] _handleEventChatNotification iniciado para: $eventId');
    try {
      if (!context.mounted) {
        debugPrint('❌ [AppNotifications] Context not mounted!');
        return;
      }

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        debugPrint('❌ [AppNotifications] User not logged in');
        return;
      }
      debugPrint('✅ [AppNotifications] currentUserId: $currentUserId');

      // Buscar conversa do evento do Firestore
      final conversationId = 'event_$eventId';
      debugPrint('🔍 [AppNotifications] Buscando conversa em Connections/$currentUserId/Conversations/$conversationId');
      final conversationDoc = await FirebaseFirestore.instance
          .collection('Connections')
          .doc(currentUserId)
          .collection('Conversations')
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        debugPrint('❌ [AppNotifications] Event conversation not found: $eventId');
        debugPrint('   - Path: Connections/$currentUserId/Conversations/$conversationId');
        return;
      }

      final data = conversationDoc.data() ?? {};
      debugPrint('✅ [AppNotifications] Event conversa encontrada, dados: ${data.keys}');

      // Criar objeto User a partir dos dados da conversa (usa fullname do evento como nome)
      final user = _createUserFromData(data, conversationId);

      // Navegar diretamente usando rootNavigatorKey (não precisa agendar)
      debugPrint('🚀 [AppNotifications] Navegando para ChatScreenRefactored (event chat)...');
      _navigateToEventChat(context, user, eventId, currentUserId, conversationId);
    } catch (e, stack) {
      debugPrint('❌ [AppNotifications] Error opening event chat: $e');
      debugPrint('   Stack: $stack');
    }
  }
  
  /// Navega para o chat do evento usando rootNavigatorKey global
  void _navigateToEventChat(
    BuildContext context,
    app_models.User user,
    String eventId,
    String currentUserId,
    String conversationId,
  ) {
    try {
      // Usar rootNavigatorKey para garantir acesso ao Navigator
      final navigator = rootNavigatorKey.currentState;
      
      if (navigator != null) {
        debugPrint('✅ [AppNotifications] rootNavigator encontrado, navegando...');
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ChatScreenRefactored(
              user: user,
              isEvent: true,
              eventId: eventId,
            ),
          ),
        );
        debugPrint('✅ [AppNotifications] Navegação para event chat completada');
        
        // Marcar como lido em background
        _markAsReadInBackground(currentUserId, conversationId);
      } else {
        // Fallback: Navegar para home e usar MapNavigationService
        debugPrint('⚠️ [AppNotifications] rootNavigator null, usando fallback via home...');
        
        // Registrar navegação pendente para abrir o EventCard
        MapNavigationService.instance.navigateToEvent(eventId);
        
        // Navegar para home onde o mapa vai processar a navegação pendente
        if (context.mounted) {
          context.go(AppRoutes.home);
        }
      }
    } catch (e, stack) {
      debugPrint('❌ [AppNotifications] Error in _navigateToEventChat: $e');
      debugPrint('   Stack: $stack');
      
      // Fallback de emergência
      try {
        MapNavigationService.instance.navigateToEvent(eventId);
        if (context.mounted) context.go(AppRoutes.home);
      } catch (_) {}
    }
  }

  /// Cria um objeto User a partir dos dados da conversa
  app_models.User _createUserFromData(Map<String, dynamic> data, String odString) {
    final rawName = data['fullName'] ?? data['fullname'] ?? data['full_name'] ?? data['name'] ?? '';
    final userName = (rawName is String) ? rawName.trim() : '';
    final rawPhoto = data['photoUrl'] ?? data['photo_url'] ?? data['avatarUrl'] ?? data['avatar_url'] ?? '';
    final userPhoto = (rawPhoto is String) ? rawPhoto : '';
    
    debugPrint('✅ [AppNotifications] User criado: name="$userName", photo="$userPhoto"');
    
    return app_models.User.fromDocument({
      'userId': odString,
      'fullName': userName,
      'photoUrl': userPhoto,
      'gender': '',
      'birthDay': 1,
      'birthMonth': 1,
      'birthYear': 2000,
      'jobTitle': '',
      'bio': '',
      'country': '',
      'locality': '',
      'latitude': 0.0,
      'longitude': 0.0,
      'status': 'active',
      'level': '',
      'isVerified': false,
      'registrationDate': DateTime.now().toIso8601String(),
      'lastLoginDate': DateTime.now().toIso8601String(),
      'totalLikes': 0,
      'totalVisits': 0,
      'isOnline': false,
    });
  }

  /// Marca a conversa como lida em background
  void _markAsReadInBackground(String currentUserId, String conversationId) {
    Future.microtask(() {
      try {
        FirebaseFirestore.instance
            .collection('Connections')
            .doc(currentUserId)
            .collection('Conversations')
            .doc(conversationId)
            .update({
          'message_read': true,
          'unread_count': 0,
        });
        debugPrint('✅ [AppNotifications] Marcado como lido: $conversationId');
      } catch (e) {
        debugPrint('⚠️ [AppNotifications] Erro ao marcar como lido: $e');
      }
    });
  }

  /// Handle screen navigation by name
  void _handleScreenNavigation(BuildContext context, String screenName) {
    // Navegar para tela específica
    // TODO: Implementar conforme rotas do app
  }
}
