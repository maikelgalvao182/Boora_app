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
}
