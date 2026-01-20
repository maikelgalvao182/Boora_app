import 'dart:async';

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

  bool get isInitialized => _isInitialized;

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

  // debugPrint direto pra garantir que isso aparece no console sempre.
  debugPrint('🧪 [AF_INIT] initialize() chamado');

    AppLogger.info('🚀 Iniciando AppsFlyer SDK...', tag: 'APPSFLYER');
  final devKeyPrefix = devKey.length >= 5 ? devKey.substring(0, 5) : devKey;
  AppLogger.info('   devKey: ${devKeyPrefix.isEmpty ? "(vazio)" : "$devKeyPrefix..."}', tag: 'APPSFLYER');
    AppLogger.info('   appId: ${appId.isEmpty ? "(vazio - app não publicado)" : appId}', tag: 'APPSFLYER');

  try {
      // Configuração das opções do SDK
      final AppsFlyerOptions options = AppsFlyerOptions(
        afDevKey: devKey,
        appId: appId,
        showDebug: kDebugMode, // Ative apenas em desenvolvimento
        timeToWaitForATTUserAuthorization: 15, // Tempo para aguardar autorização ATT (iOS)
      );

      _appsflyerSdk = AppsflyerSdk(options);
      AppLogger.info('   AppsflyerSdk criado', tag: 'APPSFLYER');

      // Listener para conversões (deep links)
      _appsflyerSdk.onDeepLinking((deepLinkResult) {
        _handleDeepLink(deepLinkResult);
      });

      // Listener para eventos de instalação/conversão
      _appsflyerSdk.onInstallConversionData((installData) {
        _handleInstallConversion(installData);
      });

      // Nota: onInstallConversionFailure foi removido nas versões mais recentes do SDK
      // Os erros são tratados no callback onInstallConversionData

      AppLogger.info('   Listeners registrados, chamando initSdk()...', tag: 'APPSFLYER');
  debugPrint('🧪 [AF_INIT] chamando initSdk()');

      // Inicializa o SDK
      final result = await _appsflyerSdk.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );

      AppLogger.info('   initSdk() retornou: $result', tag: 'APPSFLYER');
  debugPrint('🧪 [AF_INIT] initSdk() retornou: $result');

      // Smoke test: tenta obter o AppsFlyer UID para confirmar bridge nativa ativa.
      // Se isso falhar, normalmente é problema de configuração nativa / plugin.
      try {
        final uid = await _appsflyerSdk.getAppsFlyerUID();
        AppLogger.info('   AppsFlyer UID: $uid', tag: 'APPSFLYER');
      } catch (e, stackTrace) {
        AppLogger.error(
          '⚠️ initSdk OK, mas getAppsFlyerUID falhou (bridge nativa pode não estar ativa)',
          error: e,
          stackTrace: stackTrace,
          tag: 'APPSFLYER',
        );
      }

      // Configura o OneLink ID para User Invite
      _appsflyerSdk.setAppInviteOneLinkID(
        'bFrs', // OneLink Template ID do AppsFlyer Dashboard
        (result) {
          AppLogger.info('setAppInviteOneLinkID callback: $result', tag: 'APPSFLYER');
        },
      );

      _isInitialized = true;
      AppLogger.success('✅ AppsFlyer SDK inicializado com sucesso', tag: 'APPSFLYER');
  debugPrint('🧪 [AF_INIT] ✅ initialized=true');
    } catch (e, stackTrace) {
      AppLogger.error(
        '❌ Erro ao inicializar AppsFlyer SDK',
        error: e,
        stackTrace: stackTrace,
        tag: 'APPSFLYER',
      );
  debugPrint('🧪 [AF_INIT] ❌ erro ao inicializar: $e');
      // Não seta _isInitialized = true, então geração de link usará fallback
    } finally {
      AppLogger.info('📌 AppsFlyer estado final: initialized=$_isInitialized', tag: 'APPSFLYER');
  debugPrint('🧪 [AF_INIT] finally - initialized=$_isInitialized');
    }
  }

  /// Gera link de convite usando a API oficial do AppsFlyer
  /// Retorna o link gerado via callback de sucesso
  Future<String?> generateInviteLink({
    required String referrerId,
    String? referrerName,
    String? campaign,
    String? channel,
  }) async {
    if (!_isInitialized) {
      AppLogger.warning('AppsFlyer não inicializado', tag: 'APPSFLYER');
      return null;
    }

    final completer = Completer<String?>();

    // Parâmetros conforme configurado no Dashboard AppsFlyer:
    // pid = User_invite (channel)
    // c = Convite (campaign) 
    // deep_link_value = invite
    // deep_link_sub1 = new_member
    // deep_link_sub2 = referrerId
    final params = AppsFlyerInviteLinkParams(
      channel: channel ?? 'User_invite',  // pid no dashboard
      campaign: campaign ?? 'Convite',     // c no dashboard
      referrerName: referrerName,
      customerID: referrerId,
      baseDeepLink: 'boora://main',
      customParams: {
        'deep_link_value': 'invite',
        'deep_link_sub1': 'new_member',    // Conforme dashboard
        'deep_link_sub2': referrerId,       // Referrer ID
        'af_sub1': referrerId,              // Backup para raw data
      },
    );

    _appsflyerSdk.generateInviteLink(
      params,
      (dynamic result) {
        AppLogger.success('✅ Link de convite gerado: $result', tag: 'APPSFLYER');
        if (!completer.isCompleted) {
          // O resultado vem como: {status: success, payload: {userInviteURL: https://...}}
          String? link;
          if (result is Map) {
            final payload = result['payload'];
            if (payload is Map) {
              link = payload['userInviteURL']?.toString();
            }
          } else if (result is String) {
            link = result;
          }
          completer.complete(link);
        }
      },
      (dynamic error) {
        AppLogger.error('❌ Erro ao gerar link de convite: $error', tag: 'APPSFLYER');
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );

    // Timeout de 10 segundos
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        AppLogger.warning('⏱️ Timeout ao gerar link de convite', tag: 'APPSFLYER');
        return null;
      },
    );
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
        AppLogger.info('Deep link encontrado: ${deepLinkResult.deepLink?.toString()}', tag: 'APPSFLYER');

        final deepLink = deepLinkResult.deepLink;
        final deepLinkValue = deepLink?.deepLinkValue;
        final referrerId = _extractReferrerIdFromDeepLink(deepLink);

        AppLogger.info('🔗 Deep link data - value: $deepLinkValue, referrerId: $referrerId', tag: 'APPSFLYER');

        if (referrerId != null) {
          AppLogger.info('✅ Chamando ReferralService.captureReferral com referrerId: $referrerId', tag: 'APPSFLYER');
          ReferralService.instance.captureReferral(
            referrerId: referrerId,
            deepLinkValue: deepLinkValue,
          );
        } else {
          AppLogger.warning('⚠️ referrerId é null - não foi possível extrair do deep link', tag: 'APPSFLYER');
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
    AppLogger.info('Dados de conversão de instalação: $installData', tag: 'APPSFLYER');
    
    // Verificar se é uma instalação orgânica ou paga
    final isFirstLaunch = installData['is_first_launch'] == true ||
      installData['is_first_launch']?.toString() == 'true';
    final isOrganic = isFirstLaunch && installData['af_status'] == 'Organic';
    
    AppLogger.info('📱 Install conversion - isFirstLaunch: $isFirstLaunch, isOrganic: $isOrganic', tag: 'APPSFLYER');
    
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

      AppLogger.info('🔗 Install data - referrerId: $referrerId, deepLinkValue: $deepLinkValue', tag: 'APPSFLYER');

      if (referrerId != null) {
        AppLogger.info('✅ Chamando ReferralService.captureReferral (install) com referrerId: $referrerId', tag: 'APPSFLYER');
        ReferralService.instance.captureReferral(
          referrerId: referrerId,
          deepLinkValue: deepLinkValue,
        );
      } else {
        AppLogger.warning('⚠️ referrerId é null no install data', tag: 'APPSFLYER');
      }
    }
  }

  /// Processa o deep link recebido
  void _processDeepLink(String deepLinkValue) {
    AppLogger.info('Processando deep link: $deepLinkValue', tag: 'APPSFLYER');
    
    // Deep links de convite (invite) não precisam de navegação
    // O ReferralService já capturou o referrerId
    if (deepLinkValue == 'invite' || deepLinkValue.contains('invite')) {
      AppLogger.info('Deep link de convite detectado - referral já foi capturado', tag: 'APPSFLYER');
      return;
    }
    
    // Deep link para main (home) - não precisa navegar pois já estamos no app
    if (deepLinkValue.contains('main')) {
      AppLogger.info('Deep link para main - usuário já está no app', tag: 'APPSFLYER');
      return;
    }
    
    // TODO: Implementar navegação baseada no deep link para outras rotas
    // Exemplo:
    // if (deepLinkValue.contains('profile')) {
    //   // Navegar para perfil específico
    // } else if (deepLinkValue.contains('event')) {
    //   // Navegar para evento específico
    // }
  }

  /// Define o ID do usuário (opcional)
  Future<void> setCustomerUserId(String userId) async {
    if (!_isInitialized) {
      AppLogger.warning('AppsFlyer não inicializado');
      return;
    }

    try {
      _appsflyerSdk.setCustomerUserId(userId); // Método é void, não retorna Future
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

    // Log todos os dados disponíveis do deep link para debug
    AppLogger.info('🔍 DeepLink.toString(): ${deepLink.toString()}', tag: 'APPSFLYER');
    AppLogger.info('🔍 DeepLink.deepLinkValue: ${deepLink.deepLinkValue}', tag: 'APPSFLYER');
    AppLogger.info('🔍 DeepLink.clickEvent: ${deepLink.clickEvent}', tag: 'APPSFLYER');

    // Tenta extrair de getStringValue (método oficial)
    var candidate = deepLink.getStringValue('deep_link_sub2');
    AppLogger.info('🔍 getStringValue(deep_link_sub2): $candidate', tag: 'APPSFLYER');

    // Fallback: tenta extrair do clickEvent (como no iOS nativo)
    if (candidate == null || candidate.trim().isEmpty) {
      final clickEvent = deepLink.clickEvent;
      if (clickEvent != null) {
        candidate = clickEvent['deep_link_sub2']?.toString();
        AppLogger.info('🔍 clickEvent[deep_link_sub2]: $candidate', tag: 'APPSFLYER');
      }
    }

    // Fallbacks adicionais
    if (candidate == null || candidate.trim().isEmpty) {
      candidate = deepLink.getStringValue('deep_link_sub1');
      AppLogger.info('🔍 getStringValue(deep_link_sub1): $candidate', tag: 'APPSFLYER');
    }

    if (candidate == null || candidate.trim().isEmpty) {
      candidate = deepLink.getStringValue('af_sub1');
      AppLogger.info('🔍 getStringValue(af_sub1): $candidate', tag: 'APPSFLYER');
    }

    // Tenta também do clickEvent para af_sub1
    if (candidate == null || candidate.trim().isEmpty) {
      final clickEvent = deepLink.clickEvent;
      if (clickEvent != null) {
        candidate = clickEvent['af_sub1']?.toString();
        AppLogger.info('🔍 clickEvent[af_sub1]: $candidate', tag: 'APPSFLYER');
      }
    }

    if (candidate == null || candidate.trim().isEmpty) {
      AppLogger.warning('⚠️ Nenhum referrerId encontrado em nenhum campo', tag: 'APPSFLYER');
      return null;
    }

    AppLogger.info('✅ ReferrerId extraído: $candidate', tag: 'APPSFLYER');
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

  /// Loga evento de criação de link de convite
  /// 
  /// Conforme documentação AppsFlyer:
  /// "logInvite results in an af_invite in-app event"
  /// 
  /// [channel] - Canal de compartilhamento (ex: 'whatsapp', 'telegram', 'clipboard')
  /// [referrerId] - ID do usuário que está convidando
  /// [campaign] - Campanha associada ao convite (default: 'Convite')
  Future<void> logInvite({
    required String channel,
    required String referrerId,
    String? campaign,
    Map<String, dynamic>? additionalParams,
  }) async {
    if (!_isInitialized) {
      AppLogger.warning('AppsFlyer não inicializado. logInvite ignorado.', tag: 'APPSFLYER');
      return;
    }

    try {
      // Parâmetros conforme Dashboard AppsFlyer
      final eventValues = <String, dynamic>{
        'af_channel': channel,
        'campaign': campaign ?? 'Convite',  // Conforme dashboard
        'referrerId': referrerId,
        'deep_link_sub1': 'new_member',     // Conforme dashboard
        'deep_link_sub2': referrerId,
        ...?additionalParams,
      };

      // Usa logEvent com nome 'af_invite' conforme documentação
      await _appsflyerSdk.logEvent('af_invite', eventValues);

      AppLogger.info(
        '📤 Evento af_invite enviado - channel: $channel, referrerId: $referrerId',
        tag: 'APPSFLYER',
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao logar evento af_invite',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Loga evento de compra com referrer ID para recompensas
  /// 
  /// Conforme documentação AppsFlyer:
  /// "Retrieve user A's referrer ID and add it to one of the customizable 
  /// in-app event parameters (for example, af_param_1)"
  Future<void> logPurchaseWithReferrer({
    required double revenue,
    required String currency,
    String? referrerId,
    Map<String, dynamic>? additionalParams,
  }) async {
    if (!_isInitialized) {
      AppLogger.warning('AppsFlyer não inicializado. logPurchase ignorado.', tag: 'APPSFLYER');
      return;
    }

    try {
      final eventValues = <String, dynamic>{
        'af_revenue': revenue,
        'af_currency': currency,
        if (referrerId != null) 'af_param_1': referrerId, // Conforme documentação
        ...?additionalParams,
      };

      await _appsflyerSdk.logEvent(eventPurchase, eventValues);

      AppLogger.info(
        '💰 Evento af_purchase enviado - revenue: $revenue $currency, referrerId: $referrerId',
        tag: 'APPSFLYER',
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao logar evento af_purchase',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
