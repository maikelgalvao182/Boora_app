import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/features/home/presentation/services/map_navigation_service.dart';
import 'package:partiu/features/home/presentation/coordinators/home_navigation_coordinator.dart';
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
      case 'chat_message':
        // ✅ Navigate to specific chat using senderId
        if (nSenderId.isNotEmpty && context.mounted) {
          debugPrint('💬 [AppNotifications] Navegando para chat com sender: $nSenderId');
          await _handleChatNotification(context, nSenderId);
        } else if (context.mounted) {
          debugPrint('⚠️ [AppNotifications] Sem senderId, indo para aba de conversas');
          _goToConversationsTab(context);
        }
        break;      // Mensagem do chat de evento (push)
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
      
      // Pedido de entrada -> Aba de Ações
      case ActivityNotificationTypes.activityJoinRequest:
        await _handleActionTabNotification(context);
        break;

      // Notificações de atividades/eventos
      case ActivityNotificationTypes.activityCreated:
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


  /// Navega para a aba de ações (Solicitações/Reviews)
  Future<void> _handleActionTabNotification(BuildContext context) async {
    debugPrint('📝 [AppNotifications] Opening actions tab');
    
    // Usar rootNavigatorKey para garantir navegação estável
    final navigator = rootNavigatorKey.currentState;
    
    if (navigator == null) {
      if (context.mounted) {
        context.go('${AppRoutes.home}?tab=1');
      }
      return;
    }
    
    // Fechar TODAS as rotas/modais até a raiz
    navigator.popUntil((route) => route.isFirst);
    
    await Future.delayed(const Duration(milliseconds: 100));
    
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final ctx = navigator.context;
      if (ctx.mounted) {
        ctx.go('${AppRoutes.home}?tab=1');
      }
    });
  }

  /// Trata notificações relacionadas a atividades/eventos
  /// 
  /// Usa o MapNavigationService singleton para:
  /// 1. Registrar navegação pendente
  /// 2. Fechar modais/sheets (limpeza)
  /// 3. Navegar para a aba do mapa via GoRouter
  Future<void> _handleActivityNotification(
    BuildContext context,
    String eventId,
  ) async {
    debugPrint('🗺️ [AppNotifications] Opening activity: $eventId');
    
    // Teste de isolamento de contexto e estado
    debugPrint('🧪 [TEST] rootCtx = ${rootNavigatorKey.currentContext}');
    debugPrint('🧪 [TEST] rootState = ${rootNavigatorKey.currentState}');
    
    // 2. Usar rootNavigatorKey para obter contexto estável
    final rootCtx = rootNavigatorKey.currentContext;
    
    if (rootCtx == null) {
      debugPrint('⚠️ [AppNotifications] rootNavigatorKey.currentContext é null. Usando fallback.');
      if (context.mounted) {
        // Fallback simples
        MapNavigationService.instance.navigateToEvent(eventId);
        context.go('${AppRoutes.home}?tab=0');
      }
      return;
    }
    
    // 3. Limpar modais/sheets (opcional, mas garante que não haja overlays sobre o mapa)
    // popUntil garante que voltamos à base (geralmente o ShellRoute)
    Navigator.of(rootCtx).popUntil((route) => route.isFirst);

    // 4. Delegar navegação para o HomeNavigationCoordinator (NOVO PADRÃO)
    // Isso garante que a aba seja trocada via Switcher (sem rebuild total)
    // e o evento seja enfileirado e consumido de forma robusta.
    debugPrint('🗺️ [AppNotifications] Delegando para HomeNavigationCoordinator: $eventId');
    HomeNavigationCoordinator.instance.openEventOnMap(eventId);
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
      // NOTA: Reviews são exibidas no perfil do usuário, então navegamos para lá
      case String p when p.startsWith('reviews/'):
        final userId = p.replaceFirst('reviews/', '');
        debugPrint('⭐ [AppNotifications] Opening reviews for: $userId');
        // Navega para o perfil do usuário onde as reviews são exibidas
        await _handleProfileNotification(context, userId);
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
        await _handleProfileNotification(context, userId);
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

      app_models.User user;
      
      if (conversationDoc.exists) {
        final data = conversationDoc.data() ?? {};
        debugPrint('✅ [AppNotifications] Conversa encontrada, dados: ${data.keys}');
        // Criar objeto User a partir dos dados da conversa
        user = _createUserFromData(data, otherUserId);
      } else {
        debugPrint('⚠️ [AppNotifications] Conversation not found, trying Users collection...');
        // Fallback: buscar diretamente na coleção Users
        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(otherUserId)
            .get();
        
        if (userDoc.exists) {
          final userData = userDoc.data() ?? {};
          debugPrint('✅ [AppNotifications] User encontrado em Users collection');
          user = _createUserFromData(userData, otherUserId);
        } else {
          debugPrint('⚠️ [AppNotifications] User não encontrado, criando user básico...');
          // Criar user básico apenas com ID (chat vai funcionar)
          user = _createUserFromData({}, otherUserId);
        }
      }

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
    String otherUserId, {
    int retryCount = 0,
  }) {
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
      } else if (retryCount < 3) {
        // Retry: Navigator ainda não está pronto (comum após cold start)
        debugPrint('⚠️ [AppNotifications] rootNavigator null, retry ${retryCount + 1}/3 em 300ms...');
        Future.delayed(const Duration(milliseconds: 300), () {
          _navigateToChat(context, user, currentUserId, otherUserId, retryCount: retryCount + 1);
        });
      } else {
        // Fallback: Tentar com context.mounted após retries
        debugPrint('⚠️ [AppNotifications] rootNavigator ainda null após retries, tentando com context...');
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
            debugPrint('❌ [AppNotifications] Nenhum navigator disponível, desistindo');
          }
        }
      }
    } catch (e, stack) {
      debugPrint('❌ [AppNotifications] Error in _navigateToChat: $e');
      debugPrint('   Stack: $stack');
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

      app_models.User user;
      
      if (conversationDoc.exists) {
        final data = conversationDoc.data() ?? {};
        debugPrint('✅ [AppNotifications] Event conversa encontrada, dados: ${data.keys}');
        // Criar objeto User a partir dos dados da conversa (usa fullname do evento como nome)
        user = _createUserFromData(data, conversationId);
      } else {
        debugPrint('⚠️ [AppNotifications] Event conversation not found, trying Events collection...');
        // Fallback: buscar dados do evento diretamente
        final eventDoc = await FirebaseFirestore.instance
            .collection('Events')
            .doc(eventId)
            .get();
        
        if (eventDoc.exists) {
          final eventData = eventDoc.data() ?? {};
          debugPrint('✅ [AppNotifications] Evento encontrado em Events collection');
          // Criar user com dados do evento
          user = _createUserFromData({
            'fullName': eventData['eventTitle'] ?? eventData['activityText'] ?? 'Evento',
            'photoUrl': eventData['eventPhoto'] ?? '',
          }, conversationId);
        } else {
          debugPrint('⚠️ [AppNotifications] Event não encontrado, criando user básico...');
          // Criar user básico apenas com ID (chat vai funcionar)
          user = _createUserFromData({'fullName': 'Evento'}, conversationId);
        }
      }

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
    String conversationId, {
    int retryCount = 0,
  }) {
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
      } else if (retryCount < 3) {
        // Retry: Navigator ainda não está pronto (comum após cold start)
        debugPrint('⚠️ [AppNotifications] rootNavigator null, retry ${retryCount + 1}/3 em 300ms...');
        Future.delayed(const Duration(milliseconds: 300), () {
          _navigateToEventChat(context, user, eventId, currentUserId, conversationId, retryCount: retryCount + 1);
        });
      } else {
        // Fallback: Navegar para home e usar MapNavigationService
        debugPrint('⚠️ [AppNotifications] rootNavigator ainda null após retries, usando fallback via home...');
        
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

  /// Handle profile navigation from notification
  /// 
  /// Navega para o perfil do usuário usando ProfileScreenRouter
  Future<void> _handleProfileNotification(BuildContext context, String userId) async {
    debugPrint('👤 [AppNotifications] _handleProfileNotification iniciado para: $userId');
    try {
      if (!context.mounted) {
        debugPrint('❌ [AppNotifications] Context not mounted!');
        return;
      }

      // Buscar dados do usuário do Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        debugPrint('❌ [AppNotifications] User not found: $userId');
        if (context.mounted) {
          context.go(AppRoutes.home);
        }
        return;
      }

      final userData = userDoc.data() ?? {};
      final user = _createUserFromData(userData, userId);
      
      debugPrint('✅ [AppNotifications] User encontrado, navegando para perfil...');
      
      // Navegar para o perfil usando ProfileScreenRouter
      if (context.mounted) {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        if (currentUserId != null) {
          context.push(
            '${AppRoutes.profile}/$userId',
            extra: {
              'user': user,
              'currentUserId': currentUserId,
            },
          );
        } else {
          debugPrint('❌ [AppNotifications] Current user not logged in');
          context.go(AppRoutes.home);
        }
      }
    } catch (e, stack) {
      debugPrint('❌ [AppNotifications] Error opening profile: $e');
      debugPrint('   Stack: $stack');
      if (context.mounted) {
        context.go(AppRoutes.home);
      }
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
