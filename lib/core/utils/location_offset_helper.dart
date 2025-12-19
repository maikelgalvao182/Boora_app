import 'dart:math';

/// Utilitário para gerar offset de localização determinístico
/// 
/// Gera coordenadas display com offset aleatório mas reprodutível
/// para proteger a privacidade do usuário.
class LocationOffsetHelper {
  /// Raio mínimo do offset (em metros)
  static const double minOffsetMeters = 300;
  
  /// Raio máximo do offset (em metros)
  static const double maxOffsetMeters = 1500;
  
  /// Raio da Terra (em km)
  static const double earthRadiusKm = 6371;
  
  /// Gera um número pseudo-aleatório determinístico baseado em uma string seed
  static double _seededRandom(String seed, int index) {
    // Combina seed + index para gerar diferentes valores da mesma seed
    final combined = '$seed-$index';
    
    // Hash simples mas eficaz
    int hash = 0;
    for (int i = 0; i < combined.length; i++) {
      final char = combined.codeUnitAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }
    
    // Normaliza para [0, 1] - usa máscara para evitar overflow do abs()
    // hash.abs() pode ser 2147483648 (overflow), então usamos bitwise AND
    final normalized = (hash & 0x7fffffff) / 2147483647;
    return normalized;
  }
  
  /// Calcula coordenadas display com offset determinístico
  /// 
  /// Regras:
  /// - Offset mínimo: 300 metros
  /// - Offset máximo: 1500 metros (1.5 km)
  /// - Direção aleatória mas fixa por userId
  /// - Reprodutível (mesmo input = mesmo output)
  /// 
  /// Throws [ArgumentError] se coordenadas estiverem fora dos limites válidos
  static Map<String, double> generateDisplayLocation({
    required double realLat,
    required double realLng,
    required String userId,
  }) {
    // 🚨 VALIDAÇÃO CRÍTICA: Garantir que coordenadas são lat/lng em graus, não Web Mercator
    if (realLat < -90 || realLat > 90) {
      throw ArgumentError(
        '🚨 ERRO CRÍTICO: Latitude inválida: $realLat\n'
        'Latitude deve estar entre -90 e +90 graus.\n'
        'Valor recebido parece ser coordenada projetada (Web Mercator), não latitude em graus.',
      );
    }
    
    if (realLng < -180 || realLng > 180) {
      throw ArgumentError(
        '🚨 ERRO CRÍTICO: Longitude inválida: $realLng\n'
        'Longitude deve estar entre -180 e +180 graus.\n'
        'Valor recebido parece ser coordenada projetada (Web Mercator), não longitude em graus.',
      );
    }
    
    if (userId.isEmpty) {
      throw ArgumentError('userId não pode ser vazio');
    }
    
    // Gera valores determinísticos baseados no userId
    final random1 = _seededRandom(userId, 0); // Para distância
    final random2 = _seededRandom(userId, 1); // Para ângulo
    
    // Calcula distância do offset (entre 300m e 1500m)
    final offsetMeters = minOffsetMeters + (random1 * (maxOffsetMeters - minOffsetMeters));
    final offsetKm = offsetMeters / 1000;
    
    // Calcula ângulo aleatório (0 a 360 graus)
    final angle = random2 * 2 * pi;
    
    // Converte offset para graus
    // 1 grau de latitude ≈ 111 km
    // 1 grau de longitude varia com a latitude
    final latOffset = (offsetKm / earthRadiusKm) * (180 / pi);
    final lngOffset = (offsetKm / earthRadiusKm) * (180 / pi) / cos(realLat * pi / 180);
    
    // Aplica offset na direção do ângulo
    final displayLatitude = realLat + (latOffset * cos(angle));
    final displayLongitude = realLng + (lngOffset * sin(angle));
    
    // 🚨 VALIDAÇÃO PÓS-CÁLCULO: Garantir que resultado também é válido
    if (displayLatitude < -90 || displayLatitude > 90) {
      throw StateError(
        '🚨 BUG NO ALGORITMO: displayLatitude calculada está fora do range: $displayLatitude\n'
        'Input: realLat=$realLat, realLng=$realLng\n'
        'Isso indica um bug no cálculo do offset.',
      );
    }
    
    if (displayLongitude < -180 || displayLongitude > 180) {
      throw StateError(
        '🚨 BUG NO ALGORITMO: displayLongitude calculada está fora do range: $displayLongitude\n'
        'Input: realLat=$realLat, realLng=$realLng\n'
        'Isso indica um bug no cálculo do offset.',
      );
    }
    
    return {
      'displayLatitude': displayLatitude,
      'displayLongitude': displayLongitude,
    };
  }
}
