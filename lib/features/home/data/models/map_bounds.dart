import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Representa um bounding box do mapa para queries geográficas
/// 
/// Usado para buscar eventos dentro de uma região visível do mapa.
/// Implementa o padrão Airbnb de bounded queries.
class MapBounds {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const MapBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  /// Cria MapBounds a partir de LatLngBounds do Google Maps
  factory MapBounds.fromLatLngBounds(LatLngBounds bounds) {
    return MapBounds(
      minLat: bounds.southwest.latitude,
      maxLat: bounds.northeast.latitude,
      minLng: bounds.southwest.longitude,
      maxLng: bounds.northeast.longitude,
    );
  }

  /// Verifica se um ponto está dentro dos bounds
  bool contains(double lat, double lng) {
    return lat >= minLat && 
           lat <= maxLat && 
           lng >= minLng && 
           lng <= maxLng;
  }

  /// Calcula área aproximada em km²
  double get areaKm2 {
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    // Aproximação simples: 111 km por grau
    return (latDiff * 111) * (lngDiff * 111);
  }

  /// Gera um quadkey para cache (simplificado)
  /// 
  /// Arredonda coordenadas para criar uma chave única
  /// baseada na região (precisão de ~1km)
  String toQuadkey({int precision = 2}) {
    final latKey = (minLat + maxLat) ~/ 2 * precision;
    final lngKey = (minLng + maxLng) ~/ 2 * precision;
    return '${latKey}_$lngKey';
  }

  @override
  String toString() {
    return 'MapBounds(lat: $minLat to $maxLat, lng: $minLng to $maxLng)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MapBounds &&
        other.minLat == minLat &&
        other.maxLat == maxLat &&
        other.minLng == minLng &&
        other.maxLng == maxLng;
  }

  @override
  int get hashCode {
    return Object.hash(minLat, maxLat, minLng, maxLng);
  }
}
