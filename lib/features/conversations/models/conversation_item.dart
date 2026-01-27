import 'package:hive_flutter/hive_flutter.dart';

@HiveType(typeId: 30)
class ConversationItem {
  @HiveField(0)
  final String id; // other userId or conversationId
  @HiveField(1)
  final String userId;
  @HiveField(2)
  final String userFullname;
  @HiveField(3)
  final String? userPhotoUrl;
  @HiveField(4)
  final String? lastMessage;
  @HiveField(5)
  final String? lastMessageType;
  @HiveField(6)
  final DateTime? lastMessageAt;
  @HiveField(7)
  final int unreadCount;
  @HiveField(8)
  final bool isRead;
  @HiveField(9)
  final bool isEventChat; // Se é um chat de evento
  @HiveField(10)
  final String? eventId; // ID do evento (quando isEventChat = true)
  @HiveField(11)
  final String? emoji; // Emoji do evento (quando isEventChat = true)

  ConversationItem({
    required this.id,
    required this.userId,
    required this.userFullname,
    this.userPhotoUrl,
    this.lastMessage,
    this.lastMessageType,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.isRead = true,
    this.isEventChat = false,
    this.eventId,
    this.emoji,
  });

  ConversationItem copyWith({
    String? id,
    String? userId,
    String? userFullname,
    String? userPhotoUrl,
    String? lastMessage,
    String? lastMessageType,
    DateTime? lastMessageAt,
    int? unreadCount,
    bool? isRead,
    bool? isEventChat,
    String? eventId,
    String? emoji,
  }) {
    return ConversationItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userFullname: userFullname ?? this.userFullname,
      userPhotoUrl: userPhotoUrl ?? this.userPhotoUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isRead: isRead ?? this.isRead,
      isEventChat: isEventChat ?? this.isEventChat,
      eventId: eventId ?? this.eventId,
      emoji: emoji ?? this.emoji,
    );
  }

  factory ConversationItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) {
        return DateTime.tryParse(value);
      }
      if (value is num) {
        final n = value.toDouble();
        // Heurística: > 10^12 → millis, senão segundos
        final millis = n > 1000000000000 ? n.toInt() : (n * 1000).toInt();
        return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
      }
      if (value is Map) {
        final seconds = value['seconds'] ?? value['_seconds'];
        final nanos = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
        if (seconds is num) {
          final millis =
              (seconds * 1000).toInt() + ((nanos is num ? nanos : 0) ~/ 1000000);
          return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
        }
      }
      return null;
    }

    final rawTs = json['lastMessageAt'] ??
        json['last_message_timestamp'] ??
        json['last_message_at'] ??
        json['timestamp'];
    final parsedTs = parseTimestamp(rawTs);

    // Resolve IDs and name from multiple possible keys
    final id = (json['id'] ?? json['conversationId'] ?? json['userId'] ?? '')
        .toString();
    final userId = (json['userId'] ?? json['other_user_id'] ?? json['id'] ?? '')
        .toString();
    final userFullname =
        (json['userFullname'] ?? json['other_user_name'] ?? '').toString();

    // Resolve last message text from multiple fields
    final lastMessage = (json['lastMessage'] ??
            json['last_message_text'] ??
            json['message_text'] ??
            json['lastMessageText'] ??
            json['last_message'] ??
            '')
        .toString();

    // Resolve message type from multiple fields
    final lastMessageType = (json['lastMessageType'] ??
            json['last_message_type'] ??
            json['message_type'])
        ?.toString();

    // Resolve unread information
    final unreadCountJson =
        (json['unreadCount'] ?? json['unread_count']) as num?;
    final unreadCount = unreadCountJson?.toInt() ?? 0;
    final readFlag = json['isRead'] ?? json['message_read'];
    final isRead = (readFlag is bool)
        ? readFlag
        : unreadCount == 0; // fallback: any unreadCount > 0 => not read

    // Event chat fields
    final isEventChat = json['is_event_chat'] == true || json['isEventChat'] == true;
    final eventId = (json['event_id'] ?? json['eventId'])?.toString();
    final emoji = (json['emoji'])?.toString();

    return ConversationItem(
      id: id,
      userId: userId,
      userFullname: userFullname,
      userPhotoUrl: json['userPhotoUrl'] as String?,
      lastMessage: lastMessage.isNotEmpty ? lastMessage : null,
      lastMessageType: lastMessageType,
      lastMessageAt: parsedTs,
      unreadCount: unreadCount,
      isRead: isRead,
      isEventChat: isEventChat,
      eventId: eventId,
      emoji: emoji,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'userFullname': userFullname,
      'userPhotoUrl': userPhotoUrl,
      'lastMessage': lastMessage,
      'lastMessageType': lastMessageType,
      'lastMessageAt': lastMessageAt?.toIso8601String(),
      'unreadCount': unreadCount,
      'isRead': isRead,
      'isEventChat': isEventChat,
      'eventId': eventId,
      'emoji': emoji,
    };
  }
}

/// TypeAdapter manual para ConversationItem
class ConversationItemAdapter extends TypeAdapter<ConversationItem> {
  @override
  final int typeId = 30;

  @override
  ConversationItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final fieldKey = reader.readByte();
      fields[fieldKey] = reader.read();
    }

    return ConversationItem(
      id: fields[0] as String? ?? '',
      userId: fields[1] as String? ?? '',
      userFullname: fields[2] as String? ?? '',
      userPhotoUrl: fields[3] as String?,
      lastMessage: fields[4] as String?,
      lastMessageType: fields[5] as String?,
      lastMessageAt: fields[6] as DateTime?,
      unreadCount: (fields[7] as num?)?.toInt() ?? 0,
      isRead: fields[8] as bool? ?? true,
      isEventChat: fields[9] as bool? ?? false,
      eventId: fields[10] as String?,
      emoji: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ConversationItem obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.userFullname)
      ..writeByte(3)
      ..write(obj.userPhotoUrl)
      ..writeByte(4)
      ..write(obj.lastMessage)
      ..writeByte(5)
      ..write(obj.lastMessageType)
      ..writeByte(6)
      ..write(obj.lastMessageAt)
      ..writeByte(7)
      ..write(obj.unreadCount)
      ..writeByte(8)
      ..write(obj.isRead)
      ..writeByte(9)
      ..write(obj.isEventChat)
      ..writeByte(10)
      ..write(obj.eventId)
      ..writeByte(11)
      ..write(obj.emoji);
  }
}
