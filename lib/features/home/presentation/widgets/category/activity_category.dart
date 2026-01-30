/// Categorias de atividade para o fluxo de criação
enum ActivityCategory {
  carnaval,
  gastronomy,
  social,
  entertainment,
  culture,
  outdoor,
  sports,
  wellness,
  networking,
  games,
  romance,
  other,
}

/// Modelo de categoria com informações de exibição
class ActivityCategoryInfo {
  final ActivityCategory category;
  final String emoji;
  final String titleKey;
  final String subtitleKey;

  const ActivityCategoryInfo({
    required this.category,
    required this.emoji,
    required this.titleKey,
    required this.subtitleKey,
  });
}

/// Lista de categorias disponíveis
const List<ActivityCategoryInfo> activityCategories = [
  ActivityCategoryInfo(
    category: ActivityCategory.carnaval,
    emoji: '🎭',
    titleKey: 'category_carnaval',
    subtitleKey: 'category_carnaval_subtitle',
  ),
  ActivityCategoryInfo(
    category: ActivityCategory.gastronomy,
    emoji: '🍽️',
    titleKey: 'category_gastronomy',
    subtitleKey: 'category_gastronomy_subtitle',
  ),
  ActivityCategoryInfo(
    category: ActivityCategory.social,
    emoji: '🍷',
    titleKey: 'category_social',
    subtitleKey: 'category_social_subtitle',
  ),
  ActivityCategoryInfo(
    category: ActivityCategory.entertainment,
    emoji: '🎉',
    titleKey: 'category_entertainment',
    subtitleKey: 'category_entertainment_subtitle',
  ),
  ActivityCategoryInfo(
    category: ActivityCategory.culture,
    emoji: '🎨',
    titleKey: 'category_culture',
    subtitleKey: 'category_culture_subtitle',
  ),
  ActivityCategoryInfo(
    category: ActivityCategory.outdoor,
    emoji: '🌳',
    titleKey: 'category_outdoor',
    subtitleKey: 'category_outdoor_subtitle',
  ),
  ActivityCategoryInfo(
    category: ActivityCategory.sports,
    emoji: '⚽',
    titleKey: 'category_sports',
    subtitleKey: 'category_sports_subtitle',
  ),
  ActivityCategoryInfo(
    category: ActivityCategory.wellness,
    emoji: '🧘',
    titleKey: 'category_wellness',
    subtitleKey: 'category_wellness_subtitle',
  ),
  ActivityCategoryInfo(
    category: ActivityCategory.networking,
    emoji: '💼',
    titleKey: 'category_networking',
    subtitleKey: 'category_networking_subtitle',
  ),
  ActivityCategoryInfo(
    category: ActivityCategory.games,
    emoji: '🎲',
    titleKey: 'category_games',
    subtitleKey: 'category_games_subtitle',
  ),
  ActivityCategoryInfo(
    category: ActivityCategory.romance,
    emoji: '❤️',
    titleKey: 'category_romance',
    subtitleKey: 'category_romance_subtitle',
  ),
  ActivityCategoryInfo(
    category: ActivityCategory.other,
    emoji: '✨',
    titleKey: 'category_other',
    subtitleKey: 'category_other_subtitle',
  ),
];

/// Retorna o ID string da categoria para salvar no Firestore
String categoryToString(ActivityCategory category) {
  switch (category) {
    case ActivityCategory.carnaval:
      return 'carnaval';
    case ActivityCategory.gastronomy:
      return 'gastronomy';
    case ActivityCategory.social:
      return 'social';
    case ActivityCategory.entertainment:
      return 'entertainment';
    case ActivityCategory.culture:
      return 'culture';
    case ActivityCategory.outdoor:
      return 'outdoor';
    case ActivityCategory.sports:
      return 'sports';
    case ActivityCategory.wellness:
      return 'wellness';
    case ActivityCategory.networking:
      return 'networking';
    case ActivityCategory.games:
      return 'games';
    case ActivityCategory.romance:
      return 'romance';
    case ActivityCategory.other:
      return 'other';
  }
}

/// Converte string do Firestore para enum
ActivityCategory? categoryFromString(String? value) {
  if (value == null) return null;
  switch (value) {
    case 'carnaval':
      return ActivityCategory.carnaval;
    case 'gastronomy':
      return ActivityCategory.gastronomy;
    case 'social':
      return ActivityCategory.social;
    case 'entertainment':
      return ActivityCategory.entertainment;
    case 'culture':
      return ActivityCategory.culture;
    case 'outdoor':
      return ActivityCategory.outdoor;
    case 'sports':
      return ActivityCategory.sports;
    case 'wellness':
      return ActivityCategory.wellness;
    case 'networking':
      return ActivityCategory.networking;
    case 'games':
      return ActivityCategory.games;
    case 'romance':
      return ActivityCategory.romance;
    case 'other':
      return ActivityCategory.other;
    default:
      return null;
  }
}

/// Retorna a info da categoria pelo enum
ActivityCategoryInfo? getCategoryInfo(ActivityCategory category) {
  try {
    return activityCategories.firstWhere((c) => c.category == category);
  } catch (_) {
    return null;
  }
}
