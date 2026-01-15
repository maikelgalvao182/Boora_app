import 'package:partiu/core/services/google_maps_config_service.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// Serviço para inicializar o Google Maps com chaves locais (constants.dart)
class GoogleMapsInitializer {
  static const String _tag = 'GoogleMapsInitializer';
  static bool _isInitialized = false;

  /// Inicializa o Google Maps com a chave do Firebase
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      AppLogger.info('Initializing Google Maps with local keys...', tag: _tag);

      // O GoogleMapsConfigService já faz toda a configuração nativa
      // incluindo os method channels para iOS e Android
      final configService = GoogleMapsConfigService();
      await configService.initialize();
      
      AppLogger.success('Google Maps configured using local constants', tag: _tag);

      _isInitialized = true;
      AppLogger.success('Google Maps initialization completed', tag: _tag);
    } catch (e) {
      AppLogger.error('Failed to initialize Google Maps: $e', tag: _tag);
      // Não trava o app, apenas loga o erro
    }
  }

  /// Força reinicialização (útil para testes ou quando chaves são atualizadas)
  static Future<void> reinitialize() async {
    _isInitialized = false;
    await initialize();
  }

  /// Verifica se foi inicializado
  static bool get isInitialized => _isInitialized;
}