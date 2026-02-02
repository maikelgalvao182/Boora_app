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
  /// 
  /// ✅ FIX: Trata wrap de longitude (ex: bounds de 170° a -170°)
  bool contains(double lat, double lng) {
    // Latitude sempre é simples
    if (lat < minLat || lat > maxLat) return false;
    
    // Longitude: caso normal (minLng <= maxLng)
    if (minLng <= maxLng) {
      return lng >= minLng && lng <= maxLng;
    }
    
    // Longitude: caso wrap (ex: minLng=170, maxLng=-170)
    // Neste caso, lng é válido se >= minLng OU <= maxLng
    return lng >= minLng || lng <= maxLng;
  }
  
  /// Verifica se longitude está dentro dos bounds (helper para debug)
  bool containsLng(double lng) {
    if (minLng <= maxLng) {
      return lng >= minLng && lng <= maxLng;
    }
    return lng >= minLng || lng <= maxLng;
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
  /// Usa floor() para grid consistente (não round!).
  /// Inclui bucket de span para evitar colisão entre zoom-in e zoom-out.
  String toQuadkey({int precision = 2}) {
    final centerLat = (minLat + maxLat) / 2.0;
    final centerLng = (minLng + maxLng) / 2.0;
    
    // ✅ FIX: Usar floor() com gridSize para tiles consistentes
    // round() causa instabilidade em coordenadas negativas
    final gridSize = 1.0 / precision;
    final latKey = (centerLat / gridSize).floor();
    final lngKey = (centerLng / gridSize).floor();

    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    final spanBucket = _spanBucket(latSpan, lngSpan);

    return '${latKey}_${lngKey}_$spanBucket';
  }

  /// Gera chave de cache com zoomBucket explícito e versão do schema.
  /// 
  /// Formato: "events:{tileLat}_{tileLng}_s{spanKey}:zb{zoomBucket}:v{schemaVersion}"
  /// 
  /// ✅ FIX v5: spanKey de volta (quantizado em 0.1° steps)
  /// Evita que "SP inteiro" e "meio estado" caiam na mesma key.
  /// Precision dinâmico por zoomBucket:
  /// - zoomBucket 0: grid 1.0° (~111km)
  /// - zoomBucket 1: grid 0.25° (~28km)
  /// - zoomBucket 2: grid 0.10° (~11km)
  /// - zoomBucket 3: grid 0.05° (~5.5km)
  static const int _cacheSchemaVersion = 5; // ✅ v5: spanKey de volta
  
  String toCacheKey({required int zoomBucket}) {
    final precision = _precisionForZoomBucket(zoomBucket);
    final gridSize = 1.0 / precision;
    
    final centerLat = (minLat + maxLat) / 2.0;
    final centerLng = (minLng + maxLng) / 2.0;
    
    final tileLat = (centerLat / gridSize).floor();
    final tileLng = (centerLng / gridSize).floor();
    
    // ✅ spanKey quantizado em 0.1° steps (~11km)
    final latSpan = (maxLat - minLat).abs();
    final spanKey = (latSpan * 10).round();
    
    return 'events:${tileLat}_${tileLng}_s$spanKey:zb$zoomBucket:v$_cacheSchemaVersion';
  }
  
  /// Precision dinâmico baseado no zoomBucket
  static int _precisionForZoomBucket(int zoomBucket) {
    switch (zoomBucket) {
      case 0: return 1;  // grid 1.0° (~111km tiles)
      case 1: return 4;  // grid 0.25° (~28km tiles)
      case 2: return 10; // grid 0.10° (~11km tiles)
      case 3: return 20; // grid 0.05° (~5.5km tiles)
      default: return 10;
    }
  }

  int _spanBucket(double latSpan, double lngSpan) {
    final span = (latSpan + lngSpan) / 2.0;
    if (span > 5) return 1;
    if (span > 2) return 2;
    if (span > 1) return 3;
    if (span > 0.5) return 4;
    if (span > 0.25) return 5;
    if (span > 0.1) return 6;
    return 7;
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
