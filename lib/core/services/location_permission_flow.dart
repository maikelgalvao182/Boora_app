import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:partiu/core/services/location_analytics_service.dart';

/// Serviço responsável exclusivamente por gerenciar o fluxo de permissões de localização
/// 
/// Responsabilidades:
/// - Checar permissão atual
/// - Solicitar permissão
/// - Verificar se GPS está habilitado
/// - Resolver estado final de permissão
/// - Abrir configurações do sistema
/// 
/// Este serviço NÃO obtém coordenadas - apenas gerencia permissões
class LocationPermissionFlow {
  static Future<LocationPermission>? _requestInFlight;

  /// Etapa 1: Verifica o status atual da permissão de localização
  Future<LocationPermission> check() async {
    return await Geolocator.checkPermission();
  }

  /// Etapa 2: Solicita permissão ao usuário
  Future<LocationPermission> request() async {
    if (_requestInFlight != null) {
      return _requestInFlight!;
    }

    final completer = Completer<LocationPermission>();
    _requestInFlight = completer.future;

    try {
      final result = await Geolocator.requestPermission();
      completer.complete(result);
      return result;
    } catch (e, stackTrace) {
      completer.completeError(e, stackTrace);
      rethrow;
    } finally {
      _requestInFlight = null;
    }
  }

  /// Etapa 3: Verifica se o serviço de localização (GPS) está ativo no dispositivo
  Future<bool> isGpsEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Abre as configurações do aplicativo no sistema operacional
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Abre as configurações de localização do dispositivo
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Resolve o estado final da permissão com lógica inteligente
  /// 
  /// Se permissão for `denied`, tenta solicitar novamente
  /// Retorna o estado final da permissão
  /// 
  /// Registra eventos de analytics para monitoramento
  Future<LocationPermission> resolvePermission() async {
    final analytics = LocationAnalyticsService.instance;
    final currentPermission = await check();

    // Se já foi negada permanentemente, não tenta solicitar novamente
    if (currentPermission == LocationPermission.deniedForever) {
      analytics.logPermissionDeniedForever();
      return currentPermission;
    }

    // Se está negada, solicita ao usuário
    if (currentPermission == LocationPermission.denied) {
      final newPermission = await request();
      
      // Log do resultado
      if (isPermissionGranted(newPermission)) {
        analytics.logPermissionGranted();
      } else if (newPermission == LocationPermission.deniedForever) {
        analytics.logPermissionDeniedForever();
      } else {
        analytics.logPermissionDenied();
      }
      
      return newPermission;
    }

    // Se já tem permissão (whileInUse ou always)
    if (isPermissionGranted(currentPermission)) {
      analytics.logPermissionGranted();
    }
    
    return currentPermission;
  }

  /// Verifica se a permissão atual permite acessar localização
  bool isPermissionGranted(LocationPermission permission) {
    return permission == LocationPermission.whileInUse ||
           permission == LocationPermission.always;
  }

  /// Fluxo completo: verifica GPS e permissões
  /// 
  /// Retorna um mapa com:
  /// - `gpsEnabled`: bool
  /// - `permission`: LocationPermission
  /// - `canAccessLocation`: bool
  /// 
  /// Registra eventos de analytics
  Future<Map<String, dynamic>> checkFullStatus() async {
    final analytics = LocationAnalyticsService.instance;
    final gpsEnabled = await isGpsEnabled();
    final permission = await check();
    final canAccess = isPermissionGranted(permission) && gpsEnabled;

    // Log se GPS estiver desligado
    if (!gpsEnabled) {
      analytics.logGpsDisabled();
    }

    return {
      'gpsEnabled': gpsEnabled,
      'permission': permission,
      'canAccessLocation': canAccess,
    };
  }
}
