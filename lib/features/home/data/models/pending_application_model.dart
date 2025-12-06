import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo para aplicação pendente com dados do usuário e evento
class PendingApplicationModel {
  final String applicationId;
  final String eventId;
  final String userId;
  final String userFullName;
  final String? userPhotoUrl;
  final String activityText;
  final String eventEmoji;
  final DateTime appliedAt;

  const PendingApplicationModel({
    required this.applicationId,
    required this.eventId,
    required this.userId,
    required this.userFullName,
    this.userPhotoUrl,
    required this.activityText,
    required this.eventEmoji,
    required this.appliedAt,
  });

  /// Cria instância com dados combinados de application + user + event
  factory PendingApplicationModel.fromCombined({
    required String applicationId,
    required Map<String, dynamic> applicationData,
    required Map<String, dynamic> userData,
    required Map<String, dynamic> eventData,
  }) {
    // Tenta buscar campos com nomes normalizados ou nomes do Firestore
    final fullName = userData['fullName'] as String? ?? 
                     userData['fullname'] as String? ?? 
                     'Usuário';
                     
    final photoUrl = userData['photoUrl'] as String? ?? 
                     userData['user_profile_photo'] as String?;

    final activityName = eventData['activityText'] as String? ?? 
                         eventData['name'] as String? ?? 
                         'um evento';

    return PendingApplicationModel(
      applicationId: applicationId,
      eventId: applicationData['eventId'] as String,
      userId: applicationData['userId'] as String,
      userFullName: fullName,
      userPhotoUrl: photoUrl,
      activityText: activityName,
      eventEmoji: eventData['emoji'] as String? ?? '🎉',
      appliedAt: (applicationData['appliedAt'] as Timestamp).toDate(),
    );
  }

  /// Retorna tempo relativo formatado (ex: "há 5 minutos")
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(appliedAt);

    if (difference.inMinutes < 1) {
      return 'agora';
    } else if (difference.inMinutes < 60) {
      return 'há ${difference.inMinutes}min';
    } else if (difference.inHours < 24) {
      return 'há ${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return 'há ${difference.inDays}d';
    } else {
      return 'há ${(difference.inDays / 7).floor()}sem';
    }
  }
}
