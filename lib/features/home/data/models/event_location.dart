/// Representa um evento com sua localização geográfica
/// 
/// Usado no MapDiscoveryService para retornar eventos
/// encontrados em queries de bounding box.
class EventLocation {
  final String eventId;
  final double latitude;
  final double longitude;
  final Map<String, dynamic> eventData;

  const EventLocation({
    required this.eventId,
    required this.latitude,
    required this.longitude,
    required this.eventData,
  });

  /// Cria EventLocation a partir de um documento Firestore
  factory EventLocation.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final location = data['location'] as Map<String, dynamic>?;
    
    return EventLocation(
      eventId: docId,
      latitude: location?['latitude'] ?? 0.0,
      longitude: location?['longitude'] ?? 0.0,
      eventData: data,
    );
  }

  /// Retorna dados essenciais do evento
  String get title => eventData['activityText'] as String? ?? '';
  String get emoji => eventData['emoji'] as String? ?? '🎉';
  String get createdBy => eventData['createdBy'] as String? ?? '';

  String? get category {
    final raw = eventData['category'];
    if (raw is String) return raw;
    return null;
  }
  
  DateTime? get scheduleDate {
    final timestamp = eventData['scheduleDate'];
    if (timestamp == null) return null;
    
    try {
      return timestamp.toDate();
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() {
    return 'EventLocation(id: $eventId, title: $title, lat: $latitude, lng: $longitude)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EventLocation && other.eventId == eventId;
  }

  @override
  int get hashCode => eventId.hashCode;
}
