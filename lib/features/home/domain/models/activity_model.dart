import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de atividade simplificado para notificações
class ActivityModel {
  final String id;
  final String name;
  final String emoji;
  final double latitude;
  final double longitude;
  final String createdBy;
  final DateTime createdAt;

  const ActivityModel({
    required this.id,
    required this.name,
    required this.emoji,
    required this.latitude,
    required this.longitude,
    required this.createdBy,
    required this.createdAt,
  });

  /// Cria ActivityModel a partir de documento do Firestore
  factory ActivityModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ActivityModel(
      id: doc.id,
      name: data['activityText'] ?? '',
      emoji: data['emoji'] ?? '',
      latitude: data['location']?['latitude'] ?? 0.0,
      longitude: data['location']?['longitude'] ?? 0.0,
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Cria ActivityModel a partir de Map
  factory ActivityModel.fromMap(String id, Map<String, dynamic> data) {
    return ActivityModel(
      id: id,
      name: data['activityText'] ?? '',
      emoji: data['emoji'] ?? '',
      latitude: data['location']?['latitude'] ?? 0.0,
      longitude: data['location']?['longitude'] ?? 0.0,
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Converte para Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'activityText': name,
      'emoji': emoji,
      'location': {
        'latitude': latitude,
        'longitude': longitude,
      },
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  @override
  String toString() {
    return 'ActivityModel(id: $id, name: $name, emoji: $emoji)';
  }
}
