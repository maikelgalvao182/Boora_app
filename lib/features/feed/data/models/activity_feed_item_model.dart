import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de item do feed de atividades do usuário
/// 
/// Representa um post no feed do usuário quando ele cria um evento.
/// Dados são "congelados" no momento da criação para evitar inconsistências
/// caso o evento seja editado posteriormente.
class ActivityFeedItemModel {
  const ActivityFeedItemModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.userFullName,
    required this.activityText,
    required this.emoji,
    required this.locationName,
    required this.eventDate,
    required this.createdAt,
    this.userPhotoUrl,
    this.status = 'active',
  });

  /// ID do documento no Firestore
  final String id;

  /// ID do evento associado (para navegação e deleção)
  final String eventId;

  /// ID do usuário que criou o evento
  final String userId;

  /// Nome completo do usuário (congelado)
  final String userFullName;

  /// Texto da atividade (congelado)
  final String activityText;

  /// Emoji da atividade (congelado)
  final String emoji;

  /// Nome do local (congelado)
  final String locationName;

  /// Data do evento (congelada)
  final Timestamp eventDate;

  /// Data de criação do post no feed
  final Timestamp? createdAt;

  /// URL da foto do usuário (congelada)
  final String? userPhotoUrl;

  /// Status do item (active, deleted)
  final String status;

  /// Cria o modelo a partir de um documento Firestore
  factory ActivityFeedItemModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ActivityFeedItemModel(
      id: doc.id,
      eventId: (data['eventId'] as String?) ?? '',
      userId: (data['userId'] as String?) ?? '',
      userFullName: (data['userFullName'] as String?) ?? '',
      activityText: (data['activityText'] as String?) ?? '',
      emoji: (data['emoji'] as String?) ?? '',
      locationName: (data['locationName'] as String?) ?? '',
      eventDate: data['eventDate'] as Timestamp? ?? Timestamp.now(),
      createdAt: data['createdAt'] as Timestamp?,
      userPhotoUrl: data['userPhotoUrl'] as String?,
      status: (data['status'] as String?) ?? 'active',
    );
  }

  /// Converte para Map para criação no Firestore
  Map<String, dynamic> toCreateMap() {
    return {
      'eventId': eventId,
      'userId': userId,
      'userFullName': userFullName,
      'activityText': activityText,
      'emoji': emoji,
      'locationName': locationName,
      'eventDate': eventDate,
      'createdAt': FieldValue.serverTimestamp(),
      'userPhotoUrl': userPhotoUrl,
      'status': status,
    };
  }

  /// Texto formatado para exibição no header do post
  /// Exemplo: "João quer Jogar Futebol em Parque Ibirapuera"
  String get formattedHeader => '$userFullName quer $activityText em $locationName';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityFeedItemModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ActivityFeedItemModel('
        'id: $id, '
        'eventId: $eventId, '
        'userId: $userId, '
        'activityText: $activityText'
        ')';
  }
}
