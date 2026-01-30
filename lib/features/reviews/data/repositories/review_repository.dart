import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';
import 'package:partiu/features/reviews/data/models/pending_review_model.dart';
import 'package:partiu/features/reviews/data/models/review_stats_model.dart';
import 'package:partiu/features/reviews/data/services/review_page_cache_service.dart';
import 'package:partiu/features/reviews/data/services/review_stats_cache_service.dart';
import 'package:partiu/features/reviews/presentation/services/pending_reviews_listener_service.dart';
import 'package:partiu/features/reviews/data/repositories/actions_repository.dart';

/// Repository para gerenciar reviews no Firestore
class ReviewRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ActionsRepository _actionsRepo = ActionsRepository();
  final ReviewPageCacheService _reviewsCache = ReviewPageCacheService.instance;
  final ReviewStatsCacheService _statsCache = ReviewStatsCacheService.instance;

  // ==================== PENDING REVIEWS ====================

  /// Busca reviews pendentes do usuário atual
  /// 
  /// Retorna apenas reviews que:
  /// - Ainda não expiraram
  /// - Não foram dismissed
  /// - Pertencem ao usuário logado
  Future<List<PendingReviewModel>> getPendingReviews() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('Usuário não autenticado');
    }

    final now = Timestamp.now();

    // Query simplificada - apenas os filtros essenciais
    final snapshot = await _firestore
        .collection('PendingReviews')
        .where('reviewer_id', isEqualTo: userId)
        .where('dismissed', isEqualTo: false)
        .where('expires_at', isGreaterThan: now)
        .orderBy('expires_at')
        .orderBy('created_at', descending: true)
        .limit(20)
        .get();

    // Converte diretamente sem verificação extra
    // (A verificação de duplicata será feita no momento do submit)
    return snapshot.docs
        .map((doc) => PendingReviewModel.fromFirestore(doc))
        .toList();
  }

  /// Stream de reviews pendentes (para ActionsTab)
  Stream<List<PendingReviewModel>> getPendingReviewsStream() {
    final controller = StreamController<List<PendingReviewModel>>();

    final userId = _auth.currentUser?.uid;
    debugPrint('🔍 [ReviewRepository] getPendingReviewsStream');
    debugPrint('   - userId: $userId');

    if (userId == null) {
      debugPrint('   ❌ userId é null, retornando stream vazio');
      controller.add([]);
      controller.close();
      return controller.stream;
    }

    final now = Timestamp.now();
    debugPrint('   - now: ${now.toDate()}');

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
    StreamSubscription<User?>? authSub;

    void stop() {
      sub?.cancel();
      sub = null;
      authSub?.cancel();
      authSub = null;

      if (!controller.isClosed) {
        controller.add([]);
        controller.close();
      }
    }

    authSub = _auth.authStateChanges().listen((user) {
      if (user != null) return;
      stop();
    });

    sub = _firestore
        .collection('PendingReviews')
        .where('reviewer_id', isEqualTo: userId)
        .where('dismissed', isEqualTo: false)
        .where('expires_at', isGreaterThan: now)
        .orderBy('expires_at')
        .orderBy('created_at', descending: true)
        .limit(20)
        .snapshots()
        .listen(
      (snapshot) async {
        if (controller.isClosed) return;

        try {
          debugPrint('📦 [ReviewRepository] Stream snapshot recebido: ${snapshot.docs.length} docs');

          if (snapshot.docs.isEmpty) {
            debugPrint('   ✅ Nenhum review, retornando lista vazia');
            controller.add([]);
            return;
          }

          final reviews = snapshot.docs
              .map((doc) => PendingReviewModel.fromFirestore(doc))
              .toList();

          final eventIds = reviews.map((r) => r.eventId).toSet().toList();
          debugPrint('🔍 [ReviewRepository] Buscando dados de ${eventIds.length} eventos');

          final ownersData = await _actionsRepo.getMultipleEventOwnersData(eventIds);

          final enrichedReviews = reviews.map((review) {
            if (review.reviewerRole == 'participant') {
              final ownerData = ownersData[review.eventId];

              if (ownerData != null) {
                debugPrint('✅ [ReviewRepository] Enriquecendo review PARTICIPANT ${review.pendingReviewId} com owner: ${ownerData['fullName']}');
                return review.copyWith(
                  revieweeId: ownerData['userId'] as String,
                  revieweeName: ownerData['fullName'] as String,
                  revieweePhotoUrl: ownerData['photoUrl'] as String?,
                );
              }

              debugPrint('⚠️ [ReviewRepository] Owner não encontrado para evento ${review.eventId}');
              return review;
            }

            debugPrint('✅ [ReviewRepository] Mantendo review OWNER ${review.pendingReviewId} com revieweeId original: ${review.revieweeId}');
            return review;
          }).toList();

          final validReviews = enrichedReviews.where((review) {
            if (review.reviewerId == review.revieweeId) {
              debugPrint('❌ [ReviewRepository] BLOQUEADO: Autoavaliação detectada!');
              debugPrint('   - pendingReviewId: ${review.pendingReviewId}');
              debugPrint('   - reviewerId: ${review.reviewerId}');
              debugPrint('   - revieweeId: ${review.revieweeId}');
              return false;
            }
            return true;
          }).toList();

          debugPrint('   ✅ Retornando ${validReviews.length} reviews válidos (${enrichedReviews.length - validReviews.length} autoavaliações bloqueadas)');
          controller.add(validReviews);
        } catch (e) {
          debugPrint('❌ [ReviewRepository] Erro ao processar snapshot: $e');
          controller.add([]);
        }
      },
      onError: (error) {
        final isPermissionDenied =
            error is FirebaseException && error.code == 'permission-denied';
        final isLoggedOut = _auth.currentUser == null;

        if (isPermissionDenied && isLoggedOut) {
          stop();
          return;
        }

        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
    );

    controller.onCancel = () {
      sub?.cancel();
      authSub?.cancel();
    };

    return controller.stream;
  }

  /// Busca count de reviews pendentes (para badge)
  Future<int> getPendingReviewsCount() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return 0;

    final now = Timestamp.now();

    final snapshot = await _firestore
        .collection('PendingReviews')
        .where('reviewer_id', isEqualTo: userId)
        .where('dismissed', isEqualTo: false)
        .where('expires_at', isGreaterThan: now)
        .get();

    return snapshot.docs.length;
  }

  /// Marca pending review como dismissed
  Future<void> dismissPendingReview(String pendingReviewId) async {
    await _firestore.collection('PendingReviews').doc(pendingReviewId).update({
      'dismissed': true,
      'dismissed_at': FieldValue.serverTimestamp(),
    });
    
    // Notifica o listener para remover do cache local
    PendingReviewsListenerService.instance.clearPendingReview(pendingReviewId);
  }

  /// Atualiza PendingReview (ex: presenceConfirmed)
  Future<void> updatePendingReview({
    required String pendingReviewId,
    required Map<String, dynamic> data,
  }) async {
    debugPrint('🔍 [ReviewRepository] updatePendingReview');
    debugPrint('   - pendingReviewId: $pendingReviewId');
    debugPrint('   - data: $data');
    
    try {
      await _firestore
          .collection('PendingReviews')
          .doc(pendingReviewId)
          .update(data);
      debugPrint('   ✅ PendingReview atualizado com sucesso');
    } catch (e, stack) {
      debugPrint('   ❌ Erro ao atualizar PendingReview: $e');
      debugPrint('   Stack trace: $stack');
      rethrow;
    }
  }

  /// Salva participante confirmado na subcoleção do evento
  Future<void> saveConfirmedParticipant({
    required String eventId,
    required String participantId,
    required String confirmedBy,
  }) async {
    debugPrint('🔍 [ReviewRepository] saveConfirmedParticipant');
    debugPrint('   - eventId: $eventId');
    debugPrint('   - participantId: $participantId');
    debugPrint('   - confirmedBy: $confirmedBy');
    
    try {
      await _firestore
          .collection('events')
          .doc(eventId)
          .collection('ConfirmedParticipants')
          .doc(participantId)
          .set({
        'confirmed_at': FieldValue.serverTimestamp(),
        'confirmed_by': confirmedBy,
        'presence': 'Vou',
        'reviewed': false,
      });
      debugPrint('   ✅ Participante confirmado salvo com sucesso');
    } catch (e, stack) {
      debugPrint('   ❌ Erro ao salvar participante confirmado: $e');
      debugPrint('   Stack trace: $stack');
      rethrow;
    }
  }

  /// Marca participante como avaliado
  Future<void> markParticipantAsReviewed({
    required String eventId,
    required String participantId,
  }) async {
    await _firestore
        .collection('events')
        .doc(eventId)
        .collection('ConfirmedParticipants')
        .doc(participantId)
        .update({'reviewed': true});
  }

  /// Cria PendingReview para participante avaliar owner
  Future<void> createParticipantPendingReview({
    required String eventId,
    required String participantId,
    required String ownerId,
    required String ownerName,
    required String? ownerPhotoUrl,
    required String eventTitle,
    required String eventEmoji,
    required String? eventLocationName,
    required DateTime? eventScheduleDate,
  }) async {
    final pendingReviewId = '${eventId}_participant_$participantId';
    final expiresAt = DateTime.now().add(const Duration(days: 30));

    await _firestore.collection('PendingReviews').doc(pendingReviewId).set({
      'pending_review_id': pendingReviewId,
      'event_id': eventId,
      'application_id': '',
      'reviewer_id': participantId,
      'reviewee_id': ownerId,
      'reviewee_name': ownerName,
      'reviewee_photo_url': ownerPhotoUrl,
      'reviewer_role': 'participant',
      'event_title': eventTitle,
      'event_emoji': eventEmoji,
      'event_location': eventLocationName,
      'event_date': eventScheduleDate != null
          ? Timestamp.fromDate(eventScheduleDate)
          : FieldValue.serverTimestamp(),
      'allowed_to_review_owner': true,
      'created_at': FieldValue.serverTimestamp(),
      'expires_at': Timestamp.fromDate(expiresAt),
      'dismissed': false,
    });
  }

  /// Deleta PendingReview
  Future<void> deletePendingReview(String pendingReviewId) async {
    await _firestore
        .collection('PendingReviews')
        .doc(pendingReviewId)
        .delete();
    
    // Notifica o listener
    PendingReviewsListenerService.instance.clearPendingReview(pendingReviewId);
  }

  // ==================== REVIEWS ====================

  /// Cria uma nova review
  Future<void> createReview({
    required String eventId,
    required String revieweeId,
    required String reviewerRole,
    required Map<String, int> criteriaRatings,
    List<String> badges = const [],
    String? comment,
    String? pendingReviewId,
  }) async {
    debugPrint('🔍 [createReview] Iniciando...');
    debugPrint('   eventId: $eventId');
    debugPrint('   revieweeId: $revieweeId');
    debugPrint('   reviewerRole: $reviewerRole');
    debugPrint('   criteriaRatings: $criteriaRatings');
    debugPrint('   pendingReviewId: $pendingReviewId');
    
    final userId = _auth.currentUser?.uid;
    debugPrint('   userId (reviewer): $userId');
    
    if (userId == null) {
      debugPrint('❌ [createReview] Usuário não autenticado');
      throw Exception('Usuário não autenticado');
    }

    // VALIDAÇÃO CRÍTICA: Bloquear autoavaliação
    if (userId == revieweeId) {
      debugPrint('❌ [createReview] BLOQUEADO: Tentativa de autoavaliação!');
      debugPrint('   reviewerId: $userId');
      debugPrint('   revieweeId: $revieweeId');
      throw Exception('Você não pode avaliar a si mesmo');
    }

    // Verifica duplicata
    debugPrint('🔍 [createReview] Verificando duplicata...');
    final existing = await _firestore
        .collection('Reviews')
        .where('reviewer_id', isEqualTo: userId)
        .where('reviewee_id', isEqualTo: revieweeId)
        .where('event_id', isEqualTo: eventId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      debugPrint('❌ [createReview] Review duplicado encontrado');
      throw Exception('Você já avaliou esta pessoa neste evento');
    }
    debugPrint('   ✅ Nenhum duplicado encontrado');

    // Busca dados do reviewer
    debugPrint('🔍 [createReview] Buscando dados do reviewer...');
    final userDoc = await _firestore.collection('Users').doc(userId).get();
    final userData = userDoc.data();
    debugPrint('   reviewerName: ${userData?['fullname']}');
    debugPrint('   reviewerPhotoUrl: ${userData?['photoUrl']}');

    // Calcula overall rating
    final overallRating = ReviewModel.calculateOverallRating(criteriaRatings);
    debugPrint('   overallRating calculado: $overallRating');

    // Cria review
    final now = DateTime.now();
    final review = ReviewModel(
      reviewId: '', // Será preenchido após criação
      eventId: eventId,
      reviewerId: userId,
      revieweeId: revieweeId,
      reviewerRole: reviewerRole,
      criteriaRatings: criteriaRatings,
      overallRating: overallRating,
      badges: badges,
      comment: comment?.trim().isEmpty == true ? null : comment?.trim(),
      createdAt: now,
      updatedAt: now,
      reviewerName: userData?['fullname'] as String?,
      reviewerPhotoUrl: userData?['photoUrl'] as String?,
    );

    // Converte para Firestore e loga
    final firestoreData = review.toFirestore();
    debugPrint('📤 [createReview] Dados a serem salvos no Firestore:');
    debugPrint('   ${firestoreData.toString()}');
    
    // Validação final de segurança
    if (firestoreData['reviewer_id'] != userId) {
      debugPrint('❌ [createReview] ERRO CRÍTICO: reviewer_id não corresponde ao userId autenticado!');
      debugPrint('   reviewer_id no documento: ${firestoreData['reviewer_id']}');
      debugPrint('   userId autenticado: $userId');
      throw Exception('Erro de segurança: reviewer_id inválido');
    }

    // Salva no Firestore
    debugPrint('💾 [createReview] Salvando no Firestore...');
    try {
      await _firestore.collection('Reviews').add(firestoreData);
      debugPrint('   ✅ Review salvo com sucesso');
    } catch (e, stack) {
      debugPrint('❌ [createReview] ERRO ao salvar no Firestore: $e');
      debugPrint('   Stack trace: $stack');
      rethrow;
    }

    // Remove pending review
    if (pendingReviewId != null && pendingReviewId.isNotEmpty) {
      debugPrint('🗑️ [createReview] Removendo PendingReview: $pendingReviewId');
      await _removePendingReviewById(pendingReviewId);
      // Notifica o listener
      PendingReviewsListenerService.instance.clearPendingReview(pendingReviewId);
    } else {
      debugPrint('🗑️ [createReview] Removendo PendingReview por query');
      await _removePendingReview(userId, revieweeId, eventId);
    }
    
    debugPrint('✅ [createReview] Processo completo!');
  }

  /// Busca reviews de um usuário
  Future<List<ReviewModel>> getUserReviews(
    String userId, {
    int limit = 10,
    DocumentSnapshot? startAfter,
  }) async {
    Query query = _firestore
        .collection('Reviews')
        .where('reviewee_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();

    return snapshot.docs.map((doc) => ReviewModel.fromFirestore(doc)).toList();
  }

  /// Busca estatísticas de reviews (calculadas dinamicamente)
  Future<ReviewStatsModel?> getReviewStats(String userId) async {
    final reviewsSnapshot = await _firestore
        .collection('Reviews')
        .where('reviewee_id', isEqualTo: userId)
        .get();

    if (reviewsSnapshot.docs.isEmpty) {
      return null;
    }

    final reviews = reviewsSnapshot.docs
        .map((doc) => ReviewModel.fromFirestore(doc))
        .toList();

    // Calcula estatísticas dinamicamente
    return ReviewStatsModel.calculate(userId, reviews);
  }

  /// Stream de reviews pendentes (para atualização em tempo real)
  Stream<List<PendingReviewModel>> watchPendingReviews() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return Stream.value([]);
    }

    final now = Timestamp.now();

    return _firestore
        .collection('PendingReviews')
        .where('reviewer_id', isEqualTo: userId)
        .where('dismissed', isEqualTo: false)
        .where('expires_at', isGreaterThan: now)
        .orderBy('expires_at')
        .orderBy('created_at', descending: true)
        .limit(20)
        .snapshots()
        .asyncMap((snapshot) async {
      final pendingReviews = <PendingReviewModel>[];

      for (final doc in snapshot.docs) {
        final pending = PendingReviewModel.fromFirestore(doc);

        // Verifica se já existe review
        final existingReview = await _firestore
            .collection('Reviews')
            .where('reviewer_id', isEqualTo: userId)
            .where('reviewee_id', isEqualTo: pending.revieweeId)
            .where('event_id', isEqualTo: pending.eventId)
            .limit(1)
            .get();

        if (existingReview.docs.isEmpty) {
          pendingReviews.add(pending);
        }
      }

      return pendingReviews;
    });
  }

  /// Stream de reviews de um usuário (para atualização em tempo real)
  Stream<List<ReviewModel>> watchUserReviews(
    String userId, {
    int limit = 10,
    int page = 0,
    bool useCache = true,
  }) async* {
    if (useCache && page == 0) {
      await _reviewsCache.ensureInitialized();
      final cached = _reviewsCache.getPage(userId, page);
      if (cached != null && cached.isNotEmpty) {
        yield cached;
      }
    }

    final query = _firestore
        .collection('Reviews')
        .where('reviewee_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .limit(limit);

    await for (final snapshot in query.snapshots()) {
      final reviews = snapshot.docs
          .map((doc) => ReviewModel.fromFirestore(doc))
          .toList(growable: false);

      if (useCache && page == 0) {
        await _reviewsCache.putPage(userId, page, reviews);
      }

      yield reviews;
    }
  }

  /// Stream de estatísticas de reviews de um usuário
  ///
  /// ✅ Usa users_stats (ou Users) para evitar leitura de N reviews.
  Stream<ReviewStatsModel> watchUserStats(String userId) async* {
    debugPrint('🔍 [ReviewRepository] Iniciando watchUserStats para userId: ${userId.substring(0, 8)}...');

    await _statsCache.ensureInitialized();
    final cached = _statsCache.get(userId);
    if (cached != null && cached.isNotEmpty) {
      yield _buildStatsFromData(userId, cached);
    }

    var didFallbackUsers = false;

    await for (final statsDoc
        in _firestore.collection('users_stats').doc(userId).snapshots()) {
      try {
        final statsData = statsDoc.data();
        if (statsData != null) {
          await _statsCache.put(userId, statsData);
          yield _buildStatsFromData(userId, statsData);
          continue;
        }

        if (!didFallbackUsers) {
          didFallbackUsers = true;
          final userDoc = await _firestore.collection('Users').doc(userId).get();
          final userData = userDoc.data();
          if (userData != null) {
            await _statsCache.put(userId, userData);
            yield _buildStatsFromData(userId, userData);
            continue;
          }
        }

        yield _emptyStats(userId);
      } catch (e, stackTrace) {
        debugPrint('  ❌ ERRO em watchUserStats: $e');
        debugPrint('  Stack: $stackTrace');
        yield _emptyStats(userId);
      }
    }
  }

  ReviewStatsModel _buildStatsFromData(String userId, Map<String, dynamic> data) {
    final totalReviews = (data['totalReviews'] as num?)?.toInt() ??
        (data['total_reviews'] as num?)?.toInt() ??
        0;
    final overallRating = (data['overallRating'] as num?)?.toDouble() ??
        (data['overall_rating'] as num?)?.toDouble() ??
        0.0;

    final ratingsRaw = data['ratingBuckets'] ??
        data['ratingsBreakdown'] ??
        data['ratings_breakdown'];
    final ratingsBreakdown = <String, double>{};
    if (ratingsRaw is Map) {
      for (final entry in ratingsRaw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is num) {
          ratingsBreakdown[key] = value.toDouble();
        }
      }
    }

    final badgesRaw = data['badgesCount'] ?? data['badges_count'];
    final badgesCount = <String, int>{};
    if (badgesRaw is Map) {
      for (final entry in badgesRaw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is num) {
          badgesCount[key] = value.toInt();
        }
      }
    }

    final lastUpdated = _parseDateTime(
          data['lastReviewAt'] ?? data['lastUpdated'] ?? data['last_updated'],
        ) ??
        DateTime.now();

    return ReviewStatsModel(
      userId: userId,
      totalReviews: totalReviews,
      overallRating: overallRating,
      ratingsBreakdown: ratingsBreakdown,
      badgesCount: badgesCount,
      last30DaysCount: 0,
      last90DaysCount: 0,
      lastUpdated: lastUpdated,
    );
  }

  ReviewStatsModel _emptyStats(String userId) {
    return ReviewStatsModel(
      userId: userId,
      totalReviews: 0,
      overallRating: 0.0,
      ratingsBreakdown: {},
      badgesCount: {},
      last30DaysCount: 0,
      last90DaysCount: 0,
      lastUpdated: DateTime.now(),
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  // ==================== PRIVATE HELPERS ====================

  Future<void> _removePendingReview(
    String reviewerId,
    String revieweeId,
    String eventId,
  ) async {
    final snapshot = await _firestore
        .collection('PendingReviews')
        .where('reviewer_id', isEqualTo: reviewerId)
        .where('reviewee_id', isEqualTo: revieweeId)
        .where('event_id', isEqualTo: eventId)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      await snapshot.docs.first.reference.delete();
    }
  }

  /// Remove pending review por ID direto
  Future<void> _removePendingReviewById(String pendingReviewId) async {
    try {
      await _firestore
          .collection('PendingReviews')
          .doc(pendingReviewId)
          .delete();
    } catch (e) {
      // Falha silenciosa - o documento pode já ter sido deletado
    }
  }
}
