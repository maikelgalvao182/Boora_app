import 'package:partiu/core/constants/glimpse_variables.dart';

/// Helper para operações relacionadas a atividades e sugestões
class ActivityHelper {
  /// Retorna o emoji correspondente ao texto da atividade
  /// Se não encontrar, retorna o emoji padrão 🎉
  static String getEmojiForActivity(String activityText) {
    final suggestion = activitySuggestions.firstWhere(
      (s) => s.text == activityText,
      orElse: () => const ActivitySuggestion('🎉', ''),
    );
    return suggestion.emoji;
  }
}
