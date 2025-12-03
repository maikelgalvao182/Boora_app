import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo para mensagens do chat com otimizações de performance
class Message {

  const Message({
    required this.id,
    required this.userId,
    this.senderId, // Now nullable for legacy messages
    this.receiverId,
    required this.type,
    this.text,
    this.imageUrl,
    this.timestamp,
    this.isRead,
    this.params,
  });

  /// Criar Message a partir de documento Firestore
  factory Message.fromDocument(Map<String, dynamic> data, String id) {
    DateTime? timestamp;
    try {
      final timestampField = data['timestamp'];
      if (timestampField is Timestamp) {
        timestamp = timestampField.toDate();
      }
    } catch (e) {
      // Se houver erro ao converter timestamp, deixar null
      timestamp = null;
    }

    final senderId = data['sender_id'] as String?;
    final receiverId = data['receiver_id'] as String?;
    final userId = data['user_id'] as String? ?? '';
    
    // Debug log
    print('🔍 Message.fromDocument - id: $id');
    print('   sender_id (raw): ${data['sender_id']}');
    print('   receiver_id (raw): ${data['receiver_id']}');
    print('   user_id (raw): ${data['user_id']}');
    print('   senderId (final): $senderId');
    print('   userId (final): $userId');

    return Message(
      id: id,
      text: data['message'] ?? data['message_text'] as String?, // ✅ Suporta ambos os campos
      imageUrl: data['message_img_link'] as String?,
      userId: userId,
      senderId: senderId ?? userId, // ✅ Fallback para user_id em mensagens antigas
      receiverId: receiverId,
      type: data['message_type'] as String? ?? 'text',
      timestamp: timestamp,
      isRead: data['message_read'] as bool?,
      params: data['message_params'] as Map<String, dynamic>?,
    );
  }
  final String id;
  final String? text;
  final String? imageUrl;
  final String userId; // ID do dono da subcoleção (mantido por compatibilidade)
  final String? senderId; // ID do autor real da mensagem (nullable para mensagens antigas)
  final String? receiverId;
  final String type;
  final DateTime? timestamp;
  final bool? isRead;
  final Map<String, dynamic>? params;

  /// Converter para Map para salvar no Firestore
  Map<String, dynamic> toMap() {
    return {
      'message': text, // ✅ Campo principal
      'message_text': text, // Compatibilidade
      'message_img_link': imageUrl,
      'user_id': userId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_type': type,
      'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : FieldValue.serverTimestamp(),
      'message_read': isRead,
      'message_params': params,
    };
  }

  Message copyWith({
    String? id,
    String? userId,
    String? senderId,
    String? receiverId,
    String? type,
    String? text,
    String? imageUrl,
    DateTime? timestamp,
    bool? isRead,
    Map<String, dynamic>? params,
  }) {
    return Message(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      type: type ?? this.type,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      params: params ?? this.params,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
      runtimeType == other.runtimeType &&
      id == other.id &&
      text == other.text &&
      imageUrl == other.imageUrl &&
      userId == other.userId &&
      senderId == other.senderId &&
      receiverId == other.receiverId &&
      type == other.type &&
      timestamp == other.timestamp &&
      isRead == other.isRead &&
      params == other.params;

  @override
  int get hashCode =>
      id.hashCode ^
      text.hashCode ^
      imageUrl.hashCode ^
      userId.hashCode ^
      senderId.hashCode ^
      receiverId.hashCode ^
      type.hashCode ^
      timestamp.hashCode ^
      isRead.hashCode ^
      params.hashCode;
}
