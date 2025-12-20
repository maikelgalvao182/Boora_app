import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/screens/chat/models/reply_snapshot.dart';

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
    this.replyTo, // 🆕 Dados de reply
  });

  /// Criar Message a partir de documento Firestore
  static Message? fromDocument(Map<String, dynamic> data, String id) {
    // 🔍 DIAGNOSTIC LOG: Print raw data to identify source of bad messages
    // print("RAW DOC [$id]: $data");

    DateTime? timestamp;
    try {
      final timestampField = data['timestamp'];
      if (timestampField is Timestamp) {
        timestamp = timestampField.toDate();
      } else if (timestampField == null) {
        // 🕒 Fallback para escritas locais (latency compensation)
        timestamp = DateTime.now();
      }
    } catch (e) {
      timestamp = DateTime.now();
    }

    // 🔄 NORMALIZATION: Support both snake_case and camelCase keys
    // Some legacy or system messages use camelCase (senderId, receiverId, etc.)
    final senderId = (data['sender_id'] ?? data['senderId']) as String?;
    final userId = (data['user_id'] ?? data['userId']) as String?; 
    
    // 🛡️ VALIDATION: Filter out broken messages
    if (senderId == null && (userId == null || userId.isEmpty)) {
      print("⚠️ [Message Model] Invalid message detected (no sender_id/user_id). Ignoring id: $id");
      print("   - Data: $data");
      return null;
    }

    // 🔄 NORMALIZATION: Handle Event vs 1x1 Chat Schema
    // If receiver_id starts with 'event_', treat it as null (Event Chat)
    // This fixes legacy messages that might have 'event_...' in receiver_id
    String? rawReceiverId = (data['receiver_id'] ?? data['receiverId']) as String?;
    if (rawReceiverId != null && rawReceiverId.startsWith('event_')) {
      rawReceiverId = null;
    }
    final receiverId = rawReceiverId;

    final finalUserId = userId ?? '';
    
    // 🆕 Criar ReplySnapshot se campos de reply existirem
    ReplySnapshot? replyTo;
    if (data['replyToMessageId'] != null) {
      try {
        replyTo = ReplySnapshot.fromMap(data);
      } catch (e) {
        print('⚠️ [Message Model] Erro ao parsear reply: $e');
      }
    }
    
    return Message(
      id: id,
      text: data['message'] ?? data['message_text'] as String?, // ✅ Suporta ambos os campos
      imageUrl: (data['message_img_link'] ?? data['imgLink']) as String?,
      userId: finalUserId,
      senderId: senderId ?? finalUserId, // ✅ Fallback para user_id em mensagens antigas
      receiverId: receiverId,
      type: (data['message_type'] ?? data['messageType']) as String? ?? 'text',
      timestamp: timestamp,
      isRead: data['message_read'] as bool?,
      params: data['message_params'] as Map<String, dynamic>?,
      replyTo: replyTo, // 🆕
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
  final ReplySnapshot? replyTo; // 🆕 Dados de reply

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
      if (replyTo != null) ...replyTo!.toMap(), // 🆕 Spread dos campos de reply
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
    ReplySnapshot? replyTo, // 🆕
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
      replyTo: replyTo ?? this.replyTo, // 🆕
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
      params == other.params &&
      replyTo == other.replyTo; // 🆕

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
      params.hashCode ^
      replyTo.hashCode; // 🆕
}
