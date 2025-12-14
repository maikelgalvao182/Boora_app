import 'package:flutter/material.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Critérios de avaliação para reviews
/// Mesmos critérios para owner e participantes
class ReviewCriteria {
  static const String conversation = 'conversation';
  static const String energy = 'energy';
  static const String coexistence = 'coexistence';
  static const String participation = 'participation';

  static List<Map<String, String>> all(BuildContext context) => [
    {
      'key': conversation,
      'icon': '💬',
      'title': AppLocalizations.of(context).translate('review_criteria_conversation'),
      'description': AppLocalizations.of(context).translate('review_criteria_conversation_description'),
    },
    {
      'key': energy,
      'icon': '⚡',
      'title': AppLocalizations.of(context).translate('review_criteria_energy_short'),
      'description': AppLocalizations.of(context).translate('review_criteria_energy_description'),
    },
    {
      'key': coexistence,
      'icon': '🤝',
      'title': AppLocalizations.of(context).translate('review_criteria_coexistence'),
      'description': AppLocalizations.of(context).translate('review_criteria_coexistence_description'),
    },
    {
      'key': participation,
      'icon': '🎯',
      'title': AppLocalizations.of(context).translate('review_criteria_participation'),
      'description': AppLocalizations.of(context).translate('review_criteria_participation_description'),
    },
  ];

  static Map<String, String>? getCriterion(String key, BuildContext context) {
    try {
      return all(context).firstWhere((c) => c['key'] == key);
    } catch (_) {
      return null;
    }
  }

  static String getTitle(String key, BuildContext context) {
    final criterion = getCriterion(key, context);
    return criterion?['title'] ?? key;
  }

  static String getIcon(String key, BuildContext context) {
    final criterion = getCriterion(key, context);
    return criterion?['icon'] ?? '⭐';
  }
}
