import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeedOnboardingService {
  FeedOnboardingService._();
  static final FeedOnboardingService instance = FeedOnboardingService._();

  static const String _tag = 'FeedOnboardingService';
  static const String _keyCompleted = 'boora_feed_onboarding_completed_v1';

  static const String _usersCollection = 'users';
  static const String _fieldFeedOnboardingComplete = 'feedOnboardingComplete';

  Future<bool> isCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(_keyCompleted) ?? false;
      AppLogger.debug('Feed onboarding completed: $completed', tag: _tag);

      if (completed) return true;

      final userId = AppState.currentUserId;
      if (userId == null || userId.isEmpty) return false;

      final remoteCompleted = await _getRemoteCompleted(userId);
      if (remoteCompleted == true) {
        await prefs.setBool(_keyCompleted, true);
        return true;
      }

      return completed;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao verificar feed onboarding',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return true;
    }
  }

  Future<bool> shouldShow() async {
    final completed = await isCompleted();
    return !completed;
  }

  Future<void> markCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyCompleted, true);
      AppLogger.info('Feed onboarding marcado como completado', tag: _tag);

      final userId = AppState.currentUserId;
      if (userId == null || userId.isEmpty) return;

      await _setRemoteCompleted(userId, true);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao marcar feed onboarding',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool?> _getRemoteCompleted(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_usersCollection)
          .doc(userId)
          .get();

      if (doc.exists) {
        final value = doc.data()?[_fieldFeedOnboardingComplete];
        if (value is bool) return value;
      }

      return null;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao buscar feedOnboardingComplete no Firestore',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _setRemoteCompleted(String userId, bool complete) async {
    try {
      await FirebaseFirestore.instance.collection(_usersCollection).doc(userId).set(
        {_fieldFeedOnboardingComplete: complete},
        SetOptions(merge: true),
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao salvar feedOnboardingComplete no Firestore',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
