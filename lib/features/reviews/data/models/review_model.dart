import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de review (avaliação completa)
class ReviewModel {
  final String reviewId;
  final String eventId;
  final String reviewerId;
  final String revieweeId;
  final String reviewerRole; // 'owner' | 'participant'

  // Ratings por critério (1-5 estrelas)
  final Map<String, int> criteriaRatings;
  final double overallRating; // Média automática

  // Badges opcionais
  final List<String> badges;

  // Comentário opcional
  final String? comment;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;

  // Dados do reviewer (para exibição)
  final String? reviewerName;
  final String? reviewerPhotoUrl;

  const ReviewModel({
    required this.reviewId,
    required this.eventId,
    required this.reviewerId,
    required this.revieweeId,
    required this.reviewerRole,
    required this.criteriaRatings,
    required this.overallRating,
    this.badges = const [],
    this.comment,
    required this.createdAt,
    required this.updatedAt,
    this.reviewerName,
    this.reviewerPhotoUrl,
  });

  /// Cria instância a partir de documento Firestore
  factory ReviewModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse criteriaRatings
    final criteriaRatingsData = data['criteria_ratings'] as Map<String, dynamic>? ?? {};
    final criteriaRatings = criteriaRatingsData.map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );

    // Parse badges
    final badgesData = data['badges'] as List<dynamic>?;
    final badges = badgesData?.map((e) => e.toString()).toList() ?? [];

    return ReviewModel(
      reviewId: doc.id,
      eventId: data['event_id'] as String,
      reviewerId: data['reviewer_id'] as String,
      revieweeId: data['reviewee_id'] as String,
      reviewerRole: data['reviewer_role'] as String,
      criteriaRatings: criteriaRatings,
      overallRating: (data['overall_rating'] as num).toDouble(),
      badges: badges,
      comment: data['comment'] as String?,
      createdAt: (data['created_at'] as Timestamp).toDate(),
      updatedAt: (data['updated_at'] as Timestamp).toDate(),
      reviewerName: data['reviewer_name'] as String?,
      reviewerPhotoUrl: data['reviewer_photo_url'] as String?,
    );
  }

  /// Converte para Map para salvar no Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'event_id': eventId,
      'reviewer_id': reviewerId,
      'reviewee_id': revieweeId,
      'reviewer_role': reviewerRole,
      'criteria_ratings': criteriaRatings,
      'overall_rating': overallRating,
      'badges': badges,
      if (comment != null && comment!.isNotEmpty) 'comment': comment,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      if (reviewerName != null) 'reviewer_name': reviewerName,
      if (reviewerPhotoUrl != null) 'reviewer_photo_url': reviewerPhotoUrl,
    };
  }

  /// Calcula média dos ratings
  static double calculateOverallRating(Map<String, int> ratings) {
    if (ratings.isEmpty) return 0;

    final sum = ratings.values.reduce((a, b) => a + b);
    return sum / ratings.length;
  }

  /// Verifica se tem badges
  bool get hasBadges => badges.isNotEmpty;

  /// Verifica se tem comentário
  bool get hasComment => comment != null && comment!.isNotEmpty;

  /// Verifica se é owner avaliando participante
  bool get isOwnerReview => reviewerRole == 'owner';

  /// Verifica se é participante avaliando owner
  bool get isParticipantReview => reviewerRole == 'participant';

  ReviewModel copyWith({
    String? reviewId,
    String? eventId,
    String? reviewerId,
    String? revieweeId,
    String? reviewerRole,
    Map<String, int>? criteriaRatings,
    double? overallRating,
    List<String>? badges,
    String? comment,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? reviewerName,
    String? reviewerPhotoUrl,
  }) {
    return ReviewModel(
      reviewId: reviewId ?? this.reviewId,
      eventId: eventId ?? this.eventId,
      reviewerId: reviewerId ?? this.reviewerId,
      revieweeId: revieweeId ?? this.revieweeId,
      reviewerRole: reviewerRole ?? this.reviewerRole,
      criteriaRatings: criteriaRatings ?? this.criteriaRatings,
      overallRating: overallRating ?? this.overallRating,
      badges: badges ?? this.badges,
      comment: comment ?? this.comment,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reviewerName: reviewerName ?? this.reviewerName,
      reviewerPhotoUrl: reviewerPhotoUrl ?? this.reviewerPhotoUrl,
    );
  }
}
