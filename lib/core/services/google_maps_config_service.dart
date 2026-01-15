import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// Serviço para fornecer as API Keys do Google Maps/Places.
///
/// Fonte de verdade: constantes locais em `constants.dart`.
/// Não faz leitura de chaves via Firestore.
class GoogleMapsConfigService {
  factory GoogleMapsConfigService() => _instance;
  GoogleMapsConfigService._internal();
  static final GoogleMapsConfigService _instance = GoogleMapsConfigService._internal();

  static const String _tag = 'GoogleMapsConfig';

  // Method channels para comunicação com código nativo
  static const MethodChannel _iosChannel = MethodChannel('com.example.partiu/google_maps_ios');
  static const MethodChannel _androidChannel = MethodChannel('com.example.partiu/google_maps');

  // Cache das chaves (carregadas de constants.dart)
  String? _androidMapsKey;
  String? _iosMapsKey;
  bool _isInitialized = false;

  String _mapsKeyForPlatform() {
    if (Platform.isAndroid) return _androidMapsKey ?? '';
    if (Platform.isIOS) return _iosMapsKey ?? '';
    return '';
  }

  /// Inicializa e carrega as chaves locais.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _androidMapsKey = GOOGLE_MAPS_API_KEY_ANDROID.trim();
      _iosMapsKey = GOOGLE_MAPS_API_KEY_IOS.trim();

      if (_androidMapsKey == null || _androidMapsKey!.isEmpty) {
        AppLogger.error('GOOGLE_MAPS_API_KEY_ANDROID não configurada em constants.dart', tag: _tag);
      }
      if (_iosMapsKey == null || _iosMapsKey!.isEmpty) {
        AppLogger.error('GOOGLE_MAPS_API_KEY_IOS não configurada em constants.dart', tag: _tag);
      }

      _isInitialized = true;

      // Configurar as API keys no nativo (quando implementado)
      await _configureNativeApiKeys();

      AppLogger.success('Google Maps/Places: chaves locais carregadas', tag: _tag);
    } catch (e) {
      AppLogger.error('Falha ao inicializar Google Maps/Places', tag: _tag, error: e);
      rethrow;
    }
  }

  /// Configura as API keys no código nativo através de method channels
  Future<void> _configureNativeApiKeys() async {
    try {
      if (Platform.isIOS && _iosMapsKey != null && _iosMapsKey!.isNotEmpty) {
        await _iosChannel.invokeMethod('setApiKey', {'apiKey': _iosMapsKey});
        AppLogger.info('iOS: chave do Google Maps enviada via MethodChannel', tag: _tag);
      } else if (Platform.isAndroid && _androidMapsKey != null && _androidMapsKey!.isNotEmpty) {
        await _androidChannel.invokeMethod('setApiKey', {'apiKey': _androidMapsKey});
        AppLogger.info('Android: setApiKey chamado via MethodChannel (se suportado)', tag: _tag);
      }
    } catch (e) {
      // Não falhar a inicialização se o method channel falhar
      AppLogger.warning('Falha ao configurar chave no nativo via MethodChannel (seguindo)', tag: _tag);
    }
  }

  /// Retorna a Google Maps API Key baseado na plataforma.
  Future<String> getGoogleMapsApiKey() async {
    await initialize();

    final key = _mapsKeyForPlatform().trim();
    if (key.isEmpty) {
      throw Exception('Google Maps API Key não configurada em constants.dart para esta plataforma');
    }

    return key;
  }

  /// Retorna a Google Places API Key.
  /// Neste app, usamos a mesma chave do Maps por plataforma.
  Future<String> getGooglePlacesApiKey() async {
    return getGoogleMapsApiKey();
  }

  /// Força recarregar as chaves do Firebase
  Future<void> reload() async {
    _isInitialized = false;
    _androidMapsKey = null;
    _iosMapsKey = null;
    await initialize();
  }
}