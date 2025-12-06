import 'package:flutter/material.dart';

/// Badge que pode ser atribuído em uma review
class ReviewBadge {
  final String key;
  final String emoji;
  final String title;
  final Color color;

  const ReviewBadge({
    required this.key,
    required this.emoji,
    required this.title,
    required this.color,
  });

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'emoji': emoji,
      'title': title,
    };
  }

  static ReviewBadge? fromKey(String key) {
    try {
      return availableBadges.firstWhere((b) => b.key == key);
    } catch (_) {
      return null;
    }
  }
}

/// Lista de badges disponíveis para atribuir
const List<ReviewBadge> availableBadges = [
  ReviewBadge(
    key: 'mega_simpatico',
    emoji: '😄',
    title: 'Mega simpático(a)',
    color: Color(0xFFFFEB3B), // Amarelo
  ),
  ReviewBadge(
    key: 'muito_engracado',
    emoji: '😂',
    title: 'Muito engraçado(a)',
    color: Color(0xFFFF9800), // Laranja
  ),
  ReviewBadge(
    key: 'muito_inteligente',
    emoji: '🧠',
    title: 'Muito inteligente',
    color: Color(0xFF9C27B0), // Roxo
  ),
  ReviewBadge(
    key: 'estilo_impecavel',
    emoji: '😍',
    title: 'Estilo impecável',
    color: Color(0xFFE91E63), // Pink
  ),
  ReviewBadge(
    key: 'super_educado',
    emoji: '🤝',
    title: 'Super educado(a)',
    color: Color(0xFF2196F3), // Azul
  ),
  ReviewBadge(
    key: 'anima_todo_mundo',
    emoji: '🎉',
    title: 'Anima todo mundo',
    color: Color(0xFF4CAF50), // Verde
  ),
  ReviewBadge(
    key: 'super_gato',
    emoji: '🐱',
    title: 'Super gato(a)',
    color: Color(0xFFFF5722), // Vermelho
  ),
];
