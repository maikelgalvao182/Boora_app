import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/utils/app_logger.dart';

class AppsflyerService {
  AppsflyerService._();

  static final AppsflyerService _instance = AppsflyerService._();
  static AppsflyerService get instance => _instance;

  AppsflyerSdk? _appsflyerSdk;
  bool _isInitialized = false;
  String? _pendingCustomerUserId;
  String? _lastSyncedCustomerUserId;

  Future<void> initialize({
    required String devKey,
    required String appId,
  }) async {
    if (_isInitialized || kIsWeb) return;

    final normalizedDevKey = devKey.trim();
    final normalizedAppId = _normalizeAppId(appId);

    if (normalizedDevKey.isEmpty || normalizedAppId.isEmpty) {
      AppLogger.warning(
        'AppsFlyer não inicializado: dev key ou app id ausentes',
        tag: 'APPSFLYER',
      );
      return;
    }

    try {
      final options = AppsFlyerOptions(
        afDevKey: normalizedDevKey,
        appId: normalizedAppId,
        showDebug: kDebugMode,
        timeToWaitForATTUserAuthorization: 15,
      );

      final sdk = AppsflyerSdk(options);
      sdk.onInstallConversionData(_onInstallConversionData);
      sdk.onAppOpenAttribution(_onAppOpenAttribution);
      sdk.onDeepLinking(_onDeepLinking);

      await sdk.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );

      _appsflyerSdk = sdk;
      _isInitialized = true;

      final pendingUserId = _pendingCustomerUserId;
      if (pendingUserId != null && pendingUserId.isNotEmpty) {
        await setCustomerUserId(pendingUserId);
      }

      final appsFlyerId = await _appsflyerSdk?.getAppsFlyerUID();
      AppLogger.success(
        'AppsFlyer inicializado. appsFlyerId=$appsFlyerId',
        tag: 'APPSFLYER',
      );
    } catch (e, stack) {
      AppLogger.error(
        'Erro ao inicializar AppsFlyer',
        tag: 'APPSFLYER',
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<void> setCustomerUserId(String? userId) async {
    final normalizedUserId = userId?.trim();

    if (normalizedUserId == null || normalizedUserId.isEmpty) {
      return;
    }

    _pendingCustomerUserId = normalizedUserId;

    if (_lastSyncedCustomerUserId == normalizedUserId) {
      return;
    }

    if (!_isInitialized || _appsflyerSdk == null) {
      return;
    }

    try {
      _appsflyerSdk!.setCustomerUserId(normalizedUserId);
      _lastSyncedCustomerUserId = normalizedUserId;
      AppLogger.info(
        'AppsFlyer customerUserId definido: $normalizedUserId',
        tag: 'APPSFLYER',
      );
    } catch (e, stack) {
      AppLogger.error(
        'Erro ao definir customerUserId no AppsFlyer',
        tag: 'APPSFLYER',
        error: e,
        stackTrace: stack,
      );
    }
  }

  void clearPendingCustomerUserId() {
    _pendingCustomerUserId = null;
    _lastSyncedCustomerUserId = null;
  }

  Future<String?> getAppsFlyerId() async {
    if (!_isInitialized || _appsflyerSdk == null) return null;

    try {
      return await _appsflyerSdk!.getAppsFlyerUID();
    } catch (e) {
      AppLogger.warning('Erro ao obter AppsFlyer ID: $e', tag: 'APPSFLYER');
      return null;
    }
  }

  Future<void> logEvent(
    String eventName, {
    Map<String, dynamic>? eventValues,
  }) async {
    if (!_isInitialized || _appsflyerSdk == null) return;

    try {
      await _appsflyerSdk!.logEvent(eventName, eventValues);
    } catch (e) {
      AppLogger.warning('Erro ao enviar evento AppsFlyer $eventName: $e', tag: 'APPSFLYER');
    }
  }

  String _normalizeAppId(String appId) {
    final normalized = appId.trim();
    if (normalized.toLowerCase().startsWith('id')) {
      return normalized.substring(2);
    }
    return normalized;
  }

  void _onInstallConversionData(dynamic data) {
    AppLogger.info(
      'AppsFlyer conversion data recebida: $data',
      tag: 'APPSFLYER',
    );
  }

  void _onAppOpenAttribution(dynamic data) {
    AppLogger.info(
      'AppsFlyer app open attribution: $data',
      tag: 'APPSFLYER',
    );
  }

  void _onDeepLinking(DeepLinkResult result) {
    AppLogger.info(
      'AppsFlyer deep link status=${result.status} payload=${result.deepLink?.toString()}',
      tag: 'APPSFLYER',
    );
  }
}
