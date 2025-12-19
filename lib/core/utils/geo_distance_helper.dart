import 'dart:math';

class GeoDistanceHelper {
  static const double earthRadiusKm = 6371;

  static double distanceInKm(double lat1, double lng1, double lat2, double lng2) {
    // 🚨 VALIDAÇÃO: Detectar coordenadas Web Mercator (bug comum)
    // Lat/Lng válidos: lat entre -90 e +90, lng entre -180 e +180
    assert(
      lat1 >= -90 && lat1 <= 90,
      '🚨 lat1 inválido: $lat1 (esperado: -90 a +90). Possível Web Mercator?',
    );
    assert(
      lat2 >= -90 && lat2 <= 90,
      '🚨 lat2 inválido: $lat2 (esperado: -90 a +90). Possível Web Mercator?',
    );
    assert(
      lng1 >= -180 && lng1 <= 180,
      '🚨 lng1 inválido: $lng1 (esperado: -180 a +180). Possível Web Mercator?',
    );
    assert(
      lng2 >= -180 && lng2 <= 180,
      '🚨 lng2 inválido: $lng2 (esperado: -180 a +180). Possível Web Mercator?',
    );
    
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    return earthRadiusKm * 2 * asin(sqrt(a));
  }

  static double _degToRad(double deg) => deg * pi / 180;
}
