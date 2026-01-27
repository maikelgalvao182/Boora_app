import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Modelo de cache persistente para notificações
@HiveType(typeId: 40)
class NotificationCacheItem {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final Map<String, dynamic> data;

  @HiveField(2)
  final int cachedAtMs;

  const NotificationCacheItem({
    required this.id,
    required this.data,
    required this.cachedAtMs,
  });

  DateTime get cachedAt => DateTime.fromMillisecondsSinceEpoch(cachedAtMs);

  static NotificationCacheItem fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final raw = doc.data() ?? <String, dynamic>{};
    final sanitized = _sanitizeMap(raw);

    return NotificationCacheItem(
      id: doc.id,
      data: sanitized,
      cachedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> input) {
    dynamic normalizeValue(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), normalizeValue(v)));
      }
      if (value is List) return value.map(normalizeValue).toList();
      return value;
    }

    final normalized = normalizeValue(input);
    if (normalized is Map) {
      return normalized.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }
}

/// TypeAdapter manual para NotificationCacheItem
class NotificationCacheItemAdapter extends TypeAdapter<NotificationCacheItem> {
  @override
  final int typeId = 40;

  @override
  NotificationCacheItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final fieldKey = reader.readByte();
      fields[fieldKey] = reader.read();
    }

    return NotificationCacheItem(
      id: fields[0] as String? ?? '',
      data: (fields[1] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      cachedAtMs: (fields[2] as num?)?.toInt() ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, NotificationCacheItem obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.data)
      ..writeByte(2)
      ..write(obj.cachedAtMs);
  }
}