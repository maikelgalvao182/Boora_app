import 'package:flutter/foundation.dart';

/// Snapshot imutável de uma mensagem sendo respondida
/// 
/// Evita espalhar múltiplos campos e facilita evolução futura.
/// Usado para armazenar dados de reply tanto em memória quanto no Firestore.
@immutable
class ReplySnapshot {
  const ReplySnapshot({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    this.text,
    this.imageUrl,
    this.type = 'text',
  });

  /// ID da mensagem original sendo respondida
  final String messageId;
  
  /// ID do autor da mensagem original
  final String senderId;
  
  /// Nome do autor da mensagem original (cacheado para evitar queries)
  final String senderName;
  
  /// Texto da mensagem original (max 100 chars, truncado se maior)
  final String? text;
  
  /// URL da imagem da mensagem original (se for mensagem de imagem)
  final String? imageUrl;
  
  /// Tipo da mensagem original: 'text', 'image', 'audio' (futuro)
  final String type;

  /// Truncar texto para máximo de 100 caracteres
  static String? _truncateText(String? text) {
    if (text == null || text.isEmpty) return null;
    final cleaned = text.trim();
    return cleaned.length > 100 
      ? '${cleaned.substring(0, 97)}...' 
      : cleaned;
  }

  /// Criar ReplySnapshot a partir de dados do Firestore
  factory ReplySnapshot.fromMap(Map<String, dynamic> map) {
    return ReplySnapshot(
      messageId: map['replyToMessageId'] as String,
      senderId: map['replyToSenderId'] as String,
      senderName: map['replyToSenderName'] as String,
      text: map['replyToText'] as String?,
      imageUrl: map['replyToImageUrl'] as String?,
      type: map['replyToType'] as String? ?? 'text',
    );
  }

  /// Converter para Map para salvar no Firestore
  /// Usa camelCase conforme padrão do projeto
  Map<String, dynamic> toMap() {
    return {
      'replyToMessageId': messageId,
      'replyToSenderId': senderId,
      'replyToSenderName': senderName,
      if (text != null) 'replyToText': _truncateText(text),
      if (imageUrl != null) 'replyToImageUrl': imageUrl,
      'replyToType': type,
    };
  }

  /// Cria cópia com valores alterados
  ReplySnapshot copyWith({
    String? messageId,
    String? senderId,
    String? senderName,
    String? text,
    String? imageUrl,
    String? type,
  }) {
    return ReplySnapshot(
      messageId: messageId ?? this.messageId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      type: type ?? this.type,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplySnapshot &&
          runtimeType == other.runtimeType &&
          messageId == other.messageId;

  @override
  int get hashCode => messageId.hashCode;

  @override
  String toString() {
    return 'ReplySnapshot(messageId: $messageId, senderId: $senderId, senderName: $senderName, text: $text, type: $type)';
  }
}
