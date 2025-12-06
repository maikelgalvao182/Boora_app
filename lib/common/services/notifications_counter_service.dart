import 'package:flutter/foundation.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/features/home/data/repositories/pending_applications_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Serviço centralizado para gerenciar contadores de notificações
/// 
/// Responsabilidades:
/// - Contar aplicações pendentes (Actions Tab)
/// - Contar mensagens não lidas (Conversations Tab)
/// - Expor streams reativos para badges
class NotificationsCounterService {
  NotificationsCounterService._();
  
  static final NotificationsCounterService instance = NotificationsCounterService._();

  final _pendingApplicationsRepo = PendingApplicationsRepository();
  final _firestore = FirebaseFirestore.instance;

  // ValueNotifiers para badges reativos
  final pendingActionsCount = ValueNotifier<int>(0);
  final unreadConversationsCount = ValueNotifier<int>(0);
  final unreadNotificationsCount = ValueNotifier<int>(0);

  /// Inicializa os listeners de contadores
  void initialize() {
    debugPrint('🚀 [NotificationsCounter] Inicializando serviço...');
    debugPrint('🚀 [NotificationsCounter] AppState.currentUserId: ${AppState.currentUserId}');
    _listenToPendingApplications();
    _listenToUnreadConversations();
    _listenToUnreadNotifications();
    debugPrint('🚀 [NotificationsCounter] Serviço inicializado');
  }

  /// Escuta aplicações pendentes (Actions Tab)
  void _listenToPendingApplications() {
    _pendingApplicationsRepo.getPendingApplicationsStream().listen(
      (applications) {
        pendingActionsCount.value = applications.length;
        debugPrint('📊 [NotificationsCounter] Ações pendentes: ${applications.length}');
      },
      onError: (error) {
        debugPrint('❌ [NotificationsCounter] Erro ao contar ações: $error');
        pendingActionsCount.value = 0;
      },
    );
  }

  /// Escuta conversas não lidas (Conversations Tab)
  void _listenToUnreadConversations() {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) {
      debugPrint('⚠️ [NotificationsCounter] Usuário não autenticado');
      return;
    }

    _firestore
        .collection('Connections')
        .where('participants', arrayContains: currentUserId)
        .snapshots()
        .listen(
      (snapshot) {
        int unreadCount = 0;
        
        for (final doc in snapshot.docs) {
          final data = doc.data();
          
          // Verificar se há mensagem não lida
          final hasUnread = data['has_unread_message'] as bool? ?? false;
          
          // Verificar se a última mensagem não é do usuário atual
          final lastMessageSender = data['last_message_sender'] as String?;
          final isFromOther = lastMessageSender != null && lastMessageSender != currentUserId;
          
          if (hasUnread && isFromOther) {
            unreadCount++;
          }
        }
        
        unreadConversationsCount.value = unreadCount;
        AppState.unreadMessages.value = unreadCount; // Atualiza AppState também
        
        debugPrint('📊 [NotificationsCounter] Conversas não lidas: $unreadCount');
      },
      onError: (error) {
        debugPrint('❌ [NotificationsCounter] Erro ao contar conversas: $error');
        unreadConversationsCount.value = 0;
      },
    );
  }

  /// Escuta notificações não lidas (Notification Icon)
  void _listenToUnreadNotifications() {
    final currentUserId = AppState.currentUserId;
    
    debugPrint('📊 [NotificationsCounter] Iniciando listener de notificações não lidas');
    debugPrint('📊 [NotificationsCounter] UserId: $currentUserId');
    
    if (currentUserId == null) {
      debugPrint('⚠️ [NotificationsCounter] Usuário não autenticado - não pode iniciar listener');
      return;
    }

    debugPrint('📊 [NotificationsCounter] Criando query: Notifications.userId == $currentUserId && n_read == false');
    
    _firestore
        .collection('Notifications')
        .where('userId', isEqualTo: currentUserId)
        .where('n_read', isEqualTo: false)
        .snapshots()
        .listen(
      (snapshot) {
        final count = snapshot.docs.length;
        // Atualizar AppState diretamente (padrão Advanced-Dating)
        AppState.unreadNotifications.value = count;
        unreadNotificationsCount.value = count;
        debugPrint('📊 [NotificationsCounter] ✅ Notificações não lidas atualizadas: $count');
        debugPrint('📊 [NotificationsCounter] Documentos recebidos: ${snapshot.docs.map((d) => d.id).take(5).toList()}');
      },
      onError: (error) {
        debugPrint('❌ [NotificationsCounter] Erro ao contar notificações: $error');
        AppState.unreadNotifications.value = 0;
        unreadNotificationsCount.value = 0;
      },
    );
  }

  /// Limpa os contadores (usar no logout)
  void reset() {
    // Atualizar AppState (padrão Advanced-Dating)
    AppState.unreadNotifications.value = 0;
    pendingActionsCount.value = 0;
    unreadConversationsCount.value = 0;
    unreadNotificationsCount.value = 0;
    debugPrint('🗑️ [NotificationsCounter] Contadores resetados');
  }

  /// Dispose dos listeners
  void dispose() {
    pendingActionsCount.dispose();
    unreadConversationsCount.dispose();
    unreadNotificationsCount.dispose();
  }
}
