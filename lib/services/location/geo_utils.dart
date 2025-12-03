import 'dart:math';

/// Utilitários para cálculos geoespaciais
/// 
/// Funcionalidades:
/// - Cálculo de distância (Haversine)
/// - Bounding box para queries otimizadas
/// - Conversão de coordenadas
class GeoUtils {
  /// Raio da Terra em quilômetros
  static const double earthRadiusKm = 6371.0;

  /// Calcula distância entre dois pontos usando fórmula de Haversine
  /// 
  /// Retorna distância em quilômetros
  static double calculateDistance({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Calcula bounding box para uma coordenada e raio
  /// 
  /// Retorna: {
  ///   'minLat': double,
  ///   'maxLat': double,
  ///   'minLng': double,
  ///   'maxLng': double,
  /// }
  /// 
  /// Usado para queries Firestore otimizadas
  static Map<String, double> calculateBoundingBox({
    required double centerLat,
    required double centerLng,
    required double radiusKm,
  }) {
    // Cálculo simplificado de bounding box
    // 1 grau de latitude ≈ 111 km
    // 1 grau de longitude varia com latitude
    
    final latDelta = radiusKm / 111.0;
    final lngDelta = radiusKm / (111.0 * cos(_toRadians(centerLat)));

    return {
      'minLat': centerLat - latDelta,
      'maxLat': centerLat + latDelta,
      'minLng': centerLng - lngDelta,
      'maxLng': centerLng + lngDelta,
    };
  }

  /// Verifica se um ponto está dentro do raio
  static bool isWithinRadius({
    required double centerLat,
    required double centerLng,
    required double pointLat,
    required double pointLng,
    required double radiusKm,
  }) {
    final distance = calculateDistance(
      lat1: centerLat,
      lng1: centerLng,
      lat2: pointLat,
      lng2: pointLng,
    );
    return distance <= radiusKm;
  }

  /// Converte graus para radianos
  static double _toRadians(double degrees) {
    return degrees * pi / 180.0;
  }

  /// Converte radianos para graus
  static double toDegrees(double radians) {
    return radians * 180.0 / pi;
  }
}

/// Classe para representar um ponto geoespacial
class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint({
    required this.latitude,
    required this.longitude,
  });

  /// Calcula distância até outro ponto
  double distanceTo(GeoPoint other) {
    return GeoUtils.calculateDistance(
      lat1: latitude,
      lng1: longitude,
      lat2: other.latitude,
      lng2: other.longitude,
    );
  }

  /// Verifica se está dentro do raio de outro ponto
  bool isWithinRadiusOf(GeoPoint center, double radiusKm) {
    return distanceTo(center) <= radiusKm;
  }

  @override
  String toString() => 'GeoPoint(lat: $latitude, lng: $longitude)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeoPoint &&
        other.latitude == latitude &&
        other.longitude == longitude;
  }

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}
