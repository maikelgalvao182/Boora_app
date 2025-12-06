/// Critérios de avaliação para reviews
/// Mesmos critérios para owner e participantes
class ReviewCriteria {
  static const String conversation = 'conversation';
  static const String energy = 'energy';
  static const String coexistence = 'coexistence';
  static const String participation = 'participation';

  static const List<Map<String, String>> all = [
    {
      'key': conversation,
      'icon': '💬',
      'title': 'Papo & Conexão',
      'description': 'Conseguiu manter uma boa conversa e criar conexão?',
    },
    {
      'key': energy,
      'icon': '⚡',
      'title': 'Energia & Presença',
      'description': 'Estava presente e engajado durante o evento?',
    },
    {
      'key': coexistence,
      'icon': '🤝',
      'title': 'Convivência',
      'description': 'Foi agradável e respeitoso com todos?',
    },
    {
      'key': participation,
      'icon': '🎯',
      'title': 'Participação',
      'description': 'Participou ativamente das atividades?',
    },
  ];

  static Map<String, String>? getCriterion(String key) {
    try {
      return all.firstWhere((c) => c['key'] == key);
    } catch (_) {
      return null;
    }
  }

  static String getTitle(String key) {
    final criterion = getCriterion(key);
    return criterion?['title'] ?? key;
  }

  static String getIcon(String key) {
    final criterion = getCriterion(key);
    return criterion?['icon'] ?? '⭐';
  }
}
