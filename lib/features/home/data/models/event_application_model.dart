import 'package:cloud_firestore/cloud_firestore.dart';

/// Status da aplicação para um evento
enum ApplicationStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  autoApproved('autoApproved');

  const ApplicationStatus(this.value);
  final String value;

  static ApplicationStatus fromString(String value) {
    return ApplicationStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => ApplicationStatus.pending,
    );
  }
}

/// Status de presença do participante no evento
enum PresenceStatus {
  going('Vou'),
  maybe('Talvez'),
  notGoing('Não vou');

  const PresenceStatus(this.value);
  final String value;

  static PresenceStatus fromString(String value) {
    return PresenceStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => PresenceStatus.maybe,
    );
  }
}

/// Modelo de aplicação de usuário para um evento
class EventApplicationModel {
  final String id;
  final String eventId;
  final String userId;
  final ApplicationStatus status;
  final DateTime appliedAt;
  final DateTime? decisionAt;
  final PresenceStatus presence;
  final String? userFullName;
  final String? userPhotoUrl;
  final String? eventTitle;
  final String? eventEmoji;

  const EventApplicationModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.status,
    required this.appliedAt,
    this.decisionAt,
    this.presence = PresenceStatus.maybe,
    this.userFullName,
    this.userPhotoUrl,
    this.eventTitle,
    this.eventEmoji,
  });

  /// Cria instância a partir de documento Firestore
  factory EventApplicationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return EventApplicationModel(
      id: doc.id,
      eventId: data['eventId'] as String,
      userId: data['userId'] as String,
      status: ApplicationStatus.fromString(data['status'] as String),
      appliedAt: (data['appliedAt'] as Timestamp).toDate(),
      decisionAt: data['decisionAt'] != null 
          ? (data['decisionAt'] as Timestamp).toDate() 
          : null,
      presence: data['presence'] != null
          ? PresenceStatus.fromString(data['presence'] as String)
          : PresenceStatus.maybe,
      userFullName: data['userFullName'] as String?,
      userPhotoUrl: data['userPhotoUrl'] as String?,
      eventTitle: data['eventTitle'] as String?,
      eventEmoji: data['eventEmoji'] as String?,
    );
  }

  /// Converte para Map para salvar no Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'eventId': eventId,
      'userId': userId,
      'status': status.value,
      'appliedAt': Timestamp.fromDate(appliedAt),
      'presence': presence.value,
      if (userFullName != null) 'userFullName': userFullName,
      if (userPhotoUrl != null) 'userPhotoUrl': userPhotoUrl,
      if (eventTitle != null) 'eventTitle': eventTitle,
      if (eventEmoji != null) 'eventEmoji': eventEmoji,
      if (decisionAt != null) 'decisionAt': Timestamp.fromDate(decisionAt!),
    };
  }

  /// Verifica se a aplicação foi aprovada (automática ou manualmente)
  bool get isApproved => 
      status == ApplicationStatus.approved || 
      status == ApplicationStatus.autoApproved;

  /// Verifica se está pendente
  bool get isPending => status == ApplicationStatus.pending;

  /// Verifica se foi rejeitada
  bool get isRejected => status == ApplicationStatus.rejected;
}
