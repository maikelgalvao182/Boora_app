import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/feed/data/models/activity_feed_item_model.dart';

/// Repositório para gerenciar o feed de atividades do usuário
/// 
/// Coleção: `ActivityFeed`
/// Documento: ID único gerado automaticamente
/// 
/// Estrutura:
/// - eventId: string (referência ao evento)
/// - userId: string (quem criou o evento)
/// - userFullName: string (congelado)
/// - activityText: string (congelado)
/// - emoji: string (congelado)
/// - locationName: string (congelado)
/// - eventDate: timestamp (congelado)
/// - createdAt: timestamp
/// - userPhotoUrl: string (opcional, congelado)
/// - status: string ('active' | 'deleted')
class ActivityFeedRepository {
  ActivityFeedRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _feedCollection =>
      _firestore.collection('ActivityFeed');

  /// Cria um novo item no feed quando um evento é criado
  /// 
  /// Os dados são "congelados" no momento da criação.
  /// Isso garante que o feed mostra o estado original do evento,
  /// mesmo que ele seja editado posteriormente.
  Future<String> createFeedItem({
    required String eventId,
    required String userId,
    required String userFullName,
    required String activityText,
    required String emoji,
    required String locationName,
    required DateTime eventDate,
    String? userPhotoUrl,
  }) async {
    try {
      final docRef = await _feedCollection.add({
        'eventId': eventId,
        'userId': userId,
        'userFullName': userFullName,
        'activityText': activityText,
        'emoji': emoji,
        'locationName': locationName,
        'eventDate': Timestamp.fromDate(eventDate),
        'createdAt': FieldValue.serverTimestamp(),
        'userPhotoUrl': userPhotoUrl,
        'status': 'active',
      });

      debugPrint('✅ [ActivityFeedRepository] FeedItem criado: ${docRef.id} para evento $eventId');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ [ActivityFeedRepository] Erro ao criar FeedItem: $e');
      rethrow;
    }
  }

  /// Busca itens do feed de um usuário específico
  /// 
  /// Retorna apenas itens com status 'active', ordenados por data de criação.
  Future<List<ActivityFeedItemModel>> fetchUserFeed({
    required String userId,
    int limit = 20,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _feedCollection
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => ActivityFeedItemModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ [ActivityFeedRepository] Erro ao buscar feed: $e');
      rethrow;
    }
  }

  /// Busca feed global (todos os usuários)
  /// 
  /// Útil para uma timeline geral da comunidade.
  Future<List<ActivityFeedItemModel>> fetchGlobalFeed({
    int limit = 20,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _feedCollection
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => ActivityFeedItemModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ [ActivityFeedRepository] Erro ao buscar feed global: $e');
      rethrow;
    }
  }

  /// Deleta (soft delete) todos os itens do feed relacionados a um evento
  /// 
  /// Usado quando o evento é deletado.
  /// Faz soft delete (muda status para 'deleted') ao invés de hard delete.
  Future<void> deleteFeedItemsByEventId(String eventId) async {
    try {
      final snapshot = await _feedCollection
          .where('eventId', isEqualTo: eventId)
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('ℹ️ [ActivityFeedRepository] Nenhum FeedItem encontrado para evento $eventId');
        return;
      }

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'status': 'deleted'});
      }
      await batch.commit();

      debugPrint('✅ [ActivityFeedRepository] ${snapshot.docs.length} FeedItem(s) deletado(s) para evento $eventId');
    } catch (e) {
      debugPrint('❌ [ActivityFeedRepository] Erro ao deletar FeedItems: $e');
      rethrow;
    }
  }

  /// Deleta (hard delete) todos os itens do feed relacionados a um evento
  /// 
  /// Usado pela Cloud Function para limpeza completa.
  Future<int> hardDeleteFeedItemsByEventId(String eventId) async {
    try {
      final snapshot = await _feedCollection
          .where('eventId', isEqualTo: eventId)
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('ℹ️ [ActivityFeedRepository] Nenhum FeedItem encontrado para evento $eventId');
        return 0;
      }

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      debugPrint('✅ [ActivityFeedRepository] ${snapshot.docs.length} FeedItem(s) hard-deleted para evento $eventId');
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('❌ [ActivityFeedRepository] Erro ao hard-delete FeedItems: $e');
      rethrow;
    }
  }

  /// Busca um item específico do feed pelo ID do evento
  Future<ActivityFeedItemModel?> getFeedItemByEventId(String eventId) async {
    try {
      final snapshot = await _feedCollection
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return ActivityFeedItemModel.fromFirestore(snapshot.docs.first);
    } catch (e) {
      debugPrint('❌ [ActivityFeedRepository] Erro ao buscar FeedItem: $e');
      rethrow;
    }
  }
}
