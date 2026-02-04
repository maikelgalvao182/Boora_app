import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// Extrai coordenadas suportando múltiplos schemas:
  /// 1. location como Map (location.latitude/longitude)
  /// 2. location como GeoPoint (Firestore)
  /// 3. topo (data.latitude/longitude)
  static ({double? lat, double? lng}) _extractLatLng(Map<String, dynamic> data) {
    final rawLocation = data['location'];

    // 1) location como Map (novo schema)
    if (rawLocation is Map) {
      final lat = (rawLocation['latitude'] as num?)?.toDouble();
      final lng = (rawLocation['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) return (lat: lat, lng: lng);

      // Às vezes vem aninhado ou com keys diferentes
      final lat2 = (rawLocation['lat'] as num?)?.toDouble();
      final lng2 = (rawLocation['lng'] as num?)?.toDouble();
      if (lat2 != null && lng2 != null) return (lat: lat2, lng: lng2);
    }

    // 2) location como GeoPoint (schema antigo/alternativo)
    if (rawLocation is GeoPoint) {
      return (lat: rawLocation.latitude, lng: rawLocation.longitude);
    }

    // 3) fallback topo (legado)
    final topLat = (data['latitude'] as num?)?.toDouble();
    final topLng = (data['longitude'] as num?)?.toDouble();
    if (topLat != null && topLng != null) return (lat: topLat, lng: topLng);

    return (lat: null, lng: null);
  }

  /// Valida se coordenadas são válidas geograficamente
  static bool _isValidLatLng(double lat, double lng) {
    if (lat.isNaN || lng.isNaN) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    // Evita 0,0 que mascara bug (Golfo da Guiné)
    if (lat == 0.0 && lng == 0.0) return false;
    return true;
  }

  /// Tenta criar EventLocation a partir de um documento Firestore
  /// 
  /// Retorna null se coordenadas não existirem ou forem inválidas.
  /// Isso evita criar markers em (0.0, 0.0) que são descartados depois.
  static EventLocation? tryFromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final coords = _extractLatLng(data);
    final lat = coords.lat;
    final lng = coords.lng;

    if (lat == null || lng == null) {
      // Log útil pra caçar docs ruins
      // debugPrint('⚠️ EventLocation: $docId sem lat/lng (schema=${data['location']?.runtimeType})');
      return null;
    }

    if (!_isValidLatLng(lat, lng)) {
      // debugPrint('⚠️ EventLocation: $docId lat/lng inválidos: $lat,$lng');
      return null;
    }

    return EventLocation(
      eventId: docId,
      latitude: lat,
      longitude: lng,
      eventData: data,
    );
  }

  /// Cria EventLocation a partir de um documento Firestore
  /// 
  /// @deprecated Use tryFromFirestore() para validação robusta
  factory EventLocation.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final result = tryFromFirestore(docId, data);
    if (result == null) {
      // Fallback legado: retorna (0.0, 0.0) mas isso será filtrado
      return EventLocation(
        eventId: docId,
        latitude: 0.0,
        longitude: 0.0,
        eventData: data,
      );
    }
    return result;
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
    // 1. Tenta scheduleDate diretamente (formato moderno)
    final directDate = eventData['scheduleDate'];
    if (directDate != null) {
      try {
        if (directDate is Timestamp) return directDate.toDate();
        if (directDate is DateTime) return directDate;
        if (directDate is int) return DateTime.fromMillisecondsSinceEpoch(directDate);
        if (directDate is String) return DateTime.tryParse(directDate);
      } catch (_) {}
    }
    
    // 2. Tenta schedule.date (formato Firestore usado no app)
    final schedule = eventData['schedule'];
    if (schedule is Map) {
      final dateField = schedule['date'];
      if (dateField != null) {
        try {
          if (dateField is Timestamp) return dateField.toDate();
          if (dateField is DateTime) return dateField;
          if (dateField is int) return DateTime.fromMillisecondsSinceEpoch(dateField);
          if (dateField is String) return DateTime.tryParse(dateField);
        } catch (_) {}
      }
    }
    
    return null;
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
