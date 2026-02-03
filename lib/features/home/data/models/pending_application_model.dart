import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
    debugPrint('🏗️ PendingApplicationModel.fromCombined');
    debugPrint('   applicationId: $applicationId');
    debugPrint('   applicationData keys: ${applicationData.keys.toList()}');
    debugPrint('   userData keys: ${userData.keys.toList()}');
    debugPrint('   eventData keys: ${eventData.keys.toList()}');
    
    final extractedUserId = applicationData['userId'] as String;
    debugPrint('   extractedUserId: $extractedUserId');
    
    // Busca campos com nomes do Firestore (photoUrl, fullname)
    // e também fallbacks para nomes normalizados (photoUrl, fullName)
    final fullName = userData['fullname'] as String? ?? 
                     userData['fullName'] as String? ?? 
                     'Usuário';
    debugPrint('   fullName: $fullName');
                     
    final photoUrl = userData['photoUrl'] as String? ?? 
                     userData['image'] as String?;
    debugPrint('   photoUrl: $photoUrl');

    final activityName = eventData['activityText'] as String? ??
               eventData['name'] as String? ??
               applicationData['eventTitle'] as String? ??
               applicationData['event_title'] as String? ??
               'um evento';

    return PendingApplicationModel(
      applicationId: applicationId,
      eventId: applicationData['eventId'] as String,
      userId: extractedUserId,
      userFullName: fullName,
      userPhotoUrl: photoUrl,
      activityText: activityName,
      eventEmoji: eventData['emoji'] as String? ??
          applicationData['eventEmoji'] as String? ??
          applicationData['event_emoji'] as String? ??
          '🎉',
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
