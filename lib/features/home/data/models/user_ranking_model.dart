/// Modelo de ranking de usuário
/// 
/// Combina dados de review com dados do usuário
class UserRankingModel {
  const UserRankingModel({
    required this.userId,
    required this.fullName,
    required this.photoUrl,
    required this.locality,
    required this.overallRating,
    required this.totalReviews,
    this.jobTitle,
    this.state,
    this.badgesCount = const {},
    this.criteriaRatings = const {},
    this.totalComments = 0,
  });

  final String userId;
  final String fullName;
  final String photoUrl;
  final String locality;
  final double overallRating;
  final int totalReviews;
  final String? jobTitle;
  final String? state;
  final Map<String, int> badgesCount;
  final Map<String, double> criteriaRatings;
  final int totalComments;

  /// Factory para criar a partir de dados combinados
  factory UserRankingModel.fromData({
    required String userId,
    required Map<String, dynamic> userData,
    required Map<String, dynamic> statsData,
  }) {
    // Parsear badges_count
    final badgesData = statsData['badges_count'] as Map<String, dynamic>? ?? {};
    final badgesCount = badgesData.map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );

    // Parsear ratings_breakdown
    final ratingsData = statsData['ratings_breakdown'] as Map<String, dynamic>? ?? {};
    final criteriaRatings = ratingsData.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );

    // Total de comentários (reviews com comentário)
    final totalComments = statsData['total_with_comment'] as int? ?? 0;

    return UserRankingModel(
      userId: userId,
      fullName: userData['fullName'] as String? ?? 'Usuário',
      photoUrl: userData['photoUrl'] as String? ?? '',
      locality: userData['locality'] as String? ?? '',
      state: userData['state'] as String?,
      jobTitle: userData['jobTitle'] as String?,
      overallRating: (statsData['overallRating'] as num?)?.toDouble() ?? 0.0,
      totalReviews: statsData['totalReviews'] as int? ?? 0,
      badgesCount: badgesCount,
      criteriaRatings: criteriaRatings,
      totalComments: totalComments,
    );
  }

  UserRankingModel copyWith({
    String? userId,
    String? fullName,
    String? photoUrl,
    String? locality,
    double? overallRating,
    int? totalReviews,
    String? jobTitle,
    String? state,
    Map<String, int>? badgesCount,
    Map<String, double>? criteriaRatings,
    int? totalComments,
  }) {
    return UserRankingModel(
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      photoUrl: photoUrl ?? this.photoUrl,
      locality: locality ?? this.locality,
      overallRating: overallRating ?? this.overallRating,
      totalReviews: totalReviews ?? this.totalReviews,
      jobTitle: jobTitle ?? this.jobTitle,
      state: state ?? this.state,
      badgesCount: badgesCount ?? this.badgesCount,
      criteriaRatings: criteriaRatings ?? this.criteriaRatings,
      totalComments: totalComments ?? this.totalComments,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'fullName': fullName,
      'photoUrl': photoUrl,
      'locality': locality,
      'state': state,
      'jobTitle': jobTitle,
      'overallRating': overallRating,
      'totalReviews': totalReviews,
      'badgesCount': badgesCount,
      'criteriaRatings': criteriaRatings,
      'totalComments': totalComments,
    };
  }

  factory UserRankingModel.fromMap(Map<String, dynamic> data) {
    final badgesRaw = data['badgesCount'] as Map<String, dynamic>? ?? {};
    final badges = badgesRaw.map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );

    final criteriaRaw = data['criteriaRatings'] as Map<String, dynamic>? ?? {};
    final criteria = criteriaRaw.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );

    return UserRankingModel(
      userId: data['userId'] as String? ?? '',
      fullName: data['fullName'] as String? ?? 'Usuário',
      photoUrl: data['photoUrl'] as String? ?? '',
      locality: data['locality'] as String? ?? '',
      state: data['state'] as String?,
      jobTitle: data['jobTitle'] as String?,
      overallRating: (data['overallRating'] as num?)?.toDouble() ?? 0.0,
      totalReviews: (data['totalReviews'] as num?)?.toInt() ?? 0,
      badgesCount: badges,
      criteriaRatings: criteria,
      totalComments: (data['totalComments'] as num?)?.toInt() ?? 0,
    );
  }
}
