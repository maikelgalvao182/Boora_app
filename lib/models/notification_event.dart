// Modelo semântico para eventos de notificação
import 'package:partiu/core/constants/constants.dart';
// 
// Este modelo representa eventos de notificação usando tipos semânticos
// e parâmetros estruturados, seguindo as melhores práticas da indústria
// (Firebase, Stripe, Meta, etc.).
// 
// ❌ ANTI-PATTERN (old approach):
// ```dart
// n_message: "Frank visited your profile"
// ```
// 
// ✅ BEST PRACTICE (new approach):
// ```dart
// NotificationEvent(
//   type: NotificationEventType.message,
//   params: {'senderName': 'Frank'},
// )
// ```

/// Tipos de eventos de notificação suportados
enum NotificationEventType {
  /// Nova mensagem recebida
  message('message'),
  
  /// Notificação de alerta do sistema
  alert('alert'),
  
  /// Tipo customizado para eventos específicos do app
  custom('custom');

  const NotificationEventType(this.value);
  final String value;

  /// Converte string para enum (retorna sempre um valor válido)
  static NotificationEventType fromString(String? value) {
    if (value == null || value.isEmpty) return NotificationEventType.alert;
    return NotificationEventType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => NotificationEventType.alert,
    );
  }
}

/// Modelo de evento de notificação com parâmetros estruturados
class NotificationEvent {
  /// Tipo do evento
  final NotificationEventType type;
  
  /// Parâmetros do evento para interpolação nas traduções
  final Map<String, dynamic> params;
  
  /// ID do usuário que disparou o evento
  final String? senderId;
  
  /// Nome completo do usuário que disparou o evento
  final String? senderName;
  
  /// URL da foto do usuário que disparou o evento
  final String? senderPhotoUrl;
  
  /// ID relacionado ao evento (ex: message_id, etc.)
  final String? relatedId;
  
  /// Deep link para navegação
  final String? deepLink;
  
  /// Nome da tela de destino
  final String? screen;

  const NotificationEvent({
    required this.type,
    this.params = const {},
    this.senderId,
    this.senderName,
    this.senderPhotoUrl,
    this.relatedId,
    this.deepLink,
    this.screen,
  });

  /// Cria instância a partir de dados do Firestore
  factory NotificationEvent.fromFirestore(Map<String, dynamic> data) {
    final typeStr = data[N_TYPE] as String?;
    final type = NotificationEventType.fromString(typeStr);
    
    final paramsRaw = data[N_PARAMS];
    final params = paramsRaw is Map<String, dynamic>
        ? paramsRaw
        : data[N_METADATA] is Map<String, dynamic>
            ? data[N_METADATA] as Map<String, dynamic>
            : <String, dynamic>{};

    return NotificationEvent(
      type: type,
      params: params,
      senderId: data[N_SENDER_ID] as String?,
      senderName: data[N_SENDER_FULLNAME] as String?,
      senderPhotoUrl: data[N_SENDER_PHOTO_LINK] as String?,
      relatedId: data[N_RELATED_ID] as String?,
    );
  }

  /// Converte para Map para salvar no Firestore
  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      N_TYPE: type.value,
      N_PARAMS: params,
    };

    if (senderId != null) map[N_SENDER_ID] = senderId;
    if (senderName != null) map[N_SENDER_FULLNAME] = senderName;
    if (senderPhotoUrl != null) map[N_SENDER_PHOTO_LINK] = senderPhotoUrl;
    if (relatedId != null) map[N_RELATED_ID] = relatedId;
    // deepLink/screen não devem ser persistidos; a navegação é derivada no app

    return map;
  }

  /// Converte o evento em payload de dados para FCM (client-side resolverá o texto)
  Map<String, String> toPushData({String? notificationId}) {
    final map = <String, String>{
      'type': type.value,
      if (notificationId != null) 'notificationId': notificationId,
      if (senderId != null) 'senderId': senderId!,
      if (senderName != null) 'senderName': senderName!,
      if (senderPhotoUrl != null) 'senderPhotoUrl': senderPhotoUrl!,
      if (relatedId != null) 'relatedId': relatedId!,
      if (deepLink != null) 'deepLink': deepLink!,
      if (screen != null) 'screen': screen!,
    };
    // Achatar params básicos em data (apenas strings simples)
    params.forEach((k, v) {
      final str = v?.toString();
      if (str != null) map[k] = str;
    });
    return map;
  }

  /// Cria cópia com campos alterados
  NotificationEvent copyWith({
    NotificationEventType? type,
    Map<String, dynamic>? params,
    String? senderId,
    String? senderName,
    String? senderPhotoUrl,
    String? relatedId,
    String? deepLink,
    String? screen,
  }) {
    return NotificationEvent(
      type: type ?? this.type,
      params: params ?? this.params,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderPhotoUrl: senderPhotoUrl ?? this.senderPhotoUrl,
      relatedId: relatedId ?? this.relatedId,
      deepLink: deepLink ?? this.deepLink,
      screen: screen ?? this.screen,
    );
  }

  @override
  String toString() {
    return 'NotificationEvent(type: $type, sender: $senderName, params: $params)';
  }
}

/// Factory para criar eventos de notificação comuns
class NotificationEventFactory {
  /// Evento de nova mensagem
  static NotificationEvent newMessage({
    required String senderId,
    required String senderName,
    required String senderPhotoUrl,
    String? messagePreview,
  }) {
    return NotificationEvent(
      type: NotificationEventType.message,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      params: {
        'senderName': senderName,
        if (messagePreview != null) 'messagePreview': messagePreview,
      },
      screen: 'ConversationsScreen',
    );
  }

  /// Evento de alerta do sistema
  static NotificationEvent systemAlert({
    required String message,
    String? relatedId,
  }) {
    return NotificationEvent(
      type: NotificationEventType.alert,
      params: {'message': message},
      relatedId: relatedId,
    );
  }
  
  /// Evento customizado - use este para criar seus próprios tipos de notificação
  static NotificationEvent custom({
    required String senderId,
    required String senderName,
    required String senderPhotoUrl,
    required Map<String, dynamic> params,
    String? relatedId,
    String? screen,
  }) {
    return NotificationEvent(
      type: NotificationEventType.custom,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      params: params,
      relatedId: relatedId,
      screen: screen,
    );
  }
}
