import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/screens/notifications/repositories/notifications_repository_interface.dart';

/// Implementação do repositório de notificações com acesso direto ao Firestore
class NotificationsRepository implements INotificationsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Constantes de coleções e campos do Firestore
  static const String _collectionUsers = 'Users';
  static const String _collectionNotifications = 'Notifications';
  static const String _fieldSenderId = 'n_sender_id';
  static const String _fieldSenderFullname = 'n_sender_fullname';
  static const String _fieldSenderPhotoLink = 'n_sender_photo_link';
  static const String _fieldType = 'n_type';
  static const String _fieldRead = 'n_read';
  static const String _fieldTimestamp = 'timestamp';
  static const String _fieldParams = 'n_params';
  static const String _fieldMetadata = 'n_metadata';

  /// Get current user ID
  String? get _currentUserId => _auth.currentUser?.uid;

  /// Get notifications collection reference for current user
  CollectionReference<Map<String, dynamic>>? get _notificationsCollection {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return null;
    
    return _firestore
        .collection(_collectionUsers)
        .doc(userId)
        .collection(_collectionNotifications);
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> getNotifications({String? filterKey}) {
    try {
      final notificationsRef = _notificationsCollection;
      if (notificationsRef == null) {
        return const Stream.empty();
      }

      Query<Map<String, dynamic>> query = notificationsRef;

      // Apply filter if provided
      if (filterKey != null && filterKey.isNotEmpty) {
        query = query.where(_fieldType, isEqualTo: filterKey);
      }

      // Try with orderBy, fallback without if index not ready
      return query.orderBy(_fieldTimestamp, descending: true).snapshots().handleError((error) {
        if (error is FirebaseException &&
            (error.code == 'failed-precondition' || (error.message?.contains('index') == true))) {
          print('[NOTIFICATIONS] Fallback sem orderBy (índice em construção): ${error.message}');
          return query.snapshots();
        } else {
          print('[NOTIFICATIONS] Fallback genérico: $error');
          return query.snapshots();
        }
      });
    } catch (e) {
      print('[NOTIFICATIONS] Error in getNotifications: $e');
      return const Stream.empty();
    }
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> getNotificationsPaginated({
    int limit = 20,
    DocumentSnapshot? lastDocument,
    String? filterKey,
  }) async {
    try {
      final notificationsRef = _notificationsCollection;
      if (notificationsRef == null) {
        throw Exception('User not authenticated');
      }

      Query<Map<String, dynamic>> query = notificationsRef;

      // Apply filter if provided
      if (filterKey != null && filterKey.isNotEmpty) {
        query = query.where(_fieldType, isEqualTo: filterKey);
      }

      // Pagination
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      query = query.limit(limit);

      // Try with orderBy
      QuerySnapshot<Map<String, dynamic>> result;
      try {
        final queryWithOrder = query.orderBy(_fieldTimestamp, descending: true);
        result = await queryWithOrder.get();
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition' || (e.message?.contains('index') == true)) {
          print('[NOTIFICATIONS] Fallback sem orderBy na paginação: ${e.message}');
          result = await query.get();
        } else {
          print('[NOTIFICATIONS] Fallback genérico na paginação: ${e.message}');
          result = await query.get();
        }
      }

      return result;
    } catch (e) {
      print('[NOTIFICATIONS] Error in getNotificationsPaginated: $e');
      rethrow;
    }
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> getNotificationsPaginatedStream({
    int limit = 20,
    String? filterKey,
  }) {
    try {
      final notificationsRef = _notificationsCollection;
      if (notificationsRef == null) {
        return const Stream.empty();
      }

      Query<Map<String, dynamic>> query = notificationsRef.limit(limit);

      // Apply filter if provided
      if (filterKey != null && filterKey.isNotEmpty) {
        query = query.where(_fieldType, isEqualTo: filterKey);
      }

      // Try with orderBy, fallback without if index not ready
      return query.orderBy(_fieldTimestamp, descending: true).snapshots().handleError((error) {
        if (error is FirebaseException &&
            (error.code == 'failed-precondition' || (error.message?.contains('index') == true))) {
          print('[NOTIFICATIONS] Stream fallback sem orderBy: ${error.message}');
          return query.snapshots();
        } else {
          print('[NOTIFICATIONS] Stream fallback genérico: $error');
          return query.snapshots();
        }
      });
    } catch (e) {
      print('[NOTIFICATIONS] Error in getNotificationsPaginatedStream: $e');
      return const Stream.empty();
    }
  }

  @override
  Future<void> saveNotification({
    required String nReceiverId,
    required String nType,
    required String nMessage,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('[NOTIFICATIONS] Tentativa de salvar notificação sem usuário logado');
        return;
      }

      final notificationData = <String, dynamic>{
        _fieldSenderId: currentUser.uid,
        _fieldSenderFullname: currentUser.displayName ?? 'Unknown',
        _fieldSenderPhotoLink: currentUser.photoURL ?? '',
        _fieldType: nType,
        _fieldRead: false,
        _fieldTimestamp: FieldValue.serverTimestamp(),
        _fieldParams: {'message': nMessage},
      };

      // Save to receiver's subcollection
      await _firestore
          .collection(_collectionUsers)
          .doc(nReceiverId)
          .collection(_collectionNotifications)
          .add(notificationData);
    } catch (e) {
      print('[NOTIFICATIONS] Error saving notification: $e');
    }
  }

  @override
  Future<void> onPurchaseNotification({
    required String nMessage,
  }) async {
    try {
      final userId = _currentUserId;
      if (userId == null || userId.isEmpty) {
        print('[NOTIFICATIONS] Tentativa de notificação de compra sem usuário logado');
        return;
      }

      await saveNotification(
        nReceiverId: userId,
        nType: 'alert',
        nMessage: nMessage,
      );
    } catch (e) {
      print('[NOTIFICATIONS] Error in onPurchaseNotification: $e');
    }
  }

  @override
  Future<void> deleteUserNotifications() async {
    try {
      final notificationsRef = _notificationsCollection;
      if (notificationsRef == null) {
        print('[NOTIFICATIONS] Tentativa de deletar notificações sem usuário logado');
        return;
      }

      final snapshot = await notificationsRef.get();

      if (snapshot.docs.isEmpty) return;

      // Usar WriteBatch para operações em lote
      final batch = _firestore.batch();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e) {
      print('[NOTIFICATIONS] Error deleting user notifications: $e');
    }
  }

  @override
  Future<void> deleteUserSentNotifications() async {
    try {
      final userId = _currentUserId;
      if (userId == null || userId.isEmpty) {
        print('[NOTIFICATIONS] Tentativa de deletar notificações enviadas sem usuário logado');
        return;
      }

      // Buscar todas as notificações onde o usuário é o sender
      // Isso requer buscar em todas as subcoleções de notificações de todos os usuários
      // Por questões de performance, não implementamos isso em subcoleções
      // Em vez disso, as notificações são deletadas automaticamente quando o usuário é deletado
      print('[NOTIFICATIONS] deleteUserSentNotifications não implementado para subcoleções');
    } catch (e) {
      print('[NOTIFICATIONS] Error deleting sent notifications: $e');
    }
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    try {
      final notificationsRef = _notificationsCollection;
      if (notificationsRef == null) {
        print('[NOTIFICATIONS] Tentativa de deletar notificação sem usuário logado');
        return;
      }

      await notificationsRef.doc(notificationId).delete();
    } catch (e) {
      print('[NOTIFICATIONS] Error deleting notification: $e');
      rethrow;
    }
  }

  @override
  Future<void> readNotification(String notificationId) async {
    try {
      final notificationsRef = _notificationsCollection;
      if (notificationsRef == null) {
        return;
      }

      await notificationsRef
          .doc(notificationId)
          .update({_fieldRead: true});
    } catch (e) {
      // Silencioso - não é crítico
      print('[NOTIFICATIONS] Error marking as read: $e');
    }
  }
}
