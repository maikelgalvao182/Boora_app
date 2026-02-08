import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tipo da mensagem de lembrete do feed
enum FeedReminderType {
  /// Mensagem A: 2h antes do evento (pré-evento)
  preEvent,

  /// Mensagem B: 6h depois do evento (pós-evento)
  postEvent,
}

/// Resultado da avaliação de exibição do reminder
class FeedReminderResult {
  const FeedReminderResult({
    required this.shouldShow,
    this.type,
    this.eventId,
  });

  final bool shouldShow;
  final FeedReminderType? type;
  final String? eventId;

  static const hidden = FeedReminderResult(shouldShow: false);
}

/// Service responsável por decidir quando exibir o card flutuante
/// de lembrete para postar fotos no feed.
///
/// Regras:
/// - Cooldown de 7 dias entre exibições
/// - Nunca repetir no mesmo dia
/// - Probabilidade de 25% (pré-evento) ou 35% (pós-evento)
/// - Limite total de 5 exibições por usuário (vida toda)
/// - Respeita "Não mostrar mais" (dismiss definitivo)
/// - Só mostra se há contexto (evento próximo ou encerrado sem fotos)
class FeedReminderService {
  FeedReminderService._();
  static final FeedReminderService instance = FeedReminderService._();

  static const String _tag = 'FeedReminder';

  // SharedPreferences keys
  static const _prefsDismissKey = 'feed_reminder_dismiss_v1';
  static const _prefsLastShownKey = 'feed_reminder_last_shown_v1';
  static const _prefsTotalShownKey = 'feed_reminder_total_shown_v1';
  static const _prefsLastShownDateKey = 'feed_reminder_last_date_v1';

  // Configurações
  static const int _maxTotalShown = 5;
  static const Duration _cooldown = Duration(days: 7);
  static const double _preEventProbability = 0.25;
  static const double _postEventProbability = 0.35;
  static const int _maxPostsForReminder = 3;

  // Horas relativas ao scheduleDate
  static const int _preEventHoursBefore = 2;
  static const int _postEventHoursAfter = 6;

  final _random = Random();

  /// Avalia se o card de reminder deve ser exibido.
  /// Retorna [FeedReminderResult] com tipo e eventId se deve mostrar.
  Future<FeedReminderResult> evaluate() async {
    final userId = AppState.currentUserId;
    if (userId == null || userId.isEmpty) {
      AppLogger.debug('No user logged in', tag: _tag);
      return FeedReminderResult.hidden;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Dismiss definitivo
      if (prefs.getBool(_prefsDismissKey) ?? false) {
        AppLogger.debug('User dismissed permanently', tag: _tag);
        return FeedReminderResult.hidden;
      }

      // 2. Limite total atingido
      final totalShown = prefs.getInt(_prefsTotalShownKey) ?? 0;
      if (totalShown >= _maxTotalShown) {
        AppLogger.debug('Total limit reached ($totalShown/$_maxTotalShown)', tag: _tag);
        return FeedReminderResult.hidden;
      }

      // 3. Já mostrou hoje
      final lastDateStr = prefs.getString(_prefsLastShownDateKey);
      final todayStr = _todayKey();
      if (lastDateStr == todayStr) {
        AppLogger.debug('Already shown today', tag: _tag);
        return FeedReminderResult.hidden;
      }

      // 4. Cooldown de 7 dias
      final lastShownTs = prefs.getInt(_prefsLastShownKey);
      if (lastShownTs != null) {
        final lastShown = DateTime.fromMillisecondsSinceEpoch(lastShownTs);
        if (DateTime.now().difference(lastShown) < _cooldown) {
          AppLogger.debug('Still in cooldown', tag: _tag);
          return FeedReminderResult.hidden;
        }
      }

      // 5. Verifica contexto: busca eventos do usuário
      final result = await _findRelevantEvent(userId);
      if (!result.shouldShow) {
        AppLogger.debug('No relevant event context found', tag: _tag);
        return FeedReminderResult.hidden;
      }

      // 6. Aplicar probabilidade
      final probability = result.type == FeedReminderType.preEvent
          ? _preEventProbability
          : _postEventProbability;

      final roll = _random.nextDouble();
      if (roll > probability) {
        AppLogger.debug(
          'Probability check failed (roll=$roll, threshold=$probability)',
          tag: _tag,
        );
        return FeedReminderResult.hidden;
      }

      // 7. Verifica se usuário tem poucos posts (< 3) para pré-evento
      if (result.type == FeedReminderType.preEvent) {
        final postCount = await _getUserPostCount(userId);
        if (postCount >= _maxPostsForReminder) {
          AppLogger.debug(
            'User already has $postCount posts, skipping preEvent reminder',
            tag: _tag,
          );
          return FeedReminderResult.hidden;
        }
      }

      AppLogger.info(
        'Will show reminder: type=${result.type}, eventId=${result.eventId}',
        tag: _tag,
      );
      return result;
    } catch (e, stack) {
      AppLogger.error('Error evaluating reminder', tag: _tag, error: e, stackTrace: stack);
      return FeedReminderResult.hidden;
    }
  }

  /// Busca eventos do usuário para encontrar contexto relevante
  Future<FeedReminderResult> _findRelevantEvent(String userId) async {
    final now = DateTime.now();
    final firestore = FirebaseFirestore.instance;

    // Buscar eventos do usuário que estão próximos ou recém-encerrados
    final snapshot = await firestore
        .collection('events_card_preview')
        .where('createdBy', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .orderBy('scheduleDate', descending: true)
        .limit(10)
        .get();

    if (snapshot.docs.isEmpty) {
      return FeedReminderResult.hidden;
    }

    // Verificar cada evento
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final scheduleDate = _parseScheduleDate(data['scheduleDate']);
      if (scheduleDate == null) continue;

      final eventId = doc.id;

      // Mensagem A: 2h antes do evento (no dia do evento)
      final preEventWindow = scheduleDate.subtract(
        const Duration(hours: _preEventHoursBefore),
      );
      if (now.isAfter(preEventWindow) && now.isBefore(scheduleDate)) {
        return FeedReminderResult(
          shouldShow: true,
          type: FeedReminderType.preEvent,
          eventId: eventId,
        );
      }

      // Mensagem B: 6h depois do evento (pós-evento)
      final postEventWindow = scheduleDate.add(
        const Duration(hours: _postEventHoursAfter),
      );
      if (now.isAfter(scheduleDate) && now.isBefore(postEventWindow)) {
        // Verificar se já tem foto no feed desse evento
        final hasPhoto = await _eventHasPhotoInFeed(eventId);
        if (!hasPhoto) {
          return FeedReminderResult(
            shouldShow: true,
            type: FeedReminderType.postEvent,
            eventId: eventId,
          );
        }
      }

      // Também verificar eventos que já passaram (até 48h) sem fotos
      final extendedPostWindow = scheduleDate.add(const Duration(hours: 48));
      if (now.isAfter(postEventWindow) && now.isBefore(extendedPostWindow)) {
        final hasPhoto = await _eventHasPhotoInFeed(eventId);
        if (!hasPhoto) {
          return FeedReminderResult(
            shouldShow: true,
            type: FeedReminderType.postEvent,
            eventId: eventId,
          );
        }
      }
    }

    return FeedReminderResult.hidden;
  }

  /// Verifica se um evento já tem fotos postadas no feed
  Future<bool> _eventHasPhotoInFeed(String eventId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('EventPhotos')
          .where('eventId', isEqualTo: eventId)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      AppLogger.debug('Error checking event photos: $e', tag: _tag);
      return false; // Em caso de erro, assume que não tem (mostra lembrete)
    }
  }

  /// Conta posts do usuário no feed
  Future<int> _getUserPostCount(String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('EventPhotos')
          .where('userId', isEqualTo: userId)
          .limit(_maxPostsForReminder + 1)
          .get();

      return snapshot.docs.length;
    } catch (e) {
      AppLogger.debug('Error counting user posts: $e', tag: _tag);
      return 0;
    }
  }

  /// Marca que o reminder foi exibido (atualiza cooldown e contadores)
  Future<void> markShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      await prefs.setInt(_prefsLastShownKey, now.millisecondsSinceEpoch);
      await prefs.setString(_prefsLastShownDateKey, _todayKey());

      final total = (prefs.getInt(_prefsTotalShownKey) ?? 0) + 1;
      await prefs.setInt(_prefsTotalShownKey, total);

      AppLogger.info('Reminder marked as shown (total: $total)', tag: _tag);
    } catch (e) {
      AppLogger.error('Error marking reminder as shown', tag: _tag, error: e);
    }
  }

  /// Marca dismiss definitivo (não mostrar mais)
  Future<void> dismissPermanently() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsDismissKey, true);
      AppLogger.info('User dismissed feed reminder permanently', tag: _tag);
    } catch (e) {
      AppLogger.error('Error dismissing reminder', tag: _tag, error: e);
    }
  }

  /// Retorna chave do dia atual (para controle de "nunca repetir no mesmo dia")
  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Parse flexível do scheduleDate (Timestamp, DateTime, String ISO)
  DateTime? _parseScheduleDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
