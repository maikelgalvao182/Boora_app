import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/features/profile/models/profile_view_model.dart';

/// Repository para gerenciar visualizações de perfil
/// 
/// Responsável por:
/// - Registrar visualizações
/// - Buscar visualizações não notificadas
/// - Marcar visualizações como notificadas
/// - Contar visualizações em período específico
class ProfileViewRepository {
  ProfileViewRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const String _collectionName = 'ProfileViews';

  /// Registra uma nova visualização de perfil
  /// 
  /// Não registra se:
  /// - Usuário visualiza o próprio perfil
  /// - Já existe visualização do mesmo viewer nas últimas 24h (debounce)
  Future<void> recordProfileView({
    required String viewedUserId,
    String? viewerName,
    String? viewerPhotoUrl,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('[ProfileViewRepository] Tentativa de registrar view sem autenticação');
        return;
      }

      final viewerId = currentUser.uid;

      // Não registra visualização de si mesmo
      if (viewerId == viewedUserId) {
        return;
      }

      // Debounce: verifica se já existe visualização recente (últimas 24h)
      final yesterday = DateTime.now().subtract(const Duration(hours: 24));
      final recentViews = await _firestore
          .collection(_collectionName)
          .where('viewerId', isEqualTo: viewerId)
          .where('viewedUserId', isEqualTo: viewedUserId)
          .where('viewedAt', isGreaterThan: Timestamp.fromDate(yesterday))
          .limit(1)
          .get();

      if (recentViews.docs.isNotEmpty) {
        print('[ProfileViewRepository] Visualização recente já existe (debounce 24h)');
        return;
      }

      // Registra nova visualização
      final profileView = ProfileViewModel(
        viewerId: viewerId,
        viewedUserId: viewedUserId,
        viewedAt: DateTime.now(),
        notified: false,
        viewerName: viewerName ?? currentUser.displayName,
        viewerPhotoUrl: viewerPhotoUrl ?? currentUser.photoURL,
      );

      await _firestore
          .collection(_collectionName)
          .add(profileView.toFirestore());

      print('[ProfileViewRepository] Visualização registrada: $viewerId -> $viewedUserId');
    } catch (e) {
      print('[ProfileViewRepository] Erro ao registrar visualização: $e');
    }
  }

  /// Busca visualizações não notificadas de um usuário
  /// 
  /// @param userId - ID do usuário que recebeu as visualizações
  /// @param limit - Máximo de resultados (padrão: 100)
  Future<List<ProfileViewModel>> fetchUnnotifiedViews({
    required String userId,
    int limit = 100,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .where('viewedUserId', isEqualTo: userId)
          .where('notified', isEqualTo: false)
          .orderBy('viewedAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => ProfileViewModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('[ProfileViewRepository] Erro ao buscar visualizações: $e');
      return [];
    }
  }

  /// Conta visualizações não notificadas
  Future<int> countUnnotifiedViews({required String userId}) async {
    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .where('viewedUserId', isEqualTo: userId)
          .where('notified', isEqualTo: false)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      print('[ProfileViewRepository] Erro ao contar visualizações: $e');
      return 0;
    }
  }

  /// Marca visualizações como notificadas
  /// 
  /// @param viewIds - Lista de IDs de ProfileView documents
  Future<void> markAsNotified(List<String> viewIds) async {
    if (viewIds.isEmpty) return;

    try {
      final batch = _firestore.batch();

      for (final viewId in viewIds) {
        final docRef = _firestore.collection(_collectionName).doc(viewId);
        batch.update(docRef, {'notified': true});
      }

      await batch.commit();
      print('[ProfileViewRepository] ${viewIds.length} visualizações marcadas como notificadas');
    } catch (e) {
      print('[ProfileViewRepository] Erro ao marcar como notificadas: $e');
    }
  }

  /// Busca visualizações em período específico
  /// 
  /// Útil para estatísticas e analytics
  Future<List<ProfileViewModel>> fetchViewsInPeriod({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .where('viewedUserId', isEqualTo: userId)
          .where('viewedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('viewedAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('viewedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ProfileViewModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('[ProfileViewRepository] Erro ao buscar visualizações por período: $e');
      return [];
    }
  }

  /// Deleta visualizações antigas (cleanup)
  /// 
  /// Remove visualizações com mais de X dias (padrão: 90 dias)
  Future<void> deleteOldViews({int daysOld = 90}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      final snapshot = await _firestore
          .collection(_collectionName)
          .where('viewedAt', isLessThan: Timestamp.fromDate(cutoffDate))
          .limit(500) // Processa em lotes para evitar timeout
          .get();

      if (snapshot.docs.isEmpty) {
        print('[ProfileViewRepository] Nenhuma visualização antiga para deletar');
        return;
      }

      final batch = _firestore.batch();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('[ProfileViewRepository] ${snapshot.docs.length} visualizações antigas deletadas');
    } catch (e) {
      print('[ProfileViewRepository] Erro ao deletar visualizações antigas: $e');
    }
  }

  /// Stream de visualizações não notificadas (real-time)
  /// 
  /// Útil para UI reativa (badge de notificações)
  Stream<int> watchUnnotifiedCount({required String userId}) {
    return _firestore
        .collection(_collectionName)
        .where('viewedUserId', isEqualTo: userId)
        .where('notified', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}
