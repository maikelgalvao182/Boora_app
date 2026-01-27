import 'package:hive_flutter/hive_flutter.dart';

/// Cache persistente de sessão do usuário (campos estáveis)
///
/// Usado para acelerar cold start e evitar flicker na UI
@HiveType(typeId: 22)
class UserSessionCache {
  @HiveField(0)
  final Map<String, dynamic> data;

  @HiveField(1)
  final int cachedAtMs;

  const UserSessionCache({
    required this.data,
    required this.cachedAtMs,
  });

  DateTime get cachedAt => DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
}

/// TypeAdapter manual para UserSessionCache
class UserSessionCacheAdapter extends TypeAdapter<UserSessionCache> {
  @override
  final int typeId = 22;

  @override
  UserSessionCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final fieldKey = reader.readByte();
      fields[fieldKey] = reader.read();
    }
    return UserSessionCache(
      data: (fields[0] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      cachedAtMs: (fields[1] as num?)?.toInt() ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, UserSessionCache obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.data)
      ..writeByte(1)
      ..write(obj.cachedAtMs);
  }
}