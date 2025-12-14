import 'package:flutter/foundation.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/features/home/data/repositories/pending_applications_repository.dart';
import 'package:partiu/features/reviews/data/repositories/review_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

/// Serviço centralizado para gerenciar contadores de notificações
/// 
/// Responsabilidades:
/// - Contar aplicações pendentes (Actions Tab)
/// - Contar reviews pendentes (Actions Tab)
/// - Contar mensagens não lidas (Conversations Tab)
/// - Expor streams reativos para badges
class NotificationsCounterService {
  NotificationsCounterService._();
  
  static final NotificationsCounterService instance = NotificationsCounterService._();

  final _pendingApplicationsRepo = PendingApplicationsRepository();
  final _reviewRepository = ReviewRepository();
  final _firestore = FirebaseFirestore.instance;

  // ValueNotifiers para badges reativos
  final pendingActionsCount = ValueNotifier<int>(0);
  final unreadConversationsCount = ValueNotifier<int>(0);
  final unreadNotificationsCount = ValueNotifier<int>(0);

  // StreamSubscriptions para cancelar no logout
  StreamSubscription<List<dynamic>>? _pendingApplicationsSubscription;
  StreamSubscription<List<dynamic>>? _pendingReviewsSubscription;
  StreamSubscription<QuerySnapshot>? _conversationsSubscription;
  StreamSubscription<QuerySnapshot>? _notificationsSubscription;

  // Contadores internos
  int _applicationsCount = 0;
  int _reviewsCount = 0;

  /// Verifica se os listeners estão ativos
  bool get isActive => _notificationsSubscription != null;

  /// Inicializa os listeners de contadores
  void initialize() {
    // Cancelar listeners anteriores se existirem
    _cancelAllSubscriptions();
    
    _listenToPendingApplications();
    _listenToPendingReviews();
    _listenToUnreadConversations();
    _listenToUnreadNotifications();
  }

  /// Cancela todas as subscriptions ativas
  void _cancelAllSubscriptions() {
    _pendingApplicationsSubscription?.cancel();
    _pendingReviewsSubscription?.cancel();
    _conversationsSubscription?.cancel();
    _notificationsSubscription?.cancel();
    
    _pendingApplicationsSubscription = null;
    _pendingReviewsSubscription = null;
    _conversationsSubscription = null;
    _notificationsSubscription = null;
  }

  /// Atualiza o contador total de ações (applications + reviews)
  void _updateActionsCount() {
    final total = _applicationsCount + _reviewsCount;
    pendingActionsCount.value = total;
  }

  /// Escuta aplicações pendentes (Actions Tab)
  /// Escuta aplicações pendentes (Actions Tab)
  void _listenToPendingApplications() {
    _pendingApplicationsSubscription = _pendingApplicationsRepo.getPendingApplicationsStream().listen(
      (applications) {
        _applicationsCount = applications.length;
        _updateActionsCount();
      },
      onError: (error) {
        _applicationsCount = 0;
        _updateActionsCount();
      },
    );
  }

  /// Escuta reviews pendentes (Actions Tab)
  void _listenToPendingReviews() {
    _pendingReviewsSubscription = _reviewRepository.getPendingReviewsStream().listen(
      (reviews) {
        _reviewsCount = reviews.length;
        _updateActionsCount();
      },
      onError: (error) {
        _reviewsCount = 0;
        _updateActionsCount();
      },
    );
  }
  /// Escuta conversas não lidas (Conversations Tab)
  void _listenToUnreadConversations() {
    final currentUserId = AppState.currentUserId;
    
    if (currentUserId == null) {
      debugPrint('⚠️ [NotificationsCounterService] _listenToUnreadConversations: currentUserId é null!');
      return;
    }
    
    debugPrint('🔔 [NotificationsCounterService] _listenToUnreadConversations: Iniciando listener para userId: $currentUserId');

    _conversationsSubscription = _firestore
        .collection('Connections')
        .doc(currentUserId)
        .collection('Conversations')
        .snapshots()
        .listen(
      (snapshot) {
        debugPrint('🔔 [NotificationsCounterService] Snapshot recebido: ${snapshot.docs.length} conversas');
        int unreadCount = 0;
        
        for (final doc in snapshot.docs) {
          final data = doc.data();
          
          // Verificar se há mensagem não lida usando AMBOS os campos (compatibilidade)
          final hasUnreadMessage = data['has_unread_message'] as bool? ?? false;
          final messageRead = data['message_read'] as bool? ?? true;
          final unreadCountField = data['unread_count'] as int? ?? 0;
          
          // Considera não lida se:
          // 1. has_unread_message == true OU
          // 2. message_read == false OU
          // 3. unread_count > 0
          final hasUnread = hasUnreadMessage || !messageRead || unreadCountField > 0;
          
          // Verificar se a última mensagem não é do usuário atual
          final lastMessageSender = data['last_message_sender'] as String?;
          
          // Se há mensagens não lidas (unread_count > 0), assume que são de outra pessoa
          // Caso contrário, verifica o last_message_sender
          final isFromOther = unreadCountField > 0 || 
                             (lastMessageSender != null && lastMessageSender != currentUserId);
          
          if (hasUnread && isFromOther) {
            unreadCount++;
          }
        }
        
        debugPrint('🔔 [NotificationsCounterService] unreadCount calculado: $unreadCount');
        unreadConversationsCount.value = unreadCount;
        AppState.unreadMessages.value = unreadCount; // Atualiza AppState também
        debugPrint('🔔 [NotificationsCounterService] unreadConversationsCount.value atualizado para: ${unreadConversationsCount.value}');
      },
      onError: (error) {
        debugPrint('❌ [NotificationsCounterService] Erro no listener de conversas: $error');
        unreadConversationsCount.value = 0;
      },
    );
  }

  /// Escuta notificações não lidas (Notification Icon)
  void _listenToUnreadNotifications() {
    final currentUserId = AppState.currentUserId;
    
    if (currentUserId == null) {
      debugPrint('⚠️ [NotificationsCounterService] _listenToUnreadNotifications: currentUserId é null!');
      return;
    }
    
    debugPrint('🔔 [NotificationsCounterService] _listenToUnreadNotifications: Iniciando listener para userId: $currentUserId');
    
    _notificationsSubscription = _firestore
        .collection('Notifications')
        .where('n_receiver_id', isEqualTo: currentUserId)
        .where('n_read', isEqualTo: false)
        .snapshots()
        .listen(
      (snapshot) {
        final count = snapshot.docs.length;
        debugPrint('🔔 [NotificationsCounterService] Snapshot de notificações: $count não lidas');
        
        // Atualizar AppState diretamente (padrão Advanced-Dating)
        AppState.unreadNotifications.value = count;
        unreadNotificationsCount.value = count;
        debugPrint('🔔 [NotificationsCounterService] AppState.unreadNotifications atualizado para: $count');
      },
      onError: (error) {
        AppState.unreadNotifications.value = 0;
        unreadNotificationsCount.value = 0;
      },
    );
  }

  /// Limpa os contadores (usar no logout)
  void reset() {
    // Cancelar todas as subscriptions
    _cancelAllSubscriptions();
    
    // Resetar contadores internos
    _applicationsCount = 0;
    _reviewsCount = 0;
    
    // Atualizar AppState (padrão Advanced-Dating)
    AppState.unreadNotifications.value = 0;
    pendingActionsCount.value = 0;
    unreadConversationsCount.value = 0;
    unreadNotificationsCount.value = 0;
  }

  /// Dispose dos listeners
  void dispose() {
    _cancelAllSubscriptions();
    pendingActionsCount.dispose();
    unreadConversationsCount.dispose();
    unreadNotificationsCount.dispose();
  }
}
