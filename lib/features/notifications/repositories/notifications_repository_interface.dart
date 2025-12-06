import 'package:cloud_firestore/cloud_firestore.dart';

/// Interface para o repositório de notificações
abstract class INotificationsRepository {
  /// Obtém as notificações do usuário atual
  Stream<QuerySnapshot<Map<String, dynamic>>> getNotifications({String? filterKey});
  
  /// Obtém notificações paginadas
  Future<QuerySnapshot<Map<String, dynamic>>> getNotificationsPaginated({
    int limit = 20,
    DocumentSnapshot? lastDocument,
    String? filterKey,
  });
  
  /// Obtém stream de notificações paginadas (real-time para primeira página)
  Stream<QuerySnapshot<Map<String, dynamic>>> getNotificationsPaginatedStream({
    int limit = 20,
    String? filterKey,
  });
  
  /// Salva uma notificação
  Future<void> saveNotification({
    required String nReceiverId,
    required String nType,
    required String nMessage,
  });
  
  /// Notifica o usuário atual após comprar uma assinatura VIP
  Future<void> onPurchaseNotification({
    required String nMessage,
  });
  
  /// Deleta todas as notificações do usuário atual
  Future<void> deleteUserNotifications();
  
  /// Deleta todas as notificações enviadas pelo usuário atual
  Future<void> deleteUserSentNotifications();
  
  /// Deleta uma notificação específica
  Future<void> deleteNotification(String notificationId);
  
  /// Marca uma notificação como lida
  Future<void> readNotification(String notificationId);
  
  // ===============================================
  // MÉTODOS ESPECÍFICOS PARA ATIVIDADES
  // ===============================================
  
  /// Cria notificação de atividade com parâmetros estruturados
  /// 
  /// Este método suporta o novo formato semântico com n_params
  Future<void> createActivityNotification({
    required String receiverId,
    required String type,
    required Map<String, dynamic> params,
    String? senderId,
    String? senderName,
    String? senderPhotoUrl,
    String? relatedId,
  });
  
  /// Busca notificações relacionadas a uma atividade específica
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> fetchNotificationsByActivity({
    required String activityId,
    int limit = 50,
  });
  
  /// Marca todas as notificações de uma atividade como lidas
  Future<void> markAllActivityNotificationsAsRead({
    required String activityId,
  });
  
  /// Deleta todas as notificações relacionadas a uma atividade
  /// Útil quando uma atividade é deletada permanentemente
  Future<void> deleteActivityNotifications({
    required String activityId,
  });
}
