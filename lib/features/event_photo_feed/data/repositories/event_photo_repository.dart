import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_comment_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_comment_reply_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';

class EventPhotoPage {
  const EventPhotoPage({
    required this.items,
    required this.nextCursor,
    required this.activeCursor,
    required this.pendingCursor,
    required this.hasMore,
  });

  final List<EventPhotoModel> items;

  /// Cursor compat (parâmetro único). Para o feed simples (somente active),
  /// é equivalente a [activeCursor]. Para o feed mergeado (Option 2), é um
  /// cursor "best-effort" e não deve ser usado para paginação precisa.
  final DocumentSnapshot<Map<String, dynamic>>? nextCursor;

  /// Cursor da query `status=active`.
  final DocumentSnapshot<Map<String, dynamic>>? activeCursor;

  /// Cursor da query `status=under_review AND userId=currentUserId`.
  final DocumentSnapshot<Map<String, dynamic>>? pendingCursor;

  final bool hasMore;
}

class EventPhotoRepository {
  EventPhotoRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _photos => _firestore.collection('EventPhotos');

  /// Feed público (status=active) + posts próprios em análise (status=under_review).
  ///
  /// Observação: para suportar (active OR under_review) com paginação consistente,
  /// buscamos duas queries e fazemos merge no client. Isso mantém o comportamento
  /// de "ativo pra todos" e "em análise só pro autor", sem exigir mudanças de schema.
  Future<EventPhotoPage> fetchFeedPageWithOwnPending({
    required EventPhotoFeedScope scope,
    required int limit,
    required String currentUserId,
    DocumentSnapshot<Map<String, dynamic>>? activeCursor,
    DocumentSnapshot<Map<String, dynamic>>? pendingCursor,
  }) async {
    print('🎯 [EventPhotoRepository.fetchFeedPageWithOwnPending] Iniciando...');
    print('   scope: $scope, limit: $limit, userId: $currentUserId');
    print('   activeCursor: ${activeCursor?.id}, pendingCursor: ${pendingCursor?.id}');
    
    if (currentUserId.trim().isEmpty) {
      print('⚠️ [EventPhotoRepository] userId vazio, usando fetchFeedPage');
      // Fallback: sem userId, retorna feed normal.
      return fetchFeedPage(scope: scope, limit: limit, cursor: activeCursor);
    }

    Query<Map<String, dynamic>> activeQuery = _photos
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    Query<Map<String, dynamic>> pendingQuery = _photos
        .where('status', isEqualTo: 'under_review')
        .where('userId', isEqualTo: currentUserId)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    print('🔍 [EventPhotoRepository] Queries base criadas:');
    print('   - activeQuery: status=active, orderBy(createdAt, desc)');
    print('   - pendingQuery: status=under_review, userId=$currentUserId, orderBy(createdAt, desc)');

    void applyScopeFilters(Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>>) apply) {
      activeQuery = apply(activeQuery);
      pendingQuery = apply(pendingQuery);
    }

    switch (scope) {
      case EventPhotoFeedScopeCity(:final cityId):
        if (cityId != null && cityId.trim().isNotEmpty) {
          print('🌆 [EventPhotoRepository] Aplicando filtro de cidade: $cityId');
          applyScopeFilters((q) => q.where('eventCityId', isEqualTo: cityId.trim()));
        }
        break;
      case EventPhotoFeedScopeGlobal():
        print('🌍 [EventPhotoRepository] Scope global (sem filtros adicionais)');
        break;
      case EventPhotoFeedScopeEvent(:final eventId):
        print('🎉 [EventPhotoRepository] Aplicando filtro de evento: $eventId');
        applyScopeFilters((q) => q.where('eventId', isEqualTo: eventId));
        break;
      case EventPhotoFeedScopeUser(:final userId):
        print('👤 [EventPhotoRepository] Aplicando filtro de usuário: $userId');
        // Para scope user, mostra active do usuário + under_review do usuário logado
        applyScopeFilters((q) => q.where('userId', isEqualTo: userId));
        break;
    }

    if (activeCursor != null) {
      print('⏭️ [EventPhotoRepository] Aplicando activeCursor: ${activeCursor.id}');
      activeQuery = activeQuery.startAfterDocument(activeCursor);
    }
    if (pendingCursor != null) {
      print('⏭️ [EventPhotoRepository] Aplicando pendingCursor: ${pendingCursor.id}');
      pendingQuery = pendingQuery.startAfterDocument(pendingCursor);
    }

    print('🚀 [EventPhotoRepository] Executando queries no Firestore...');
    
    final QuerySnapshot<Map<String, dynamic>> activeSnap;
    final QuerySnapshot<Map<String, dynamic>> pendingSnap;
    
    try {
      final results = await Future.wait([
        activeQuery.get(),
        pendingQuery.get(),
      ]);

      activeSnap = results[0];
      pendingSnap = results[1];
      
      print('✅ [EventPhotoRepository] Queries completadas:');
      print('   - active docs: ${activeSnap.docs.length}');
      print('   - pending docs: ${pendingSnap.docs.length}');
    } catch (e, stack) {
      print('❌ [EventPhotoRepository] ERRO ao executar queries: $e');
      print('📚 Stack trace: $stack');
      rethrow;
    }

    final byId = <String, EventPhotoModel>{};
    for (final d in activeSnap.docs) {
      final m = EventPhotoModel.fromFirestore(d);
      byId[m.id] = m;
    }
    for (final d in pendingSnap.docs) {
      final m = EventPhotoModel.fromFirestore(d);
      byId[m.id] = m;
    }

    final merged = byId.values.toList(growable: false)
      ..sort((a, b) {
        final aTs = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bTs = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTs.compareTo(aTs);
      });

    final limited = merged.length <= limit ? merged : merged.sublist(0, limit);

    final nextActiveCursor = activeSnap.docs.isNotEmpty ? activeSnap.docs.last : activeCursor;
    final nextPendingCursor = pendingSnap.docs.isNotEmpty ? pendingSnap.docs.last : pendingCursor;

    // Heurística: se qualquer query retornou >= limit, pode haver mais.
    final hasMore = activeSnap.docs.length >= limit || pendingSnap.docs.length >= limit;

    // Guardamos um cursor sintético: usamos o doc mais recente entre os dois.
    // (o controller mantém os dois cursores separadamente; aqui devolvemos null)
    // Para evitar quebrar interface existente, mantemos nextCursor como o cursor "ativo".
    // O controller v2 vai usar os dois cursores.
    return EventPhotoPage(
      items: limited,
      nextCursor: nextActiveCursor ?? nextPendingCursor,
      activeCursor: nextActiveCursor,
      pendingCursor: nextPendingCursor,
      hasMore: hasMore,
    );
  }

  Future<EventPhotoPage> fetchFeedPage({
    required EventPhotoFeedScope scope,
    required int limit,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    print('🎯 [EventPhotoRepository.fetchFeedPage] Iniciando...');
    print('   scope: $scope, limit: $limit, cursor: ${cursor?.id}');
    
    Query<Map<String, dynamic>> query = _photos
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    print('🔍 [EventPhotoRepository] Query base: status=active, orderBy(createdAt, desc)');

    switch (scope) {
      case EventPhotoFeedScopeCity(:final cityId):
        if (cityId != null && cityId.trim().isNotEmpty) {
          print('🌆 [EventPhotoRepository] Aplicando filtro de cidade: $cityId');
          query = query.where('eventCityId', isEqualTo: cityId.trim());
        }
        break;
      case EventPhotoFeedScopeGlobal():
        print('🌍 [EventPhotoRepository] Scope global (sem filtros adicionais)');
        break;
      case EventPhotoFeedScopeEvent(:final eventId):
        print('🎉 [EventPhotoRepository] Aplicando filtro de evento: $eventId');
        query = query.where('eventId', isEqualTo: eventId);
        break;
      case EventPhotoFeedScopeUser(:final userId):
        print('👤 [EventPhotoRepository] Aplicando filtro de usuário: $userId');
        query = query.where('userId', isEqualTo: userId);
        break;
    }

    if (cursor != null) {
      print('⏭️ [EventPhotoRepository] Aplicando cursor: ${cursor.id}');
      query = query.startAfterDocument(cursor);
    }

    print('🚀 [EventPhotoRepository] Executando query no Firestore...');
    
    try {
      final snap = await query.get();
      print('✅ [EventPhotoRepository] Query completada: ${snap.docs.length} docs');
      
      final items = snap.docs.map(EventPhotoModel.fromFirestore).toList(growable: false);
      final nextCursor = snap.docs.isNotEmpty ? snap.docs.last : null;
      final hasMore = snap.docs.length >= limit;

      print('📊 [EventPhotoRepository] Resultado: ${items.length} items, hasMore: $hasMore');

      return EventPhotoPage(
        items: items,
        nextCursor: nextCursor,
        activeCursor: nextCursor,
        pendingCursor: null,
        hasMore: hasMore,
      );
    } catch (e, stack) {
      print('❌ [EventPhotoRepository.fetchFeedPage] ERRO: $e');
      print('📚 Stack trace: $stack');
      rethrow;
    }
  }

  Future<void> createPhoto({
    required String photoId,
    required EventPhotoModel model,
  }) async {
    await _photos.doc(photoId).set(model.toCreateMap());
  }

  Future<void> deletePhoto({
    required String photoId,
  }) async {
    await _photos.doc(photoId).delete();
  }

  Future<List<EventPhotoCommentModel>> fetchComments({
    required String photoId,
    int limit = 50,
  }) async {
    final snap = await _photos
        .doc(photoId)
        .collection('comments')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snap.docs
        .map((d) => EventPhotoCommentModel.fromFirestore(d, photoId))
        .toList(growable: false);
  }

  Future<void> addComment({
    required String photoId,
    required EventPhotoCommentModel comment,
  }) async {
    await _photos
        .doc(photoId)
        .collection('comments')
        .add({
          ...comment.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });

    // MVP: contador direto no client (ideal: trigger/backend)
    await _photos.doc(photoId).update({
      'commentsCount': FieldValue.increment(1),
    });
  }

  Future<void> deleteComment({
    required String photoId,
    required String commentId,
  }) async {
    await _photos.doc(photoId).collection('comments').doc(commentId).delete();

    // MVP: contador direto no client (ideal: trigger/backend)
    await _photos.doc(photoId).update({
      'commentsCount': FieldValue.increment(-1),
    });
  }

  Future<List<EventPhotoCommentReplyModel>> fetchCommentReplies({
    required String photoId,
    required String commentId,
    int limit = 50,
  }) async {
    final snap = await _photos
        .doc(photoId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snap.docs
        .map(
          (d) => EventPhotoCommentReplyModel.fromFirestore(
            d,
            photoId: photoId,
            commentId: commentId,
          ),
        )
        .toList(growable: false);
  }

  Future<void> addCommentReply({
    required String photoId,
    required String commentId,
    required EventPhotoCommentReplyModel reply,
  }) async {
    await _photos
        .doc(photoId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .add({
          ...reply.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });

    // MVP: contador direto no client (ideal: trigger/backend)
    await _photos.doc(photoId).update({
      'commentsCount': FieldValue.increment(1),
    });
  }

  Future<void> deleteCommentReply({
    required String photoId,
    required String commentId,
    required String replyId,
  }) async {
    await _photos
        .doc(photoId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .doc(replyId)
        .delete();

    // MVP: contador direto no client (ideal: trigger/backend)
    await _photos.doc(photoId).update({
      'commentsCount': FieldValue.increment(-1),
    });
  }
}

sealed class EventPhotoFeedScope {
  const EventPhotoFeedScope();
}

class EventPhotoFeedScopeCity extends EventPhotoFeedScope {
  const EventPhotoFeedScopeCity({required this.cityId});
  final String? cityId;
}

class EventPhotoFeedScopeGlobal extends EventPhotoFeedScope {
  const EventPhotoFeedScopeGlobal();
}

class EventPhotoFeedScopeEvent extends EventPhotoFeedScope {
  const EventPhotoFeedScopeEvent({required this.eventId});
  final String eventId;
}

class EventPhotoFeedScopeUser extends EventPhotoFeedScope {
  const EventPhotoFeedScopeUser({required this.userId});
  final String userId;
}
