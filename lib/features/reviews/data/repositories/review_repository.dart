import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';
import 'package:partiu/features/reviews/data/models/pending_review_model.dart';
import 'package:partiu/features/reviews/data/models/review_stats_model.dart';

/// Repository para gerenciar reviews no Firestore
class ReviewRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ==================== PENDING REVIEWS ====================

  /// Busca reviews pendentes do usuário atual
  Future<List<PendingReviewModel>> getPendingReviews() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('Usuário não autenticado');
    }

    final now = Timestamp.now();

    final snapshot = await _firestore
        .collection('PendingReviews')
        .where('reviewer_id', isEqualTo: userId)
        .where('dismissed', isEqualTo: false)
        .where('expires_at', isGreaterThan: now)
        .orderBy('expires_at')
        .orderBy('created_at', descending: true)
        .limit(20)
        .get();

    // Filtra reviews já submetidos
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

    // Conta apenas os que não foram submetidos
    int count = 0;
    for (final doc in snapshot.docs) {
      final pending = PendingReviewModel.fromFirestore(doc);

      final existingReview = await _firestore
          .collection('Reviews')
          .where('reviewer_id', isEqualTo: userId)
          .where('reviewee_id', isEqualTo: pending.revieweeId)
          .where('event_id', isEqualTo: pending.eventId)
          .limit(1)
          .get();

      if (existingReview.docs.isEmpty) {
        count++;
      }
    }

    return count;
  }

  /// Marca pending review como dismissed
  Future<void> dismissPendingReview(String pendingReviewId) async {
    await _firestore.collection('PendingReviews').doc(pendingReviewId).update({
      'dismissed': true,
      'dismissed_at': FieldValue.serverTimestamp(),
    });
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
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('Usuário não autenticado');
    }

    // Verifica duplicata
    final existing = await _firestore
        .collection('Reviews')
        .where('reviewer_id', isEqualTo: userId)
        .where('reviewee_id', isEqualTo: revieweeId)
        .where('event_id', isEqualTo: eventId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('Você já avaliou esta pessoa neste evento');
    }

    // Busca dados do reviewer
    final userDoc = await _firestore.collection('Users').doc(userId).get();
    final userData = userDoc.data();

    // Calcula overall rating
    final overallRating = ReviewModel.calculateOverallRating(criteriaRatings);

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
      reviewerPhotoUrl: userData?['user_photo_link'] as String?,
    );

    // Salva no Firestore
    await _firestore.collection('Reviews').add(review.toFirestore());

    // Atualiza stats do reviewee
    await _updateReviewStats(revieweeId);

    // Remove pending review
    await _removePendingReview(userId, revieweeId, eventId);
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

  /// Busca estatísticas de reviews
  Future<ReviewStatsModel?> getReviewStats(String userId) async {
    final doc =
        await _firestore.collection('ReviewStats').doc(userId).get();

    if (!doc.exists) {
      // Calcula pela primeira vez
      await _updateReviewStats(userId);
      final recalculatedDoc =
          await _firestore.collection('ReviewStats').doc(userId).get();

      if (recalculatedDoc.exists) {
        return ReviewStatsModel.fromFirestore(recalculatedDoc);
      }
      return null;
    }

    return ReviewStatsModel.fromFirestore(doc);
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
  Stream<List<ReviewModel>> watchUserReviews(String userId, {int limit = 10}) {
    return _firestore
        .collection('Reviews')
        .where('reviewee_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ReviewModel.fromFirestore(doc))
            .toList());
  }

  /// Stream de estatísticas de reviews de um usuário
  Stream<ReviewStatsModel> watchUserStats(String userId) {
    return _firestore
        .collection('ReviewStats')
        .doc(userId)
        .snapshots()
        .asyncMap((doc) async {
          if (!doc.exists) {
            // Calcula pela primeira vez
            await _updateReviewStats(userId);
            final recalculatedDoc =
                await _firestore.collection('ReviewStats').doc(userId).get();

            if (recalculatedDoc.exists) {
              return ReviewStatsModel.fromFirestore(recalculatedDoc);
            }
            // Retorna stats vazias se ainda não há reviews
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

          return ReviewStatsModel.fromFirestore(doc);
        });
  }

  // ==================== PRIVATE HELPERS ====================

  Future<void> _updateReviewStats(String userId) async {
    final reviewsSnapshot = await _firestore
        .collection('Reviews')
        .where('reviewee_id', isEqualTo: userId)
        .get();

    if (reviewsSnapshot.docs.isEmpty) {
      // Sem reviews ainda
      return;
    }

    final reviews = reviewsSnapshot.docs
        .map((doc) => ReviewModel.fromFirestore(doc))
        .toList();

    // Calcula estatísticas
    final stats = ReviewStatsModel.calculate(userId, reviews);

    // Salva no Firestore
    await _firestore
        .collection('ReviewStats')
        .doc(userId)
        .set(stats.toFirestore(), SetOptions(merge: true));
  }

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
}
