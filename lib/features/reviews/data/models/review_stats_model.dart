import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';

/// Modelo de estatísticas agregadas de reviews (cache)
class ReviewStatsModel {
  final String userId;
  final int totalReviews;
  final double overallRating;

  // Média por critério
  final Map<String, double> ratingsBreakdown;

  // Contagem de badges recebidos
  final Map<String, int> badgesCount;

  // Reviews recentes
  final int last30DaysCount;
  final int last90DaysCount;

  final DateTime lastUpdated;

  const ReviewStatsModel({
    required this.userId,
    required this.totalReviews,
    required this.overallRating,
    required this.ratingsBreakdown,
    required this.badgesCount,
    required this.last30DaysCount,
    required this.last90DaysCount,
    required this.lastUpdated,
  });

  /// Cria instância a partir de documento Firestore
  factory ReviewStatsModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse ratingsBreakdown
    final ratingsData = data['ratings_breakdown'] as Map<String, dynamic>? ?? {};
    final ratingsBreakdown = ratingsData.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );

    // Parse badgesCount
    final badgesData = data['badges_count'] as Map<String, dynamic>? ?? {};
    final badgesCount = badgesData.map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );

    return ReviewStatsModel(
      userId: doc.id,
      totalReviews: data['total_reviews'] as int? ?? 0,
      overallRating: (data['overall_rating'] as num?)?.toDouble() ?? 0.0,
      ratingsBreakdown: ratingsBreakdown,
      badgesCount: badgesCount,
      last30DaysCount: data['last_30_days_count'] as int? ?? 0,
      last90DaysCount: data['last_90_days_count'] as int? ?? 0,
      lastUpdated: (data['last_updated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Converte para Map para salvar no Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'user_id': userId,
      'total_reviews': totalReviews,
      'overall_rating': overallRating,
      'ratings_breakdown': ratingsBreakdown,
      'badges_count': badgesCount,
      'last_30_days_count': last30DaysCount,
      'last_90_days_count': last90DaysCount,
      'last_updated': Timestamp.fromDate(lastUpdated),
    };
  }

  /// Calcula estatísticas a partir de uma lista de reviews
  static ReviewStatsModel calculate(String userId, List<ReviewModel> reviews) {
    if (reviews.isEmpty) {
      return ReviewStatsModel(
        userId: userId,
        totalReviews: 0,
        overallRating: 0,
        ratingsBreakdown: {},
        badgesCount: {},
        last30DaysCount: 0,
        last90DaysCount: 0,
        lastUpdated: DateTime.now(),
      );
    }

    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));

    // Calcula overall rating
    double totalRating = 0;
    for (final review in reviews) {
      totalRating += review.overallRating;
    }
    final overallRating = totalRating / reviews.length;

    // Calcula breakdown por critério
    final Map<String, List<int>> criteriaValues = {};
    for (final review in reviews) {
      for (final entry in review.criteriaRatings.entries) {
        criteriaValues.putIfAbsent(entry.key, () => []).add(entry.value);
      }
    }

    final ratingsBreakdown = criteriaValues.map((key, values) {
      final sum = values.reduce((a, b) => a + b);
      return MapEntry(key, sum / values.length);
    });

    // Conta badges
    final Map<String, int> badgesCount = {};
    for (final review in reviews) {
      for (final badge in review.badges) {
        badgesCount[badge] = (badgesCount[badge] ?? 0) + 1;
      }
    }

    // Conta reviews recentes
    int last30DaysCount = 0;
    int last90DaysCount = 0;
    for (final review in reviews) {
      if (review.createdAt.isAfter(thirtyDaysAgo)) {
        last30DaysCount++;
      }
      if (review.createdAt.isAfter(ninetyDaysAgo)) {
        last90DaysCount++;
      }
    }

    return ReviewStatsModel(
      userId: userId,
      totalReviews: reviews.length,
      overallRating: double.parse(overallRating.toStringAsFixed(1)),
      ratingsBreakdown: ratingsBreakdown.map(
        (key, value) => MapEntry(key, double.parse(value.toStringAsFixed(1))),
      ),
      badgesCount: badgesCount,
      last30DaysCount: last30DaysCount,
      last90DaysCount: last90DaysCount,
      lastUpdated: DateTime.now(),
    );
  }

  /// Badge mais recebido
  String? get topBadge {
    if (badgesCount.isEmpty) return null;

    final sorted = badgesCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.first.key;
  }

  /// Verifica se tem reviews
  bool get hasReviews => totalReviews > 0;

  ReviewStatsModel copyWith({
    String? userId,
    int? totalReviews,
    double? overallRating,
    Map<String, double>? ratingsBreakdown,
    Map<String, int>? badgesCount,
    int? last30DaysCount,
    int? last90DaysCount,
    DateTime? lastUpdated,
  }) {
    return ReviewStatsModel(
      userId: userId ?? this.userId,
      totalReviews: totalReviews ?? this.totalReviews,
      overallRating: overallRating ?? this.overallRating,
      ratingsBreakdown: ratingsBreakdown ?? this.ratingsBreakdown,
      badgesCount: badgesCount ?? this.badgesCount,
      last30DaysCount: last30DaysCount ?? this.last30DaysCount,
      last90DaysCount: last90DaysCount ?? this.last90DaysCount,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
