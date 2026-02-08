import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// Serviço singleton para feature flags remotas via Firestore.
///
/// Fonte de verdade: Firestore AppInfo/feature_flags
/// Padrão: cada flag é um campo booleano no documento.
///
/// Uso:
/// ```dart
/// await FeatureFlagsService().initialize();
/// final show = FeatureFlagsService().showVerificationCard;
/// ```
///
/// Para escutar mudanças reativas:
/// ```dart
/// ValueListenableBuilder<bool>(
///   valueListenable: FeatureFlagsService().showVerificationCardNotifier,
///   builder: (context, show, _) { ... },
/// )
/// ```
class FeatureFlagsService {
  factory FeatureFlagsService() => _instance;
  FeatureFlagsService._internal();
  static final FeatureFlagsService _instance = FeatureFlagsService._internal();

  static const String _tag = 'FeatureFlags';
  static const String _collection = 'AppInfo';
  static const String _document = 'feature_flags';

  bool _isInitialized = false;

  // ─── Feature Flags ────────────────────────────────────────────────────
  
  /// Exibir o card de verificação de identidade no perfil
  final ValueNotifier<bool> showVerificationCardNotifier = ValueNotifier<bool>(true);
  
  bool get showVerificationCard => showVerificationCardNotifier.value;

  // ─── Inicialização ────────────────────────────────────────────────────

  /// Carrega as feature flags do Firestore.
  /// Seguro para chamar múltiplas vezes (idempotente).
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_document)
          .get();

      if (!doc.exists || doc.data() == null) {
        AppLogger.warning(
          '$_collection/$_document não existe — usando defaults',
          tag: _tag,
        );
        _isInitialized = true;
        return;
      }

      final data = doc.data()!;
      _applyFlags(data);
      _isInitialized = true;

      AppLogger.success('Feature flags carregadas do Firestore', tag: _tag);
    } catch (e) {
      AppLogger.error(
        'Erro ao carregar feature flags — usando defaults',
        tag: _tag,
        error: e,
      );
      // Não falha o app — mantém defaults
      _isInitialized = true;
    }
  }

  /// Aplica os valores do Firestore aos notifiers.
  void _applyFlags(Map<String, dynamic> data) {
    showVerificationCardNotifier.value =
        data['show_verification_card'] as bool? ?? true;

    AppLogger.info(
      'Flags aplicadas: show_verification_card=${showVerificationCardNotifier.value}',
      tag: _tag,
    );
  }
}
