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

  /// Busca itens do feed de múltiplos usuários (seguidos)
  /// 
  /// Usado para a aba "Seguindo" - busca activities dos usuários seguidos.
  /// Firestore limita whereIn a 10 elementos, então fazemos chunks.
  Future<List<ActivityFeedItemModel>> fetchFollowingFeed({
    required List<String> userIds,
    int limit = 20,
  }) async {
    if (userIds.isEmpty) return [];
    
    try {
      // Chunk em grupos de 10 (limite do whereIn do Firestore)
      final chunks = <List<String>>[];
      for (var i = 0; i < userIds.length; i += 10) {
        final end = (i + 10) > userIds.length ? userIds.length : (i + 10);
        chunks.add(userIds.sublist(i, end));
      }
      
      // Busca em paralelo para cada chunk
      final futures = chunks.map((chunk) {
        return _feedCollection
            .where('userId', whereIn: chunk)
            .where('status', isEqualTo: 'active')
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .get();
      }).toList();
      
      final results = await Future.wait(futures);
      
      // Merge e ordena por createdAt
      final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final snap in results) {
        allDocs.addAll(snap.docs);
      }
      
      // Ordena por createdAt descending
      allDocs.sort((a, b) {
        final aTs = a.data()['createdAt'] as Timestamp?;
        final bTs = b.data()['createdAt'] as Timestamp?;
        final aMs = aTs?.millisecondsSinceEpoch ?? 0;
        final bMs = bTs?.millisecondsSinceEpoch ?? 0;
        return bMs.compareTo(aMs);
      });
      
      // Limita ao tamanho desejado
      final limited = allDocs.take(limit).toList();
      
      debugPrint('✅ [ActivityFeedRepository.fetchFollowingFeed] ${limited.length} items de ${userIds.length} usuários');
      
      return limited
          .map((doc) => ActivityFeedItemModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ [ActivityFeedRepository] Erro ao buscar feed de seguidos: $e');
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

  /// Busca itens do feed de um usuário mais novos que um timestamp
  /// 
  /// Usado para refresh incremental.
  Future<List<ActivityFeedItemModel>> fetchUserFeedNewerThan({
    required String userId,
    required Timestamp newerThan,
    int limit = 20,
  }) async {
    try {
      final query = _feedCollection
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .where('createdAt', isGreaterThan: newerThan)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      final snapshot = await query.get();
      debugPrint('✅ [ActivityFeedRepository.fetchUserFeedNewerThan] ${snapshot.docs.length} novos items');
      return snapshot.docs
          .map((doc) => ActivityFeedItemModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ [ActivityFeedRepository] Erro ao buscar feed incremental: $e');
      rethrow;
    }
  }

  /// Busca itens do feed de múltiplos usuários mais novos que um timestamp
  /// 
  /// Usado para refresh incremental na aba "Seguindo".
  Future<List<ActivityFeedItemModel>> fetchFollowingFeedNewerThan({
    required List<String> userIds,
    required Timestamp newerThan,
    int limit = 20,
  }) async {
    if (userIds.isEmpty) return [];
    
    try {
      // Chunk em grupos de 10 (limite do whereIn do Firestore)
      final chunks = <List<String>>[];
      for (var i = 0; i < userIds.length; i += 10) {
        final end = (i + 10) > userIds.length ? userIds.length : (i + 10);
        chunks.add(userIds.sublist(i, end));
      }
      
      // Busca em paralelo para cada chunk
      final futures = chunks.map((chunk) {
        return _feedCollection
            .where('userId', whereIn: chunk)
            .where('status', isEqualTo: 'active')
            .where('createdAt', isGreaterThan: newerThan)
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .get();
      }).toList();
      
      final results = await Future.wait(futures);
      
      // Merge e ordena
      final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final snap in results) {
        allDocs.addAll(snap.docs);
      }
      
      allDocs.sort((a, b) {
        final aTs = a.data()['createdAt'] as Timestamp?;
        final bTs = b.data()['createdAt'] as Timestamp?;
        final aMs = aTs?.millisecondsSinceEpoch ?? 0;
        final bMs = bTs?.millisecondsSinceEpoch ?? 0;
        return bMs.compareTo(aMs);
      });
      
      final limited = allDocs.take(limit).toList();
      
      debugPrint('✅ [ActivityFeedRepository.fetchFollowingFeedNewerThan] ${limited.length} novos items de ${userIds.length} usuários');
      
      return limited
          .map((doc) => ActivityFeedItemModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ [ActivityFeedRepository] Erro ao buscar feed incremental de seguidos: $e');
      rethrow;
    }
  }

  /// Busca itens do feed global mais novos que um timestamp
  /// 
  /// Usado para refresh incremental.
  Future<List<ActivityFeedItemModel>> fetchGlobalFeedNewerThan({
    required Timestamp newerThan,
    int limit = 20,
  }) async {
    try {
      final query = _feedCollection
          .where('status', isEqualTo: 'active')
          .where('createdAt', isGreaterThan: newerThan)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      final snapshot = await query.get();
      debugPrint('✅ [ActivityFeedRepository.fetchGlobalFeedNewerThan] ${snapshot.docs.length} novos items');
      return snapshot.docs
          .map((doc) => ActivityFeedItemModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ [ActivityFeedRepository] Erro ao buscar feed global incremental: $e');
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
