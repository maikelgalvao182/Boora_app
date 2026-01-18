/// Constantes e variáveis globais do Partiuu
library;

import 'package:flutter_country_selector/flutter_country_selector.dart';

/// Modelo de interesse/tag
class InterestTag {
  final String id;
  final String icon;
  final String nameKey; // Chave de tradução
  final String category;

  const InterestTag({
    required this.id,
    required this.icon,
    required this.nameKey,
    required this.category,
  });
}

/// Categorias de interesses
class InterestCategory {
  static const food = 'food';
  static const nightlife = 'nightlife';
  static const culture = 'culture';
  static const outdoor = 'outdoor';
  static const sports = 'sports';
  static const work = 'work';
  static const wellness = 'wellness';
  static const values = 'values';
}

/// Lista completa de interesses organizados por categoria
const List<InterestTag> interestListDisplay = [
  // 🍽️ Comida & Gastronomia
  InterestTag(id: 'japanese', icon: '🍣', nameKey: 'interest_japanese', category: InterestCategory.food),
  InterestTag(id: 'pizza', icon: '🍕', nameKey: 'interest_pizza', category: InterestCategory.food),
  InterestTag(id: 'burgers', icon: '🍔', nameKey: 'interest_burgers', category: InterestCategory.food),
  InterestTag(id: 'pasta', icon: '🍝', nameKey: 'interest_pasta', category: InterestCategory.food),
  InterestTag(id: 'beer_pub', icon: '🍻', nameKey: 'interest_beer_pub', category: InterestCategory.food),
  InterestTag(id: 'wines', icon: '🍷', nameKey: 'interest_wines', category: InterestCategory.food),
  InterestTag(id: 'sweets_cafes', icon: '🧁', nameKey: 'interest_sweets_cafes', category: InterestCategory.food),
  InterestTag(id: 'mexican', icon: '🌮', nameKey: 'interest_mexican', category: InterestCategory.food),
  InterestTag(id: 'healthy_food', icon: '🥗', nameKey: 'interest_healthy_food', category: InterestCategory.food),
  InterestTag(id: 'bbq', icon: '🥩', nameKey: 'interest_bbq', category: InterestCategory.food),
  InterestTag(id: 'vegetarian', icon: '🥗', nameKey: 'interest_vegetarian', category: InterestCategory.food),
  InterestTag(id: 'vegan', icon: '🌱', nameKey: 'interest_vegan', category: InterestCategory.food),
  InterestTag(id: 'food_markets', icon: '🛒', nameKey: 'interest_food_markets', category: InterestCategory.food),

  // 🎉 Vida Noturna & Entretenimento
  InterestTag(id: 'live_music_bar', icon: '🎵', nameKey: 'interest_live_music_bar', category: InterestCategory.nightlife),
  InterestTag(id: 'cocktails', icon: '🍸', nameKey: 'interest_cocktails', category: InterestCategory.nightlife),
  InterestTag(id: 'karaoke', icon: '🎤', nameKey: 'interest_karaoke', category: InterestCategory.nightlife),
  InterestTag(id: 'nightclub', icon: '🪩', nameKey: 'interest_nightclub', category: InterestCategory.nightlife),
  InterestTag(id: 'standup_theater', icon: '🎭', nameKey: 'interest_standup_theater', category: InterestCategory.nightlife),
  InterestTag(id: 'cinema', icon: '🎬', nameKey: 'interest_cinema', category: InterestCategory.nightlife),
  InterestTag(id: 'board_games', icon: '🎲', nameKey: 'interest_board_games', category: InterestCategory.nightlife),
  InterestTag(id: 'gaming', icon: '🎮', nameKey: 'interest_gaming', category: InterestCategory.nightlife),
  InterestTag(id: 'themed_parties', icon: '🥳', nameKey: 'interest_themed_parties', category: InterestCategory.nightlife),
  InterestTag(id: 'samba', icon: '🥁', nameKey: 'interest_samba', category: InterestCategory.nightlife),
  InterestTag(id: 'shopping', icon: '🛍️', nameKey: 'interest_shopping', category: InterestCategory.nightlife),

  // 🎨 Cultura & Artes
  InterestTag(id: 'museums', icon: '🎨', nameKey: 'interest_museums', category: InterestCategory.culture),
  InterestTag(id: 'book_club', icon: '📚', nameKey: 'interest_book_club', category: InterestCategory.culture),
  InterestTag(id: 'photography', icon: '📸', nameKey: 'interest_photography', category: InterestCategory.culture),
  InterestTag(id: 'workshops', icon: '✏️', nameKey: 'interest_workshops', category: InterestCategory.culture),
  InterestTag(id: 'concerts', icon: '🎧', nameKey: 'interest_concerts', category: InterestCategory.culture),
  InterestTag(id: 'language_exchange', icon: '🗣️', nameKey: 'interest_language_exchange', category: InterestCategory.culture),
  InterestTag(id: 'film_screenings', icon: '🎥', nameKey: 'interest_film_screenings', category: InterestCategory.culture),
  InterestTag(id: 'street_art', icon: '🎭', nameKey: 'interest_street_art', category: InterestCategory.culture),

  // 🌳 Ar Livre & Aventura
  InterestTag(id: 'light_trails', icon: '🚶', nameKey: 'interest_light_trails', category: InterestCategory.outdoor),
  InterestTag(id: 'parks', icon: '🌳', nameKey: 'interest_parks', category: InterestCategory.outdoor),
  InterestTag(id: 'beach', icon: '☀️', nameKey: 'interest_beach', category: InterestCategory.outdoor),
  InterestTag(id: 'bike', icon: '🚴', nameKey: 'interest_bike', category: InterestCategory.outdoor),
  InterestTag(id: 'climbing', icon: '🧗', nameKey: 'interest_climbing', category: InterestCategory.outdoor),
  InterestTag(id: 'outdoor_activities', icon: '🧘', nameKey: 'interest_outdoor_activities', category: InterestCategory.outdoor),
  InterestTag(id: 'pets', icon: '🐶', nameKey: 'interest_pets', category: InterestCategory.outdoor),
  InterestTag(id: 'sunset', icon: '🌅', nameKey: 'interest_sunset', category: InterestCategory.outdoor),
  InterestTag(id: 'pool', icon: '🏊', nameKey: 'interest_pool', category: InterestCategory.outdoor),
  InterestTag(id: 'camping', icon: '🏕️', nameKey: 'interest_camping', category: InterestCategory.outdoor),

  // ⚽ Esportes
  InterestTag(id: 'soccer', icon: '⚽', nameKey: 'interest_soccer', category: InterestCategory.sports),
  InterestTag(id: 'basketball', icon: '🏀', nameKey: 'interest_basketball', category: InterestCategory.sports),
  InterestTag(id: 'tennis', icon: '🎾', nameKey: 'interest_tennis', category: InterestCategory.sports),
  InterestTag(id: 'beach_tennis', icon: '🏓', nameKey: 'interest_beach_tennis', category: InterestCategory.sports),
  InterestTag(id: 'skating', icon: '🛼', nameKey: 'interest_skating', category: InterestCategory.sports),
  InterestTag(id: 'running', icon: '🏃', nameKey: 'interest_running', category: InterestCategory.sports),
  InterestTag(id: 'cycling', icon: '🚴', nameKey: 'interest_cycling', category: InterestCategory.sports),
  InterestTag(id: 'gym', icon: '🏋️', nameKey: 'interest_gym', category: InterestCategory.sports),
  InterestTag(id: 'light_activities', icon: '🤸', nameKey: 'interest_light_activities', category: InterestCategory.sports),

  // 💼 Trabalho & Estilo de Vida
  InterestTag(id: 'remote_work', icon: '💻', nameKey: 'interest_remote_work', category: InterestCategory.work),
  InterestTag(id: 'content_creators', icon: '🎥', nameKey: 'interest_content_creators', category: InterestCategory.work),
  InterestTag(id: 'career_talks', icon: '💬', nameKey: 'interest_career_talks', category: InterestCategory.work),
  InterestTag(id: 'tech_innovation', icon: '📱', nameKey: 'interest_tech_innovation', category: InterestCategory.work),

  // 🧘 Bem-estar & Saúde
  InterestTag(id: 'yoga', icon: '🧘', nameKey: 'interest_yoga', category: InterestCategory.wellness),
  InterestTag(id: 'meditation', icon: '🧘‍♂️', nameKey: 'interest_meditation', category: InterestCategory.wellness),
  InterestTag(id: 'pilates', icon: '🤸', nameKey: 'interest_pilates', category: InterestCategory.wellness),
  InterestTag(id: 'spa', icon: '💆', nameKey: 'interest_spa', category: InterestCategory.wellness),
  InterestTag(id: 'cold_plunge', icon: '🧊', nameKey: 'interest_cold_plunge', category: InterestCategory.wellness),
  InterestTag(id: 'healthy_lifestyle', icon: '🥗', nameKey: 'interest_healthy_lifestyle', category: InterestCategory.wellness),
  InterestTag(id: 'relaxing_walks', icon: '🚶', nameKey: 'interest_relaxing_walks', category: InterestCategory.wellness),

  // 🤝 Valores & Comunidade
  InterestTag(id: 'lgbtqia', icon: '🌈', nameKey: 'interest_lgbtqia', category: InterestCategory.values),
  InterestTag(id: 'sustainability', icon: '🌱', nameKey: 'interest_sustainability', category: InterestCategory.values),
  InterestTag(id: 'volunteering', icon: '🙌', nameKey: 'interest_volunteering', category: InterestCategory.values),
  InterestTag(id: 'animal_cause', icon: '🐾', nameKey: 'interest_animal_cause', category: InterestCategory.values),
];

/// Retorna os interesses filtrados por categoria
List<InterestTag> getInterestsByCategory(String category) {
  return interestListDisplay.where((interest) => interest.category == category).toList();
}

/// Retorna o InterestTag pelo ID
InterestTag? getInterestById(String id) {
  try {
    return interestListDisplay.firstWhere((interest) => interest.id == id);
  } catch (_) {
    return null;
  }
}

/// Mapa de idiomas para chaves de tradução e bandeiras
final Map<String, LanguageInfo> _languageMap = {
  'portuguese': LanguageInfo('language_portuguese', '🇧🇷'),
  'portugues': LanguageInfo('language_portuguese', '🇧🇷'),
  'português': LanguageInfo('language_portuguese', '🇧🇷'),
  'english': LanguageInfo('language_english', '🇺🇸'),
  'ingles': LanguageInfo('language_english', '🇺🇸'),
  'inglês': LanguageInfo('language_english', '🇺🇸'),
  'spanish': LanguageInfo('language_spanish', '🇪🇸'),
  'espanhol': LanguageInfo('language_spanish', '🇪🇸'),
  'español': LanguageInfo('language_spanish', '🇪🇸'),
  'french': LanguageInfo('language_french', '🇫🇷'),
  'frances': LanguageInfo('language_french', '🇫🇷'),
  'francês': LanguageInfo('language_french', '🇫🇷'),
  'german': LanguageInfo('language_german', '🇩🇪'),
  'alemao': LanguageInfo('language_german', '🇩🇪'),
  'alemão': LanguageInfo('language_german', '🇩🇪'),
  'italian': LanguageInfo('language_italian', '🇮🇹'),
  'italiano': LanguageInfo('language_italian', '🇮🇹'),
  'chinese': LanguageInfo('language_chinese', '🇨🇳'),
  'chines': LanguageInfo('language_chinese', '🇨🇳'),
  'chinês': LanguageInfo('language_chinese', '🇨🇳'),
  'japanese': LanguageInfo('language_japanese', '🇯🇵'),
  'japones': LanguageInfo('language_japanese', '🇯🇵'),
  'japonês': LanguageInfo('language_japanese', '🇯🇵'),
  'korean': LanguageInfo('language_korean', '🇰🇷'),
  'coreano': LanguageInfo('language_korean', '🇰🇷'),
  'russian': LanguageInfo('language_russian', '🇷🇺'),
  'russo': LanguageInfo('language_russian', '🇷🇺'),
  'arabic': LanguageInfo('language_arabic', '🇸🇦'),
  'arabe': LanguageInfo('language_arabic', '🇸🇦'),
  'árabe': LanguageInfo('language_arabic', '🇸🇦'),
  'hindi': LanguageInfo('language_hindi', '🇮🇳'),
  'dutch': LanguageInfo('language_dutch', '🇳🇱'),
  'holandes': LanguageInfo('language_dutch', '🇳🇱'),
  'holandês': LanguageInfo('language_dutch', '🇳🇱'),
  'swedish': LanguageInfo('language_swedish', '🇸🇪'),
  'sueco': LanguageInfo('language_swedish', '🇸🇪'),
  'norwegian': LanguageInfo('language_norwegian', '🇳🇴'),
  'noruegues': LanguageInfo('language_norwegian', '🇳🇴'),
  'norueguês': LanguageInfo('language_norwegian', '🇳🇴'),
  'danish': LanguageInfo('language_danish', '🇩🇰'),
  'dinamarques': LanguageInfo('language_danish', '🇩🇰'),
  'dinamarquês': LanguageInfo('language_danish', '🇩🇰'),
  'finnish': LanguageInfo('language_finnish', '🇫🇮'),
  'finlandes': LanguageInfo('language_finnish', '🇫🇮'),
  'finlandês': LanguageInfo('language_finnish', '🇫🇮'),
  'polish': LanguageInfo('language_polish', '🇵🇱'),
  'polones': LanguageInfo('language_polish', '🇵🇱'),
  'polonês': LanguageInfo('language_polish', '🇵🇱'),
  'turkish': LanguageInfo('language_turkish', '🇹🇷'),
  'turco': LanguageInfo('language_turkish', '🇹🇷'),
  'greek': LanguageInfo('language_greek', '🇬🇷'),
  'grego': LanguageInfo('language_greek', '🇬🇷'),
  'hebrew': LanguageInfo('language_hebrew', '🇮🇱'),
  'hebraico': LanguageInfo('language_hebrew', '🇮🇱'),
};

/// Modelo de informações de idioma
class LanguageInfo {
  final String translationKey;
  final String flag;

  const LanguageInfo(this.translationKey, this.flag);
}

/// Retorna a chave de tradução para um idioma
String? getLanguageKey(String language) {
  final normalized = language.toLowerCase().trim();
  return _languageMap[normalized]?.translationKey;
}

/// Retorna a bandeira emoji para um idioma
String? getLanguageFlag(String language) {
  final normalized = language.toLowerCase().trim();
  return _languageMap[normalized]?.flag;
}

/// Retorna informações completas do idioma (chave + bandeira)
LanguageInfo? getLanguageInfo(String language) {
  final normalized = language.toLowerCase().trim();
  return _languageMap[normalized];
}

// ========== PAÍSES (FROM/ORIGEM) ==========

/// Modelo de informações de país
class CountryInfo {
  final String translationKey;
  final String flagCode; // Código ISO do país (ex: "BR", "US")

  const CountryInfo(this.translationKey, this.flagCode);
}

/// Retorna informações do país usando flutter_country_selector
/// [countryName] pode ser o nome do país em qualquer idioma ou o código ISO
CountryInfo? getCountryInfo(String countryName) {
  if (countryName.isEmpty) return null;
  
  final normalized = countryName.trim();
  
  // Tenta encontrar pelo código ISO primeiro (ex: "BR", "US")
  if (normalized.length == 2) {
    try {
      final isoCode = IsoCode.values.firstWhere(
        (code) => code.name.toUpperCase() == normalized.toUpperCase(),
      );
      return CountryInfo('country_${isoCode.name.toLowerCase()}', isoCode.name);
    } catch (_) {
      // Se não encontrar, continua para busca por nome
    }
  }
  
  // Mapeia nomes comuns para códigos ISO
  final nameToIsoMap = {
    // Português
    'brasil': 'BR',
    'estados unidos': 'US',
    'argentina': 'AR',
    'méxico': 'MX',
    'mexico': 'MX',
    'colômbia': 'CO',
    'colombia': 'CO',
    'chile': 'CL',
    'peru': 'PE',
    'uruguai': 'UY',
    'uruguaí': 'UY',
    'paraguai': 'PY',
    'venezuela': 'VE',
    'bolívia': 'BO',
    'bolivia': 'BO',
    'equador': 'EC',
    'portugal': 'PT',
    'espanha': 'ES',
    'frança': 'FR',
    'franca': 'FR',
    'itália': 'IT',
    'italia': 'IT',
    'alemanha': 'DE',
    'reino unido': 'GB',
    'inglaterra': 'GB',
    'canadá': 'CA',
    'canada': 'CA',
    'austrália': 'AU',
    'australia': 'AU',
    'china': 'CN',
    'japão': 'JP',
    'japao': 'JP',
    'coreia do sul': 'KR',
    'índia': 'IN',
    'india': 'IN',
    'rússia': 'RU',
    'russia': 'RU',
    'áfrica do sul': 'ZA',
    'africa do sul': 'ZA',
    
    // English
    'brazil': 'BR',
    'united states': 'US',
    'usa': 'US',
    'eua': 'US',
    'uruguay': 'UY',
    'paraguay': 'PY',
    'ecuador': 'EC',
    'spain': 'ES',
    'france': 'FR',
    'italy': 'IT',
    'germany': 'DE',
    'united kingdom': 'GB',
    'uk': 'GB',
    'england': 'GB',
    'japan': 'JP',
    'south korea': 'KR',
    'south africa': 'ZA',
    
    // Español
    'españa': 'ES',
    'francia': 'FR',
    'alemania': 'DE',
    'japón': 'JP',
    'corea del sur': 'KR',
    'sudáfrica': 'ZA',
  };
  
  final normalizedLower = normalized.toLowerCase();
  final isoCodeStr = nameToIsoMap[normalizedLower];
  
  if (isoCodeStr != null) {
    return CountryInfo('country_${isoCodeStr.toLowerCase()}', isoCodeStr);
  }

  return null;
}

/// Retorna o código da bandeira (código ISO) para usar com CircleFlag
String? getCountryFlag(String countryName) {
  return getCountryInfo(countryName)?.flagCode;
}

/// Retorna a chave de tradução para um país
String? getCountryKey(String countryName) {
  return getCountryInfo(countryName)?.translationKey;
}

/// Modelo de sugestão de atividade
class ActivitySuggestion {
  final String textKey;
  final String emoji;

  const ActivitySuggestion(this.emoji, this.textKey);
}

/// Lista de sugestões de atividades
const List<ActivitySuggestion> activitySuggestions = [
  // Ao ar livre / atividade física
  ActivitySuggestion('🏃', 'activity_suggestion_run_in_park'),
  ActivitySuggestion('🏋️', 'activity_suggestion_workout_gym'),
  ActivitySuggestion('🚶', 'activity_suggestion_take_a_walk'),
  ActivitySuggestion('🧘', 'activity_suggestion_do_yoga'),
  ActivitySuggestion('🚴', 'activity_suggestion_bike_in_city'),
  ActivitySuggestion('🐕', 'activity_suggestion_walk_the_dog'),

  // Bebidas / Rolês leves
  ActivitySuggestion('☕', 'activity_suggestion_have_coffee'),
  ActivitySuggestion('🍺', 'activity_suggestion_have_draft_beer'),
  ActivitySuggestion('🍷', 'activity_suggestion_drink_wine'),
  ActivitySuggestion('🥤', 'activity_suggestion_have_acai'),
  ActivitySuggestion('🍹', 'activity_suggestion_have_a_drink'),
  ActivitySuggestion('🧋', 'activity_suggestion_have_bubble_tea'),

  // Comida
  ActivitySuggestion('🍕', 'activity_suggestion_eat_pizza'),
  ActivitySuggestion('🍔', 'activity_suggestion_eat_burger'),
  ActivitySuggestion('🍣', 'activity_suggestion_eat_sushi'),
  ActivitySuggestion('🍝', 'activity_suggestion_dinner_out'),
  ActivitySuggestion('🌮', 'activity_suggestion_eat_tacos'),
  ActivitySuggestion('🥗', 'activity_suggestion_light_meal'),

  // Casa / geek
  ActivitySuggestion('🎬', 'activity_suggestion_go_to_cinema'),
  ActivitySuggestion('📺', 'activity_suggestion_watch_a_movie'),
  ActivitySuggestion('🎮', 'activity_suggestion_play_video_games'),
  ActivitySuggestion('🎲', 'activity_suggestion_play_board_games'),
  ActivitySuggestion('🎤', 'activity_suggestion_go_to_karaoke'),
  ActivitySuggestion('🎯', 'activity_suggestion_play_darts'),

  // Arte / cultura
  ActivitySuggestion('📸', 'activity_suggestion_take_photos'),
  ActivitySuggestion('🖼️', 'activity_suggestion_visit_museum'),
  ActivitySuggestion('🎨', 'activity_suggestion_do_something_artistic'),
  ActivitySuggestion('📚', 'activity_suggestion_read_a_book'),
  ActivitySuggestion('🧩', 'activity_suggestion_do_a_puzzle'),
  ActivitySuggestion('🎹', 'activity_suggestion_play_an_instrument'),

  // Sociais / rolê leve
  ActivitySuggestion('🛍️', 'activity_suggestion_walk_in_the_mall'),
  ActivitySuggestion('🛒', 'activity_suggestion_go_shopping'),
  ActivitySuggestion('🌳', 'activity_suggestion_have_a_picnic'),
  ActivitySuggestion('🧺', 'activity_suggestion_sit_in_square_and_talk'),

  // Jogos físicos
  ActivitySuggestion('🎳', 'activity_suggestion_go_bowling'),
  ActivitySuggestion('🎱', 'activity_suggestion_play_pool'),
  ActivitySuggestion('🏓', 'activity_suggestion_play_ping_pong'),
  ActivitySuggestion('⛳', 'activity_suggestion_play_mini_golf'),

  // Passeios
  ActivitySuggestion('🚗', 'activity_suggestion_drive_around_city'),
  ActivitySuggestion('🏞️', 'activity_suggestion_watch_the_sunset'),
  ActivitySuggestion('🍧', 'activity_suggestion_have_ice_cream'),
  ActivitySuggestion('🥐', 'activity_suggestion_go_to_a_cool_bakery'),

  // 🎶 Shows / Música / Festas
  ActivitySuggestion('🎤', 'activity_suggestion_go_to_a_show'),
  ActivitySuggestion('🎶', 'activity_suggestion_go_to_pagode'),
  ActivitySuggestion('🥁', 'activity_suggestion_samba_with_friends'),
  ActivitySuggestion('🪗', 'activity_suggestion_dance_forro'),
  ActivitySuggestion('🤠', 'activity_suggestion_go_to_sertanejo'),
  ActivitySuggestion('🎸', 'activity_suggestion_go_to_a_rock_show'),
  ActivitySuggestion('🎧', 'activity_suggestion_electronic_party'),
  ActivitySuggestion('🔊', 'activity_suggestion_live_music'),
  ActivitySuggestion('🪩', 'activity_suggestion_go_to_a_club'),
  ActivitySuggestion('🕺', 'activity_suggestion_go_dancing'),
  ActivitySuggestion('🎪', 'activity_suggestion_go_to_a_festival'),
  ActivitySuggestion('🔥', 'activity_suggestion_rave_techno'),
  ActivitySuggestion('🎵', 'activity_suggestion_trap_hiphop_night'),
  ActivitySuggestion('💃', 'activity_suggestion_baile_funk'),
  ActivitySuggestion('🎛️', 'activity_suggestion_after_party'),
  ActivitySuggestion('🎚️', 'activity_suggestion_dj_set'),
  ActivitySuggestion('🌃', 'activity_suggestion_night_out_in_city'),
];
