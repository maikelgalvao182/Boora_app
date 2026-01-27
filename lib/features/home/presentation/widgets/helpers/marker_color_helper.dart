import 'dart:ui';

/// Helper para fornecer cores dinâmicas para os containers de emojis dos markers
class MarkerColorHelper {
  /// Paleta de cores disponíveis para os markers
  static const List<Color> _colors = [
    Color(0xFFA9DCFF), // Azul claro
    Color(0xFFDCD3FF), // Roxo claro
    Color(0xFFA3EDC7), // Verde claro
    Color(0xFFF8F7A9), // Amarelo claro
    Color(0xFFFBDCA9), // Laranja claro
    Color(0xFFFFD3F6), // Rosa claro
  ];

  /// Retorna uma cor baseada em um ID ou string
  /// 
  /// Usa o hashCode para garantir que o mesmo ID sempre retorne a mesma cor
  static Color getColorForId(String id) {
    final index = _stableHash(id) % _colors.length;
    return _colors[index];
  }

  /// Hash estável (FNV-1a) para evitar concentração em uma cor
  static int _stableHash(String input) {
    const int fnvOffset = 0x811C9DC5;
    const int fnvPrime = 0x01000193;
    var hash = fnvOffset;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0x7fffffff;
    }
    return hash.abs();
  }

  /// Retorna uma cor baseada no índice de um evento na lista
  /// 
  /// Útil quando você quer distribuir cores sequencialmente
  static Color getColorByIndex(int index) {
    return _colors[index % _colors.length];
  }

  /// Retorna uma cor aleatória da paleta
  static Color getRandomColor() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _colors[now % _colors.length];
  }

  /// Retorna todas as cores disponíveis
  static List<Color> getAllColors() {
    return List.unmodifiable(_colors);
  }

  /// Retorna a quantidade de cores disponíveis
  static int get colorCount => _colors.length;
}
