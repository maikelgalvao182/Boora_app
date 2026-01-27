import 'package:hive/hive.dart';

/// Modelo de cache para EventLocation
/// 
/// Versão simplificada do EventLocation otimizada para Hive:
/// - Apenas dados essenciais para markers no mapa
/// - Sem Map (problemático para serialização)
/// - Dados completos vêm do Firestore quando necessário
/// 
/// 🧠 Filosofia: Isso ajuda o app a PARECER rápido.
/// O marker aparece instantaneamente, dados completos carregam depois.
class EventLocationCache {
  final String eventId;
  final double latitude;
  final double longitude;
  final String emoji;
  final String title;
  final String createdBy;
  final String? category;
  final int? scheduleDateMillis; // DateTime como millis para Hive
  final int cachedAtMillis; // Quando foi cacheado

  EventLocationCache({
    required this.eventId,
    required this.latitude,
    required this.longitude,
    required this.emoji,
    required this.title,
    required this.createdBy,
    this.category,
    this.scheduleDateMillis,
    int? cachedAtMillis,
  }) : cachedAtMillis = cachedAtMillis ?? DateTime.now().millisecondsSinceEpoch;

  /// Cria a partir do EventLocation original
  factory EventLocationCache.fromEventLocation(
    String eventId,
    double latitude,
    double longitude,
    Map<String, dynamic> eventData,
  ) {
    DateTime? scheduleDate;
    final timestamp = eventData['scheduleDate'];
    if (timestamp != null) {
      try {
        scheduleDate = timestamp.toDate();
      } catch (_) {}
    }

    return EventLocationCache(
      eventId: eventId,
      latitude: latitude,
      longitude: longitude,
      emoji: eventData['emoji'] as String? ?? '🎉',
      title: eventData['activityText'] as String? ?? '',
      createdBy: eventData['createdBy'] as String? ?? '',
      category: eventData['category'] as String?,
      scheduleDateMillis: scheduleDate?.millisecondsSinceEpoch,
    );
  }

  /// Data do evento (pode ser null)
  DateTime? get scheduleDate => scheduleDateMillis != null 
      ? DateTime.fromMillisecondsSinceEpoch(scheduleDateMillis!) 
      : null;

  /// Quando foi cacheado
  DateTime get cachedAt => DateTime.fromMillisecondsSinceEpoch(cachedAtMillis);

  /// Reconstrói eventData mínimo para compatibilidade
  /// 
  /// ⚠️ Este Map NÃO contém todos os campos do evento original.
  /// Use apenas para exibição de markers. Para dados completos,
  /// busque do Firestore.
  Map<String, dynamic> toMinimalEventData() {
    return {
      'emoji': emoji,
      'activityText': title,
      'createdBy': createdBy,
      'category': category,
      // scheduleDate não incluído pois precisaria de Timestamp
    };
  }

  @override
  String toString() {
    return 'EventLocationCache(id: $eventId, title: $title, lat: $latitude, lng: $longitude)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EventLocationCache && other.eventId == eventId;
  }

  @override
  int get hashCode => eventId.hashCode;
}

/// TypeAdapter manual para EventLocationCache
/// 
/// TypeId: 10 (reservado para eventos/mapa)
class EventLocationCacheAdapter extends TypeAdapter<EventLocationCache> {
  @override
  final int typeId = 10;

  @override
  EventLocationCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EventLocationCache(
      eventId: fields[0] as String,
      latitude: fields[1] as double,
      longitude: fields[2] as double,
      emoji: fields[3] as String,
      title: fields[4] as String,
      createdBy: fields[5] as String,
      category: fields[6] as String?,
      scheduleDateMillis: fields[7] as int?,
      cachedAtMillis: fields[8] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, EventLocationCache obj) {
    writer
      ..writeByte(9) // número de campos
      ..writeByte(0)
      ..write(obj.eventId)
      ..writeByte(1)
      ..write(obj.latitude)
      ..writeByte(2)
      ..write(obj.longitude)
      ..writeByte(3)
      ..write(obj.emoji)
      ..writeByte(4)
      ..write(obj.title)
      ..writeByte(5)
      ..write(obj.createdBy)
      ..writeByte(6)
      ..write(obj.category)
      ..writeByte(7)
      ..write(obj.scheduleDateMillis)
      ..writeByte(8)
      ..write(obj.cachedAtMillis);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventLocationCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
