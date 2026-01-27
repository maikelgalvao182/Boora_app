import 'package:hive_flutter/hive_flutter.dart';
import 'package:partiu/screens/chat/models/reply_snapshot.dart';

/// Cache persistente de mensagens (últimas 20-30 por conversa)
@HiveType(typeId: 31)
class MessageCacheItem {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String userId;

  @HiveField(2)
  final String? senderId;

  @HiveField(3)
  final String? receiverId;

  @HiveField(4)
  final String type;

  @HiveField(5)
  final String? text;

  @HiveField(6)
  final String? imageUrl;

  @HiveField(7)
  final int? timestampMs;

  @HiveField(8)
  final bool? isRead;

  @HiveField(9)
  final Map<String, dynamic>? params;

  @HiveField(10)
  final Map<String, dynamic>? replyToMap;

  @HiveField(11)
  final bool isDeleted;

  @HiveField(12)
  final int? deletedAtMs;

  @HiveField(13)
  final String? deletedBy;

  const MessageCacheItem({
    required this.id,
    required this.userId,
    required this.senderId,
    required this.receiverId,
    required this.type,
    this.text,
    this.imageUrl,
    this.timestampMs,
    this.isRead,
    this.params,
    this.replyToMap,
    this.isDeleted = false,
    this.deletedAtMs,
    this.deletedBy,
  });

  DateTime? get timestamp =>
      timestampMs != null ? DateTime.fromMillisecondsSinceEpoch(timestampMs!) : null;

  DateTime? get deletedAt =>
      deletedAtMs != null ? DateTime.fromMillisecondsSinceEpoch(deletedAtMs!) : null;

  ReplySnapshot? get replyTo =>
      replyToMap != null ? ReplySnapshot.fromMap(replyToMap!) : null;
}

/// TypeAdapter manual para MessageCacheItem
class MessageCacheItemAdapter extends TypeAdapter<MessageCacheItem> {
  @override
  final int typeId = 31;

  @override
  MessageCacheItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final fieldKey = reader.readByte();
      fields[fieldKey] = reader.read();
    }

    return MessageCacheItem(
      id: fields[0] as String? ?? '',
      userId: fields[1] as String? ?? '',
      senderId: fields[2] as String?,
      receiverId: fields[3] as String?,
      type: fields[4] as String? ?? 'text',
      text: fields[5] as String?,
      imageUrl: fields[6] as String?,
      timestampMs: (fields[7] as num?)?.toInt(),
      isRead: fields[8] as bool?,
      params: (fields[9] as Map?)?.cast<String, dynamic>(),
      replyToMap: (fields[10] as Map?)?.cast<String, dynamic>(),
      isDeleted: fields[11] as bool? ?? false,
      deletedAtMs: (fields[12] as num?)?.toInt(),
      deletedBy: fields[13] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MessageCacheItem obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.senderId)
      ..writeByte(3)
      ..write(obj.receiverId)
      ..writeByte(4)
      ..write(obj.type)
      ..writeByte(5)
      ..write(obj.text)
      ..writeByte(6)
      ..write(obj.imageUrl)
      ..writeByte(7)
      ..write(obj.timestampMs)
      ..writeByte(8)
      ..write(obj.isRead)
      ..writeByte(9)
      ..write(obj.params)
      ..writeByte(10)
      ..write(obj.replyToMap)
      ..writeByte(11)
      ..write(obj.isDeleted)
      ..writeByte(12)
      ..write(obj.deletedAtMs)
      ..writeByte(13)
      ..write(obj.deletedBy);
  }
}