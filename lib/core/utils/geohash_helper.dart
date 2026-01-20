/// Helper para cálculo de geohash
/// 
/// Geohash é uma codificação que transforma latitude/longitude em uma string.
/// Strings que começam com os mesmos caracteres estão geograficamente próximas.
/// 
/// Exemplo:
/// - São Paulo: "6gycfq..."
/// - Rio de Janeiro: "75cm2f..."
/// 
/// Precisão por comprimento:
/// - 4 chars: ~40km x 20km
/// - 5 chars: ~5km x 5km
/// - 6 chars: ~1.2km x 0.6km
/// - 7 chars: ~150m x 150m
/// - 8 chars: ~40m x 20m
class GeohashHelper {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Calcula o geohash para uma coordenada
  /// 
  /// [latitude] Latitude em graus (-90 a 90)
  /// [longitude] Longitude em graus (-180 a 180)
  /// [precision] Número de caracteres (padrão: 9, ~5m de precisão)
  /// 
  /// Retorna string vazia se coordenadas inválidas
  static String encode(double latitude, double longitude, {int precision = 9}) {
    // Validação
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return '';
    }

    double minLat = -90.0;
    double maxLat = 90.0;
    double minLng = -180.0;
    double maxLng = 180.0;

    final buffer = StringBuffer();
    int bits = 0;
    int hashValue = 0;
    bool isEven = true;

    while (buffer.length < precision) {
      if (isEven) {
        final mid = (minLng + maxLng) / 2;
        if (longitude >= mid) {
          hashValue = (hashValue << 1) + 1;
          minLng = mid;
        } else {
          hashValue = (hashValue << 1);
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (latitude >= mid) {
          hashValue = (hashValue << 1) + 1;
          minLat = mid;
        } else {
          hashValue = (hashValue << 1);
          maxLat = mid;
        }
      }

      isEven = !isEven;
      bits++;

      if (bits == 5) {
        buffer.write(_base32[hashValue]);
        bits = 0;
        hashValue = 0;
      }
    }

    return buffer.toString();
  }

  /// Decodifica um geohash para coordenadas aproximadas (centro do retângulo)
  /// 
  /// Retorna null se geohash inválido
  static ({double latitude, double longitude})? decode(String geohash) {
    if (geohash.isEmpty) return null;

    double minLat = -90.0;
    double maxLat = 90.0;
    double minLng = -180.0;
    double maxLng = 180.0;

    bool isEven = true;

    for (int i = 0; i < geohash.length; i++) {
      final c = geohash[i];
      final cd = _base32.indexOf(c);
      if (cd == -1) return null;

      for (int j = 4; j >= 0; j--) {
        final mask = 1 << j;
        if (isEven) {
          if ((cd & mask) != 0) {
            minLng = (minLng + maxLng) / 2;
          } else {
            maxLng = (minLng + maxLng) / 2;
          }
        } else {
          if ((cd & mask) != 0) {
            minLat = (minLat + maxLat) / 2;
          } else {
            maxLat = (minLat + maxLat) / 2;
          }
        }
        isEven = !isEven;
      }
    }

    return (
      latitude: (minLat + maxLat) / 2,
      longitude: (minLng + maxLng) / 2,
    );
  }

  /// Calcula os geohashes vizinhos (para queries de bounds)
  /// 
  /// Retorna lista de geohashes que cobrem uma área ao redor do centro
  static List<String> getNeighbors(String geohash) {
    if (geohash.isEmpty) return [];

    final decoded = decode(geohash);
    if (decoded == null) return [geohash];

    final precision = geohash.length;
    
    // Calcula offset aproximado baseado na precisão
    // Cada char representa ~bits de precisão
    final latOffset = 90.0 / (1 << (precision * 5 ~/ 2));
    final lngOffset = 180.0 / (1 << (precision * 5 ~/ 2));

    final neighbors = <String>[];
    
    for (int dlat = -1; dlat <= 1; dlat++) {
      for (int dlng = -1; dlng <= 1; dlng++) {
        final newLat = decoded.latitude + (dlat * latOffset * 2);
        final newLng = decoded.longitude + (dlng * lngOffset * 2);
        
        if (newLat >= -90 && newLat <= 90 && newLng >= -180 && newLng <= 180) {
          final hash = encode(newLat, newLng, precision: precision);
          if (hash.isNotEmpty && !neighbors.contains(hash)) {
            neighbors.add(hash);
          }
        }
      }
    }

    return neighbors;
  }

  /// Calcula o prefixo de geohash para uma área de bounds
  /// 
  /// Encontra o maior prefixo comum que cobre ambos os cantos
  /// Útil para queries de range
  static String getBoundsPrefix({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) {
    final sw = encode(minLat, minLng, precision: 9);
    final ne = encode(maxLat, maxLng, precision: 9);

    if (sw.isEmpty || ne.isEmpty) return '';

    // Encontra prefixo comum
    int i = 0;
    while (i < sw.length && i < ne.length && sw[i] == ne[i]) {
      i++;
    }

    return sw.substring(0, i);
  }
}
