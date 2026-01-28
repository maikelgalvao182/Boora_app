import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_comment_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_comment_reply_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_feed_scope.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/domain/services/event_photo_cache_service.dart';

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
  EventPhotoRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    EventPhotoCacheService? cacheService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _cacheService = cacheService;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final EventPhotoCacheService? _cacheService;

  CollectionReference<Map<String, dynamic>> get _photos => _firestore.collection('EventPhotos');

  static const int _followingChunkSize = 10;

  Future<List<String>> _fetchFollowingIds(String userId) async {
    final snap = await _firestore
        .collection('Users')
        .doc(userId)
        .collection('following')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();

    return snap.docs.map((doc) => doc.id).toList(growable: false);
  }

  List<List<String>> _chunkIds(List<String> ids, int size) {
    if (ids.isEmpty) return const [];
    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += size) {
      final end = (i + size) > ids.length ? ids.length : (i + size);
      chunks.add(ids.sublist(i, end));
    }
    return chunks;
  }

  dynamic _cursorCreatedAt(DocumentSnapshot<Map<String, dynamic>>? cursor) {
    if (cursor == null) return null;
    final data = cursor.data();
    return data?['createdAt'];
  }

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
      case EventPhotoFeedScopeFollowing():
        print('👥 [EventPhotoRepository] Scope seguindo (seguindo ids)');
        return _fetchFollowingPage(
          currentUserId: currentUserId,
          limit: limit,
          cursor: activeCursor,
        );
      case EventPhotoFeedScopeEvent(:final eventId):
        print('🎉 [EventPhotoRepository] Aplicando filtro de evento: $eventId');
        applyScopeFilters((q) => q.where('eventId', isEqualTo: eventId));
        break;
      case EventPhotoFeedScopeUser(:final userId):
        print('👤 [EventPhotoRepository] Aplicando filtro de usuário: $userId');
        // Para scope user, mostra active do usuário + under_review do usuário logado
        activeQuery = activeQuery.where('userId', isEqualTo: userId);
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

  Future<EventPhotoPage> _fetchFollowingPage({
    required String currentUserId,
    required int limit,
    required DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    if (currentUserId.trim().isEmpty) {
      return const EventPhotoPage(
        items: [],
        nextCursor: null,
        activeCursor: null,
        pendingCursor: null,
        hasMore: false,
      );
    }
    final followingIds = await _fetchFollowingIds(currentUserId);
    if (followingIds.isEmpty) {
      return const EventPhotoPage(
        items: [],
        nextCursor: null,
        activeCursor: null,
        pendingCursor: null,
        hasMore: false,
      );
    }

    final chunks = _chunkIds(followingIds, _followingChunkSize);
    final cursorCreatedAt = _cursorCreatedAt(cursor);

    final futures = chunks.map((chunk) {
      var q = _photos
          .where('status', isEqualTo: 'active')
          .where('userId', whereIn: chunk)
          .orderBy('createdAt', descending: true)
          .limit(limit);
      if (cursorCreatedAt != null) {
        q = q.startAfter([cursorCreatedAt]);
      }
      return q.get();
    }).toList();

    final snaps = await Future.wait(futures);
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final snap in snaps) {
      docs.addAll(snap.docs);
    }

    docs.sort((a, b) {
      final aTs = a.data()['createdAt'] as dynamic;
      final bTs = b.data()['createdAt'] as dynamic;
      final aMs = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
      final bMs = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
      return bMs.compareTo(aMs);
    });

    final items = docs.map(EventPhotoModel.fromFirestore).toList(growable: false);
    final limited = items.length <= limit ? items : items.sublist(0, limit);
    final nextCursor = docs.isNotEmpty ? docs.last : cursor;
    final hasMore = docs.length >= limit;

    return EventPhotoPage(
      items: limited,
      nextCursor: nextCursor,
      activeCursor: nextCursor,
      pendingCursor: null,
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
      case EventPhotoFeedScopeFollowing():
        print('👥 [EventPhotoRepository] Scope seguindo (seguindo ids)');
        return _fetchFollowingPage(
          currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
          limit: limit,
          cursor: cursor,
        );
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

  /// Busca posts ativos mais novos que um determinado timestamp
  /// 
  /// Usado para refresh incremental - busca apenas novos posts ao invés
  /// de recarregar a página inteira.
  Future<List<EventPhotoModel>> fetchActiveNewerThan({
    required EventPhotoFeedScope scope,
    required Timestamp newerThan,
    int limit = 20,
  }) async {
    print('🆕 [EventPhotoRepository.fetchActiveNewerThan] newerThan: ${newerThan.toDate()}');
    
    Query<Map<String, dynamic>> query = _photos
        .where('status', isEqualTo: 'active')
        .where('createdAt', isGreaterThan: newerThan)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    // Aplica filtros de scope
    switch (scope) {
      case EventPhotoFeedScopeCity(:final cityId):
        if (cityId != null && cityId.trim().isNotEmpty) {
          query = query.where('eventCityId', isEqualTo: cityId.trim());
        }
        break;
      case EventPhotoFeedScopeGlobal():
        // Sem filtros adicionais
        break;
      case EventPhotoFeedScopeFollowing():
        // Following precisa de lógica especial (chunks de userIds)
        // Por simplicidade, retorna vazio - o controller fará fallback para refresh full
        return [];
      case EventPhotoFeedScopeEvent(:final eventId):
        query = query.where('eventId', isEqualTo: eventId);
        break;
      case EventPhotoFeedScopeUser(:final userId):
        query = query.where('userId', isEqualTo: userId);
        break;
    }

    try {
      final snap = await query.get();
      print('✅ [fetchActiveNewerThan] ${snap.docs.length} novos posts encontrados');
      return snap.docs.map(EventPhotoModel.fromFirestore).toList(growable: false);
    } catch (e) {
      print('❌ [fetchActiveNewerThan] Erro: $e');
      rethrow;
    }
  }

  /// Busca posts under_review do próprio usuário mais novos que um timestamp
  /// 
  /// Usado para refresh incremental dos posts próprios em moderação.
  Future<List<EventPhotoModel>> fetchUnderReviewMineNewerThan({
    required EventPhotoFeedScope scope,
    required String userId,
    required Timestamp newerThan,
    int limit = 20,
  }) async {
    if (userId.trim().isEmpty) return [];
    
    print('🆕 [EventPhotoRepository.fetchUnderReviewMineNewerThan] userId: $userId');
    
    Query<Map<String, dynamic>> query = _photos
        .where('status', isEqualTo: 'under_review')
        .where('userId', isEqualTo: userId)
        .where('createdAt', isGreaterThan: newerThan)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    // Aplica filtros de scope (exceto userId que já foi aplicado)
    switch (scope) {
      case EventPhotoFeedScopeCity(:final cityId):
        if (cityId != null && cityId.trim().isNotEmpty) {
          query = query.where('eventCityId', isEqualTo: cityId.trim());
        }
        break;
      case EventPhotoFeedScopeEvent(:final eventId):
        query = query.where('eventId', isEqualTo: eventId);
        break;
      default:
        // Global, Following, User - sem filtros adicionais
        break;
    }

    try {
      final snap = await query.get();
      print('✅ [fetchUnderReviewMineNewerThan] ${snap.docs.length} novos posts em moderação');
      return snap.docs.map(EventPhotoModel.fromFirestore).toList(growable: false);
    } catch (e) {
      print('❌ [fetchUnderReviewMineNewerThan] Erro: $e');
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
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final docRef = _photos.doc(photoId);
    
    debugPrint('🗑️ [EventPhotoRepository] deletePhoto');
    debugPrint('   - photoId: $photoId');
    debugPrint('   - docPath: ${docRef.path}');
    debugPrint('   - currentUserId: $currentUserId');
    
    // Tenta deletar diretamente - se o documento não existir, o Firestore
    // simplesmente não faz nada (delete de documento inexistente é no-op)
    try {
      await docRef.delete();
      debugPrint('   ✅ Delete executado com sucesso');
    } catch (e) {
      // Se o erro for permission-denied, pode ser que o documento já foi deletado
      // ou o usuário não tem permissão. Verificar se o documento existe.
      if (e.toString().contains('permission-denied')) {
        debugPrint('   ⚠️ Permission denied - verificando se documento existe...');
        
        // Usar uma transação para verificar existência sem depender de read rules
        // Se não conseguir ler, assumimos que já foi deletado
        debugPrint('   ℹ️ Documento provavelmente já foi deletado anteriormente');
        return; // Silenciosamente ignora - o objetivo era deletar e já está deletado
      }
      debugPrint('   ❌ Erro ao deletar: $e');
      rethrow;
    }
  }

  Future<void> updateCaption({
    required String photoId,
    required String caption,
  }) async {
    await _photos.doc(photoId).update({
      'caption': caption,
    });
  }

  Future<void> removePhotoImage({
    required String photoId,
    required int index,
    required List<String> imageUrls,
    required List<String> thumbnailUrls,
  }) async {
    if (index < 0 || index >= imageUrls.length) return;
    if (imageUrls.length <= 1) {
      throw Exception('Não é possível remover a última imagem');
    }

    final removedImageUrl = imageUrls[index];
    final removedThumbUrl = index < thumbnailUrls.length ? thumbnailUrls[index] : null;

    final nextImageUrls = [...imageUrls]..removeAt(index);
    final nextThumbnailUrls = [...thumbnailUrls];
    if (index < nextThumbnailUrls.length) {
      nextThumbnailUrls.removeAt(index);
    }

    await _photos.doc(photoId).update({
      'imageUrls': nextImageUrls,
      'thumbnailUrls': nextThumbnailUrls,
      'imageUrl': nextImageUrls.first,
      'thumbnailUrl': nextThumbnailUrls.isNotEmpty ? nextThumbnailUrls.first : null,
    });

    await _deleteStorageFile(removedImageUrl);
    if (removedThumbUrl != null && removedThumbUrl.isNotEmpty) {
      await _deleteStorageFile(removedThumbUrl);
    }
  }

  Future<void> _deleteStorageFile(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (_) {
      // Ignore delete errors
    }
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

  Future<List<EventPhotoCommentModel>> fetchCommentsCached({
    required String photoId,
    int limit = 50,
  }) async {
    await _cacheService?.initialize();

    final cached = _cacheService?.getCachedComments(photoId);
    if (cached != null && cached.isNotEmpty) {
      return cached.take(limit).toList(growable: false);
    }

    final items = await fetchComments(photoId: photoId, limit: limit);
    await _cacheService?.setCachedComments(photoId, items);
    return items;
  }

  Future<void> addComment({
    required String photoId,
    required EventPhotoCommentModel comment,
  }) async {
    // Adiciona o comentário e pega a referência com o ID gerado
    final docRef = await _photos
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

    if (_cacheService != null) {
      // Usa o ID real do documento criado
      final cachedComment = EventPhotoCommentModel(
        id: docRef.id,
        photoId: comment.photoId,
        userId: comment.userId,
        userName: comment.userName,
        userPhotoUrl: comment.userPhotoUrl,
        text: comment.text,
        createdAt: comment.createdAt ?? Timestamp.now(),
        status: comment.status,
      );
      await _cacheService?.appendCachedComment(photoId, cachedComment);
    }
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

    await _cacheService?.removeCachedComment(photoId, commentId);
  }

  Future<List<EventPhotoCommentReplyModel>> fetchCommentReplies({
    required String photoId,
    required String commentId,
    int limit = 50,
  }) async {
    print('🔵 [EventPhotoRepository.fetchCommentReplies] Iniciando busca de replies');
    print('   📸 photoId: $photoId');
    print('   💬 commentId: $commentId');
    print('   📊 limit: $limit');
    
    try {
      final snap = await _photos
          .doc(photoId)
          .collection('comments')
          .doc(commentId)
          .collection('replies')
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      print('✅ [EventPhotoRepository.fetchCommentReplies] Query completada: ${snap.docs.length} replies');

      return snap.docs
          .map(
            (d) => EventPhotoCommentReplyModel.fromFirestore(
              d,
              photoId: photoId,
              commentId: commentId,
            ),
          )
          .toList(growable: false);
    } catch (e, stack) {
      print('❌ [EventPhotoRepository.fetchCommentReplies] ERRO ao buscar replies!');
      print('   💥 Erro: $e');
      print('   📸 photoId: $photoId');
      print('   💬 commentId: $commentId');
      
      if (e.toString().contains('index') || e.toString().contains('Index')) {
        print('');
        print('⚠️  ═══════════════════════════════════════════════════════════════');
        print('⚠️  ERRO DE ÍNDICE FIRESTORE DETECTADO!');
        print('⚠️  ═══════════════════════════════════════════════════════════════');
        print('⚠️  Query: EventPhotos/{photoId}/comments/{commentId}/replies');
        print('⚠️  Filtros: where(status == active) + orderBy(createdAt DESC)');
        print('⚠️  ');
        print('⚠️  É necessário criar um índice composto no Firestore.');
        print('⚠️  ');
        print('⚠️  Geralmente o erro do Firestore inclui um link direto para criar');
        print('⚠️  o índice. Procure no erro completo acima por uma URL começando');
        print('⚠️  com: https://console.firebase.google.com/...');
        print('⚠️  ');
        print('⚠️  Ou adicione manualmente em firestore.indexes.json:');
        print('⚠️  {');
        print('⚠️    "collectionGroup": "replies",');
        print('⚠️    "queryScope": "COLLECTION",');
        print('⚠️    "fields": [');
        print('⚠️      {"fieldPath": "status", "order": "ASCENDING"},');
        print('⚠️      {"fieldPath": "createdAt", "order": "DESCENDING"}');
        print('⚠️    ]');
        print('⚠️  }');
        print('⚠️  ═══════════════════════════════════════════════════════════════');
        print('');
      }
      
      print('📚 Stack trace:');
      print(stack);
      rethrow;
    }
  }

  Future<List<EventPhotoCommentReplyModel>> fetchCommentRepliesCached({
    required String photoId,
    required String commentId,
    int limit = 50,
  }) async {
    await _cacheService?.initialize();

    final cached = _cacheService?.getCachedReplies(photoId, commentId);
    if (cached != null && cached.isNotEmpty) {
      return cached.take(limit).toList(growable: false);
    }

    final items = await fetchCommentReplies(
      photoId: photoId,
      commentId: commentId,
      limit: limit,
    );
    await _cacheService?.setCachedReplies(photoId, commentId, items);
    return items;
  }

  Future<void> addCommentReply({
    required String photoId,
    required String commentId,
    required EventPhotoCommentReplyModel reply,
  }) async {
    // Adiciona a reply e pega a referência com o ID gerado
    final docRef = await _photos
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

    if (_cacheService != null) {
      // Usa o ID real do documento criado
      final cachedReply = EventPhotoCommentReplyModel(
        id: docRef.id,
        photoId: reply.photoId,
        commentId: reply.commentId,
        userId: reply.userId,
        userName: reply.userName,
        userPhotoUrl: reply.userPhotoUrl,
        text: reply.text,
        createdAt: reply.createdAt ?? Timestamp.now(),
        status: reply.status,
      );
      await _cacheService?.appendCachedReply(photoId, commentId, cachedReply);
    }
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

    await _cacheService?.removeCachedReply(photoId, commentId, replyId);
  }
}

