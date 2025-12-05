import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de ranking de locais
/// 
/// Representa a posição de um local no ranking baseado
/// no número de eventos hospedados.
class LocationRankingModel {
  final String placeId;
  final String locationName;
  final String formattedAddress;
  final String? locality;
  final int totalEventsHosted;
  final int totalVisitors;
  final List<Map<String, dynamic>> visitors;
  final DateTime? lastEventAt;
  final double? lastLat;
  final double? lastLng;
  final List<String> photoReferences;

  const LocationRankingModel({
    required this.placeId,
    required this.locationName,
    required this.formattedAddress,
    this.locality,
    required this.totalEventsHosted,
    this.totalVisitors = 0,
    this.visitors = const [],
    this.lastEventAt,
    this.lastLat,
    this.lastLng,
    this.photoReferences = const [],
  });

  /// Cria instância a partir de documento Firestore
  factory LocationRankingModel.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    Timestamp? timestamp = data['lastEventAt'] as Timestamp?;
    
    // Converter photoReferences de List<dynamic> para List<String>
    List<String> photoRefs = [];
    if (data['photoReferences'] != null) {
      final refs = data['photoReferences'] as List<dynamic>;
      photoRefs = refs.map((e) => e.toString()).toList();
    }
    
    // Converter visitors de List<dynamic> para List<Map<String, dynamic>>
    List<Map<String, dynamic>> visitorsList = [];
    if (data['visitors'] != null) {
      final visitors = data['visitors'] as List<dynamic>;
      visitorsList = visitors.map((v) => Map<String, dynamic>.from(v as Map)).toList();
    }
    
    return LocationRankingModel(
      placeId: docId,
      locationName: data['locationName'] ?? 'Local desconhecido',
      formattedAddress: data['formattedAddress'] ?? '',
      locality: data['locality'] as String?,
      totalEventsHosted: data['totalEventsHosted'] ?? 0,
      totalVisitors: data['totalVisitors'] ?? 0,
      visitors: visitorsList,
      lastEventAt: timestamp?.toDate(),
      lastLat: data['lastLat']?.toDouble(),
      lastLng: data['lastLng']?.toDouble(),
      photoReferences: photoRefs,
    );
  }

  /// Converte para Map (para salvar no Firestore)
  Map<String, dynamic> toMap() {
    return {
      'placeId': placeId,
      'locationName': locationName,
      'formattedAddress': formattedAddress,
      if (locality != null) 'locality': locality,
      'totalEventsHosted': totalEventsHosted,
      'totalVisitors': totalVisitors,
      'visitors': visitors,
      'lastEventAt': lastEventAt != null 
          ? Timestamp.fromDate(lastEventAt!) 
          : FieldValue.serverTimestamp(),
      if (lastLat != null) 'lastLat': lastLat,
      if (lastLng != null) 'lastLng': lastLng,
      'photoReferences': photoReferences,
    };
  }

  /// Verifica se está dentro do raio especificado
  bool isWithinRadius({
    required double userLat,
    required double userLng,
    required double radiusKm,
  }) {
    if (lastLat == null || lastLng == null) return false;
    
    final distance = _calculateDistance(
      userLat, userLng,
      lastLat!, lastLng!,
    );

    return distance <= radiusKm;
  }

  /// Calcula distância até o usuário
  double distanceFrom({
    required double userLat,
    required double userLng,
  }) {
    if (lastLat == null || lastLng == null) return 0.0;
    return _calculateDistance(userLat, userLng, lastLat!, lastLng!);
  }

  /// Calcula distância usando fórmula de Haversine
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371.0;
    
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
        math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) *
        math.sin(dLon / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  @override
  String toString() {
    return 'LocationRankingModel(placeId: $placeId, name: $locationName, totalEvents: $totalEventsHosted)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationRankingModel && other.placeId == placeId;
  }

  @override
  int get hashCode => placeId.hashCode;
}
