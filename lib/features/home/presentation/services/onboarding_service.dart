import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serviço para controlar exibição do onboarding.
///
/// O onboarding é exibido apenas uma vez por usuário e é liberado quando
/// o usuário toca pela primeira vez no overlay/botão de criar ("+") na tela
/// de descoberta.
///
/// Usa SharedPreferences para persistir o estado entre sessões e também
/// persiste no Firestore (por usuário) para sobreviver reinstalações.
class OnboardingService {
  OnboardingService._();
  static final OnboardingService instance = OnboardingService._();

  static const String _tag = 'OnboardingService';
  static const String _keyOnboardingCompleted = 'boora_onboarding_completed_v1';
  static const String _keyFirstCreateOverlayTap = 'boora_first_create_overlay_tap_v1';

  // Firestore (por usuário)
  static const String _usersCollection = 'Users';
  static const String _fieldOnboardingComplete = 'onboardingComplete';

  /// Verifica se o onboarding já foi completado
  Future<bool> isOnboardingCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(_keyOnboardingCompleted) ?? false;
      AppLogger.debug('Onboarding completed: $completed', tag: _tag);

      // Fast path (local)
      if (completed) return true;

      // Fallback (Firestore) — garante persistência por usuário e após reinstalação
      final userId = AppState.currentUserId;
      if (userId == null || userId.isEmpty) return false;

      final remoteCompleted = await _getRemoteOnboardingComplete(userId);
      if (remoteCompleted == true) {
        await prefs.setBool(_keyOnboardingCompleted, true);
        return true;
      }

      return completed;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao verificar onboarding',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return true; // Em caso de erro, assume que já viu para não bloquear UX
    }
  }

  /// Verifica se já houve o primeiro toque no overlay/botão "+" (Create)
  ///
  /// Este é o gatilho que libera a exibição do onboarding.
  Future<bool> hasFirstCreateOverlayTapOccurred() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyFirstCreateOverlayTap) ?? false;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao verificar primeiro toque no create overlay',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return true;
    }
  }

  /// Marca que o primeiro toque no overlay/botão "+" (Create) ocorreu
  Future<void> markFirstCreateOverlayTap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyFirstCreateOverlayTap, true);
      AppLogger.info('Primeiro toque no create overlay marcado', tag: _tag);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao marcar primeiro toque no create overlay',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Marca o onboarding como completado
  Future<void> markOnboardingCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyOnboardingCompleted, true);
      AppLogger.info('Onboarding marcado como completado', tag: _tag);

      // Persistir também no Firestore (por usuário)
      final userId = AppState.currentUserId;
      if (userId == null || userId.isEmpty) return;

      await _setRemoteOnboardingComplete(userId, true);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao marcar onboarding',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Verifica se deve mostrar o onboarding
  /// Retorna true se: ainda não completou E o usuário já tocou no overlay/botão "+"
  Future<bool> shouldShowOnboarding() async {
    AppLogger.debug('shouldShowOnboarding chamado', tag: _tag);

    final completed = await isOnboardingCompleted();
    if (completed) {
      AppLogger.debug('Onboarding já completado -> false', tag: _tag);
      return false;
    }

    final createTapOccurred = await hasFirstCreateOverlayTapOccurred();
    AppLogger.debug('createTapOccurred: $createTapOccurred', tag: _tag);
    return createTapOccurred;
  }

  Future<bool?> _getRemoteOnboardingComplete(String userId) async {
    try {
      final firestore = FirebaseFirestore.instance;

      final doc = await firestore.collection(_usersCollection).doc(userId).get();
      if (doc.exists) {
        final value = doc.data()?[_fieldOnboardingComplete];
        if (value is bool) return value;
      }

      return null;
    } catch (e, stackTrace) {
      // Não bloqueia UX se Firestore falhar
      AppLogger.error(
        'Erro ao buscar onboardingComplete no Firestore',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _setRemoteOnboardingComplete(String userId, bool complete) async {
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore.collection(_usersCollection).doc(userId).set(
        {_fieldOnboardingComplete: complete},
        SetOptions(merge: true),
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao salvar onboardingComplete no Firestore',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Reseta o estado do onboarding (útil para debug/testes)
  Future<void> resetOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyOnboardingCompleted);
      await prefs.remove(_keyFirstCreateOverlayTap);
      AppLogger.info('Onboarding resetado', tag: _tag);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao resetar onboarding',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
