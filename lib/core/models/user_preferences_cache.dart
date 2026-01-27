import 'package:hive_flutter/hive_flutter.dart';

/// Cache persistente de preferências do usuário
///
/// Mantém dados de UI rápidos (ex: radiusKm, filtros avançados)
@HiveType(typeId: 21)
class UserPreferencesCache {
  @HiveField(0)
  final double radiusKm;

  @HiveField(1)
  final Map<String, dynamic>? advancedFilters;

  @HiveField(2)
  final String? lastCategoryFilter;

  @HiveField(3)
  final String? distanceUnit;

  @HiveField(4)
  final int cachedAtMs;

  const UserPreferencesCache({
    required this.radiusKm,
    this.advancedFilters,
    this.lastCategoryFilter,
    this.distanceUnit,
    required this.cachedAtMs,
  });

  DateTime get cachedAt => DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
}

/// TypeAdapter manual para UserPreferencesCache
class UserPreferencesCacheAdapter extends TypeAdapter<UserPreferencesCache> {
  @override
  final int typeId = 21;

  @override
  UserPreferencesCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final fieldKey = reader.readByte();
      fields[fieldKey] = reader.read();
    }

    return UserPreferencesCache(
      radiusKm: (fields[0] as num?)?.toDouble() ?? 30.0,
      advancedFilters: (fields[1] as Map?)?.cast<String, dynamic>(),
      lastCategoryFilter: fields[2] as String?,
      distanceUnit: fields[3] as String?,
      cachedAtMs: (fields[4] as num?)?.toInt() ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, UserPreferencesCache obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.radiusKm)
      ..writeByte(1)
      ..write(obj.advancedFilters)
      ..writeByte(2)
      ..write(obj.lastCategoryFilter)
      ..writeByte(3)
      ..write(obj.distanceUnit)
      ..writeByte(4)
      ..write(obj.cachedAtMs);
  }
}