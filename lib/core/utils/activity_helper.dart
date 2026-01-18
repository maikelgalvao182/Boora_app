import 'package:partiu/core/constants/glimpse_variables.dart';

/// Helper para operações relacionadas a atividades e sugestões
class ActivityHelper {
  /// Retorna o emoji correspondente à chave de sugestão.
  /// Se não encontrar, retorna o emoji padrão 🎉.
  static String getEmojiForSuggestionKey(String textKey) {
    final suggestion = activitySuggestions.firstWhere(
      (s) => s.textKey == textKey,
      orElse: () => const ActivitySuggestion('🎉', ''),
    );
    return suggestion.emoji;
  }

  /// Compatibilidade: se receber uma key (prefixo `activity_suggestion_`), tenta resolver.
  /// Caso contrário, retorna 🎉 (não é possível mapear texto localizado com segurança aqui).
  static String getEmojiForActivity(String activityTextOrKey) {
    final text = activityTextOrKey.trim();
    if (text.startsWith('activity_suggestion_')) {
      return getEmojiForSuggestionKey(text);
    }
    return '🎉';
  }
}
