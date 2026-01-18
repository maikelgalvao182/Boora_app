import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/services/referral_service.dart';

/// Serviço para gerenciar AppsFlyer SDK
/// Responsável por:
/// - Inicialização do SDK
/// - Deep Links (deferred e direct)
/// - Tracking de eventos
class AppsflyerService {
  static AppsflyerService? _instance;
  static AppsflyerService get instance {
    _instance ??= AppsflyerService._();
    return _instance!;
  }

  AppsflyerService._();

  late AppsflyerSdk _appsflyerSdk;
  bool _isInitialized = false;

  /// Inicializa o AppsFlyer SDK
  /// 
  /// [devKey] - Chave de desenvolvedor do AppsFlyer
  /// [appId] - iOS App ID (Apple ID)
  Future<void> initialize({
    required String devKey,
    required String appId,
  }) async {
    if (_isInitialized) {
      AppLogger.warning('AppsFlyer já foi inicializado');
      return;
    }

    try {
      // Configuração das opções do SDK
      final AppsFlyerOptions options = AppsFlyerOptions(
        afDevKey: devKey,
        appId: appId,
        showDebug: kDebugMode, // Ative apenas em desenvolvimento
        timeToWaitForATTUserAuthorization: 15, // Tempo para aguardar autorização ATT (iOS)
      );

      _appsflyerSdk = AppsflyerSdk(options);

      // Listener para conversões (deep links)
      _appsflyerSdk.onDeepLinking((deepLinkResult) {
        _handleDeepLink(deepLinkResult);
      });

      // Listener para eventos de instalação/conversão
      _appsflyerSdk.onInstallConversionData((installData) {
        _handleInstallConversion(installData);
      });

      // Listener para erros de conversão
      _appsflyerSdk.onInstallConversionFailure((error) {
        AppLogger.error(
          'Erro ao obter dados de conversão de instalação',
          error: error,
        );
      });

      // Inicializa o SDK
      await _appsflyerSdk.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );

      _isInitialized = true;
      AppLogger.success('AppsFlyer SDK inicializado com sucesso', tag: 'APPSFLYER');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao inicializar AppsFlyer SDK',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Loga evento personalizado
  Future<void> logEvent({
    required String eventName,
    Map<String, dynamic>? eventValues,
  }) async {
    if (!_isInitialized) {
      AppLogger.warning('AppsFlyer não inicializado. Chamando logEvent ignorado.');
      return;
    }

    try {
      await _appsflyerSdk.logEvent(eventName, eventValues);
      
      if (LogFlags.api) {
        AppLogger.info(
          'Evento AppsFlyer: $eventName - Valores: $eventValues',
          tag: 'APPSFLYER',
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao logar evento AppsFlyer: $eventName',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Obtém o AppsFlyer ID
  Future<String?> getAppsFlyerId() async {
    if (!_isInitialized) {
      AppLogger.warning('AppsFlyer não inicializado');
      return null;
    }

    try {
      return await _appsflyerSdk.getAppsFlyerUID();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao obter AppsFlyer ID',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Handler para deep links
  void _handleDeepLink(DeepLinkResult deepLinkResult) {
    switch (deepLinkResult.status) {
      case Status.FOUND:
        AppLogger.info('Deep link encontrado: ${deepLinkResult.deepLink?.toString()}');

        final deepLink = deepLinkResult.deepLink;
        final deepLinkValue = deepLink?.deepLinkValue;
        final referrerId = _extractReferrerIdFromDeepLink(deepLink);

        if (referrerId != null) {
          ReferralService.instance.captureReferral(
            referrerId: referrerId,
            deepLinkValue: deepLinkValue,
          );
        }

        if (deepLinkValue != null) {
          _processDeepLink(deepLinkValue);
        }
        break;
      
      case Status.NOT_FOUND:
        AppLogger.info('Deep link não encontrado');
        break;
      
      case Status.ERROR:
        AppLogger.error(
          'Erro no deep link',
          error: deepLinkResult.error,
        );
        break;
      
      case Status.PARSE_ERROR:
        AppLogger.error('Erro ao parsear deep link');
        break;
    }
  }

  /// Handler para dados de conversão de instalação
  void _handleInstallConversion(Map<String, dynamic> installData) {
    AppLogger.info('Dados de conversão de instalação: $installData');
    
    // Verificar se é uma instalação orgânica ou paga
    final isFirstLaunch = installData['is_first_launch'] == true ||
      installData['is_first_launch']?.toString() == 'true';
    final isOrganic = isFirstLaunch && installData['af_status'] == 'Organic';
    
    if (isOrganic) {
      AppLogger.info('Instalação orgânica detectada');
    } else {
      AppLogger.info('Instalação não orgânica detectada');
      
      // Processar parâmetros de campanha
      final campaign = installData['campaign'];
      final mediaSource = installData['media_source'];
      
      if (campaign != null || mediaSource != null) {
        AppLogger.info(
          'Campanha: $campaign, Media Source: $mediaSource',
        );
      }
    }

    if (isFirstLaunch) {
      final referrerId = _extractReferrerIdFromInstallData(installData);
      final deepLinkValue = installData['deep_link_value']?.toString();

      if (referrerId != null) {
        ReferralService.instance.captureReferral(
          referrerId: referrerId,
          deepLinkValue: deepLinkValue,
        );
      }
    }
  }

  /// Processa o deep link recebido
  void _processDeepLink(String deepLinkValue) {
    AppLogger.info('Processando deep link: $deepLinkValue');
    
    // TODO: Implementar navegação baseada no deep link
    // Exemplo:
    // if (deepLinkValue.contains('profile')) {
    //   // Navegar para perfil
    // } else if (deepLinkValue.contains('activity')) {
    //   // Navegar para atividade
    // }
  }

  /// Define o ID do usuário (opcional)
  Future<void> setCustomerUserId(String userId) async {
    if (!_isInitialized) {
      AppLogger.warning('AppsFlyer não inicializado');
      return;
    }

    try {
      await _appsflyerSdk.setCustomerUserId(userId);
      AppLogger.info('Customer User ID definido: $userId');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao definir Customer User ID',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Eventos pré-definidos do AppsFlyer
  static const String eventCompleteRegistration = 'af_complete_registration';
  static const String eventLogin = 'af_login';
  static const String eventPurchase = 'af_purchase';
  static const String eventSubscribe = 'af_subscribe';
  static const String eventStartTrial = 'af_start_trial';
  static const String eventAddToCart = 'af_add_to_cart';
  static const String eventAddToWishlist = 'af_add_to_wishlist';
  static const String eventSearch = 'af_search';
  static const String eventShare = 'af_share';
  static const String eventContentView = 'af_content_view';

  String? _extractReferrerIdFromDeepLink(DeepLink? deepLink) {
    if (deepLink == null) return null;

    final candidate = deepLink.getStringValue('deep_link_sub2') ??
        deepLink.getStringValue('deep_link_sub1') ??
        deepLink.getStringValue('af_sub1');

    if (candidate == null || candidate.trim().isEmpty) {
      return null;
    }

    return candidate.trim();
  }

  String? _extractReferrerIdFromInstallData(Map<String, dynamic> installData) {
    final candidate = installData['deep_link_sub2'] ??
        installData['deep_link_sub1'] ??
        installData['af_sub1'];

    if (candidate == null) return null;

    final value = candidate.toString().trim();
    if (value.isEmpty) return null;

    return value;
  }
}
