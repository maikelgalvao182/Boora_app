import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// Serviço para fornecer as API Keys do Google Maps/Places.
///
/// Fonte de verdade: Firestore AppInfo collection.
/// Fallback: constantes locais em `constants.dart` (para build/dev).
/// 
/// Estrutura no Firestore:
/// - AppInfo/google_maps
///   - android_api_key: string
///   - ios_api_key: string
class GoogleMapsConfigService {
  factory GoogleMapsConfigService() => _instance;
  GoogleMapsConfigService._internal();
  static final GoogleMapsConfigService _instance = GoogleMapsConfigService._internal();

  static const String _tag = 'GoogleMapsConfig';

  // Method channels para comunicação com código nativo
  static const MethodChannel _iosChannel = MethodChannel('com.example.partiu/google_maps_ios');
  static const MethodChannel _androidChannel = MethodChannel('com.example.partiu/google_maps');

  // Cache das chaves
  String? _androidMapsKey;
  String? _iosMapsKey;
  bool _isInitialized = false;

  String _mapsKeyForPlatform() {
    if (Platform.isAndroid) return _androidMapsKey ?? '';
    if (Platform.isIOS) return _iosMapsKey ?? '';
    return '';
  }

  /// Inicializa e carrega as chaves do Firestore (com fallback para constants).
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Tentar carregar do Firestore primeiro
      final loaded = await _loadFromFirestore();
      
      // 2. Fallback para constantes locais se Firestore falhar
      if (!loaded) {
        AppLogger.warning('Usando chaves locais (fallback)', tag: _tag);
        _androidMapsKey = GOOGLE_MAPS_API_KEY_ANDROID.trim();
        _iosMapsKey = GOOGLE_MAPS_API_KEY_IOS.trim();
      }

      if (_androidMapsKey == null || _androidMapsKey!.isEmpty) {
        AppLogger.error('GOOGLE_MAPS_API_KEY_ANDROID não configurada', tag: _tag);
      }
      if (_iosMapsKey == null || _iosMapsKey!.isEmpty) {
        AppLogger.error('GOOGLE_MAPS_API_KEY_IOS não configurada', tag: _tag);
      }

      _isInitialized = true;

      // Configurar as API keys no nativo (quando implementado)
      await _configureNativeApiKeys();

      AppLogger.success('Google Maps/Places: chaves carregadas', tag: _tag);
    } catch (e) {
      AppLogger.error('Falha ao inicializar Google Maps/Places', tag: _tag, error: e);
      rethrow;
    }
  }

  /// Carrega as chaves do Firestore (AppInfo/google_maps)
  Future<bool> _loadFromFirestore() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('AppInfo')
          .doc('google_maps')
          .get();

      if (!doc.exists) {
        AppLogger.warning('AppInfo/google_maps não existe no Firestore', tag: _tag);
        return false;
      }

      final data = doc.data();
      if (data == null) return false;

      _androidMapsKey = (data['android_api_key'] as String?)?.trim();
      _iosMapsKey = (data['ios_api_key'] as String?)?.trim();

      final hasAndroid = _androidMapsKey != null && _androidMapsKey!.isNotEmpty;
      final hasIos = _iosMapsKey != null && _iosMapsKey!.isNotEmpty;

      if (hasAndroid || hasIos) {
        AppLogger.info('Chaves carregadas do Firestore (android=$hasAndroid, ios=$hasIos)', tag: _tag);
        return true;
      }

      return false;
    } catch (e) {
      AppLogger.warning('Erro ao carregar chaves do Firestore: $e', tag: _tag);
      return false;
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
      throw Exception('Google Maps API Key não configurada para esta plataforma');
    }

    return key;
  }

  /// Retorna a Google Places API Key.
  /// Usa a mesma chave do Maps por plataforma.
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