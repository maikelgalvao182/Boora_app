import 'dart:io';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// Resultado da verificação de atualização obrigatória
enum ForceUpdateResult {
  /// App está atualizado, pode continuar
  upToDate,
  /// Atualização obrigatória necessária
  forceUpdateRequired,
  /// Atualização recomendada (não obrigatória)
  updateRecommended,
  /// Erro na verificação (continua normalmente)
  error,
}

/// Informações sobre a atualização
class UpdateInfo {
  final ForceUpdateResult result;
  final String currentVersion;
  final String minimumVersion;
  final String? recommendedVersion;
  final String? updateMessage;
  final String? storeUrl;

  const UpdateInfo({
    required this.result,
    required this.currentVersion,
    required this.minimumVersion,
    this.recommendedVersion,
    this.updateMessage,
    this.storeUrl,
  });
}

/// Serviço para verificar e forçar atualizações do app
/// 
/// Usa Firebase Remote Config para definir:
/// - `force_update_minimum_version`: versão mínima obrigatória (ex: "1.0.2")
/// - `force_update_recommended_version`: versão recomendada (opcional)
/// - `force_update_message`: mensagem customizada (opcional)
/// - `force_update_enabled`: habilita/desabilita o check (default: true)
/// 
/// Configuração no Firebase Console > Remote Config:
/// 1. Adicionar parâmetro `force_update_minimum_version` = "1.0.0"
/// 2. Quando precisar forçar update, alterar para a versão desejada
/// 3. Publicar as alterações
class ForceUpdateService {
  ForceUpdateService._();
  static final ForceUpdateService _instance = ForceUpdateService._();
  static ForceUpdateService get instance => _instance;

  static const String _tag = 'ForceUpdate';

  // Chaves do Remote Config
  static const String _keyEnabled = 'force_update_enabled';
  static const String _keyMinVersion = 'force_update_minimum_version';
  static const String _keyRecommendedVersion = 'force_update_recommended_version';
  static const String _keyMessage = 'force_update_message';
  static const String _keyMessagePt = 'force_update_message_pt';
  static const String _keyAndroidUrl = 'force_update_android_url';
  static const String _keyIosUrl = 'force_update_ios_url';

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;
  bool _initialized = false;
  PackageInfo? _packageInfo;

  /// Inicializa o Remote Config com valores padrão
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Obter informações do pacote
      _packageInfo = await PackageInfo.fromPlatform();

      // Configurar Remote Config
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? const Duration(minutes: 1) // Dev: 1 min
            : const Duration(hours: 1),   // Prod: 1 hora
      ));

      // Valores padrão (usados se não conseguir buscar)
      await _remoteConfig.setDefaults({
        _keyEnabled: true,
        _keyMinVersion: '1.0.37',
        _keyRecommendedVersion: '',
        _keyMessage: 'A new version is available. Please update to continue.',
        _keyMessagePt: 'Uma nova versão está disponível. Por favor, atualize para continuar.',
        _keyAndroidUrl: 'https://play.google.com/store/apps/details?id=com.boora.partiu',
        _keyIosUrl: 'https://apps.apple.com/app/boora/id123456789', // TODO: Atualizar com ID real
      });

      // Buscar e ativar valores remotos com retry
      try {
        await _remoteConfig.fetchAndActivate();
      } catch (fetchError) {
        // Se fetch falhar (cancelado, rede, etc), usa valores em cache ou defaults
        final errorStr = fetchError.toString().toLowerCase();
        if (errorStr.contains('cancelled') || errorStr.contains('canceled')) {
          AppLogger.warning(
            'Remote Config fetch cancelado - usando valores em cache/default',
            tag: _tag,
          );
        } else {
          AppLogger.warning(
            'Remote Config fetch falhou: $fetchError - usando valores em cache/default',
            tag: _tag,
          );
        }
        // Tenta ativar valores em cache se disponíveis
        try {
          await _remoteConfig.activate();
        } catch (_) {
          // Ignora - usa defaults
        }
      }

      _initialized = true;
      AppLogger.info(
        'ForceUpdate inicializado (currentVersion=${_packageInfo?.version})',
        tag: _tag,
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao inicializar ForceUpdate: $e',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      // Não falha a inicialização do app
      _initialized = true;
    }
  }

  /// Verifica se há atualização obrigatória
  /// 
  /// Retorna [UpdateInfo] com o resultado da verificação
  Future<UpdateInfo> checkForUpdate({String? languageCode}) async {
    await initialize();

    final currentVersion = _packageInfo?.version ?? '0.0.0';

    try {
      // Verificar se está habilitado
      final enabled = _remoteConfig.getBool(_keyEnabled);
      if (!enabled) {
        AppLogger.info('ForceUpdate desabilitado via Remote Config', tag: _tag);
        return UpdateInfo(
          result: ForceUpdateResult.upToDate,
          currentVersion: currentVersion,
          minimumVersion: '0.0.0',
        );
      }

      // Obter versões do Remote Config
      final minimumVersion = _remoteConfig.getString(_keyMinVersion);
      final recommendedVersion = _remoteConfig.getString(_keyRecommendedVersion);
      
      // Mensagem (com suporte a PT)
      final message = languageCode == 'pt'
          ? _remoteConfig.getString(_keyMessagePt)
          : _remoteConfig.getString(_keyMessage);

      // URL da loja
      final storeUrl = Platform.isIOS
          ? _remoteConfig.getString(_keyIosUrl)
          : _remoteConfig.getString(_keyAndroidUrl);

      AppLogger.info(
        'Verificando versão: current=$currentVersion, minimum=$minimumVersion, recommended=$recommendedVersion',
        tag: _tag,
      );

      // Comparar versões
      final compareMinimum = _compareVersions(currentVersion, minimumVersion);
      
      if (compareMinimum < 0) {
        // Versão atual é menor que a mínima - FORÇA UPDATE
        AppLogger.warning(
          'Atualização obrigatória: $currentVersion < $minimumVersion',
          tag: _tag,
        );
        return UpdateInfo(
          result: ForceUpdateResult.forceUpdateRequired,
          currentVersion: currentVersion,
          minimumVersion: minimumVersion,
          recommendedVersion: recommendedVersion.isNotEmpty ? recommendedVersion : null,
          updateMessage: message,
          storeUrl: storeUrl,
        );
      }

      // Verificar se há versão recomendada
      if (recommendedVersion.isNotEmpty) {
        final compareRecommended = _compareVersions(currentVersion, recommendedVersion);
        if (compareRecommended < 0) {
          AppLogger.info(
            'Atualização recomendada: $currentVersion < $recommendedVersion',
            tag: _tag,
          );
          return UpdateInfo(
            result: ForceUpdateResult.updateRecommended,
            currentVersion: currentVersion,
            minimumVersion: minimumVersion,
            recommendedVersion: recommendedVersion,
            updateMessage: message,
            storeUrl: storeUrl,
          );
        }
      }

      AppLogger.info('App está atualizado', tag: _tag);
      return UpdateInfo(
        result: ForceUpdateResult.upToDate,
        currentVersion: currentVersion,
        minimumVersion: minimumVersion,
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao verificar atualização: $e',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return UpdateInfo(
        result: ForceUpdateResult.error,
        currentVersion: currentVersion,
        minimumVersion: '0.0.0',
      );
    }
  }

  /// Compara duas versões semânticas
  /// 
  /// Retorna:
  /// - < 0 se v1 < v2
  /// - 0 se v1 == v2
  /// - > 0 se v1 > v2
  int _compareVersions(String v1, String v2) {
    try {
      // Remove prefixos como "v" se existirem
      v1 = v1.replaceAll(RegExp(r'^v'), '');
      v2 = v2.replaceAll(RegExp(r'^v'), '');

      final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      // Preenche com zeros se necessário
      while (parts1.length < 3) parts1.add(0);
      while (parts2.length < 3) parts2.add(0);

      for (var i = 0; i < 3; i++) {
        if (parts1[i] < parts2[i]) return -1;
        if (parts1[i] > parts2[i]) return 1;
      }

      return 0;
    } catch (e) {
      AppLogger.warning('Erro ao comparar versões: $v1 vs $v2', tag: _tag);
      return 0;
    }
  }

  /// Força refresh do Remote Config (útil para testes)
  Future<void> forceRefresh() async {
    try {
      await _remoteConfig.fetchAndActivate();
      AppLogger.info('Remote Config atualizado', tag: _tag);
    } catch (e) {
      AppLogger.warning('Erro ao atualizar Remote Config: $e', tag: _tag);
    }
  }

  /// Versão atual do app
  String get currentVersion => _packageInfo?.version ?? '0.0.0';
  
  /// Build number do app
  String get buildNumber => _packageInfo?.buildNumber ?? '0';
}
