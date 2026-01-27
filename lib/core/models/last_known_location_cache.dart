import 'package:hive_flutter/hive_flutter.dart';

/// Cache persistente da última localização conhecida
///
/// Usado para acelerar cold start sem esperar GPS
@HiveType(typeId: 20)
class LastKnownLocationCache {
  @HiveField(0)
  final double latitude;

  @HiveField(1)
  final double longitude;

  @HiveField(2)
  final double accuracy;

  @HiveField(3)
  final int timestampMs;

  const LastKnownLocationCache({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestampMs,
  });

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);

  int get ageMinutes => DateTime.now().difference(timestamp).inMinutes;
}

/// TypeAdapter manual para LastKnownLocationCache
class LastKnownLocationCacheAdapter extends TypeAdapter<LastKnownLocationCache> {
  @override
  final int typeId = 20;

  @override
  LastKnownLocationCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final fieldKey = reader.readByte();
      fields[fieldKey] = reader.read();
    }
    return LastKnownLocationCache(
      latitude: (fields[0] as num?)?.toDouble() ?? 0.0,
      longitude: (fields[1] as num?)?.toDouble() ?? 0.0,
      accuracy: (fields[2] as num?)?.toDouble() ?? 0.0,
      timestampMs: (fields[3] as num?)?.toInt() ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, LastKnownLocationCache obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.latitude)
      ..writeByte(1)
      ..write(obj.longitude)
      ..writeByte(2)
      ..write(obj.accuracy)
      ..writeByte(3)
      ..write(obj.timestampMs);
  }
}