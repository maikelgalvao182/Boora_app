import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:partiu/core/services/location_cache.dart';
import 'package:partiu/core/services/cache/last_known_location_cache_repository.dart';
import 'package:partiu/core/services/location_analytics_service.dart';

/// Serviço central de localização do aplicativo
/// 
/// Responsabilidades:
/// - Obter localização atual (única vez)
/// - Iniciar/parar rastreamento contínuo via stream
/// - Armazenar última posição conhecida
/// - Notificar listeners quando posição muda
/// - Lidar com timeouts e erros
/// 
/// Este serviço usa ChangeNotifier para notificar a UI sobre mudanças
class LocationService extends ChangeNotifier {
  
  Position? _lastKnownPosition;
  StreamSubscription<Position>? _positionStream;
  bool _isTracking = false;
  final LastKnownLocationCacheRepository _persistentLocationCache =
      LastKnownLocationCacheRepository();

  /// Última posição conhecida do usuário
  Position? get lastKnownPosition => _lastKnownPosition;

  /// Se o serviço está rastreando localização ativamente
  bool get isTracking => _isTracking;

  /// Obtém a localização atual do dispositivo uma única vez
  /// 
  /// Estratégia em camadas (estilo Tinder/Uber):
  /// 1. Tenta usar cache válido (< 15 min)
  /// 2. Tenta obter alta precisão com timeout
  /// 3. Fallback: última localização conhecida (baixa precisão)
  /// 
  /// Usa timeout para evitar travamentos
  /// Retorna `null` em caso de erro ou timeout
  Future<Position?> getCurrentLocation({
    Duration timeout = const Duration(seconds: 10),
    bool useCache = true,
  }) async {
    final analytics = LocationAnalyticsService.instance;
    final cache = LocationCache.instance;
    
    try {
      // 1️⃣ Tenta usar cache válido primeiro (se permitido)
      if (useCache && cache.isValid()) {
        debugPrint('✅ Usando localização em cache (${cache.getCacheAgeMinutes()} min)');
        analytics.logUsedCache(cacheAgeMinutes: cache.getCacheAgeMinutes() ?? 0);
        return cache.lastPosition;
      }

      // 1.5️⃣ Tenta usar cache persistente do Hive (cold start)
      if (useCache) {
        final persistent = await _persistentLocationCache.getCached();
        if (persistent != null) {
          final cachedPosition = _persistentLocationCache.toPosition(persistent);
          cache.update(cachedPosition);
          _lastKnownPosition = cachedPosition;
          notifyListeners();
          analytics.logUsedCache(cacheAgeMinutes: persistent.ageMinutes);
          return cachedPosition;
        }
      }
      
      // 2️⃣ Tenta obter posição com alta precisão
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(timeout);

        // Atualiza cache
        cache.update(position);
        unawaited(_persistentLocationCache.cachePosition(position));
        
        // Log analytics
        analytics.logLocationUpdated(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
        );
        
        _lastKnownPosition = position;
        notifyListeners();

        return position;
      } on TimeoutException {
        debugPrint('⏱️ Timeout ao obter alta precisão - tentando fallback');
        analytics.logLocationTimeout(timeout.inSeconds);
        
        // 3️⃣ Fallback: tenta última localização conhecida (baixa precisão)
        return await _getFallbackLocation();
      }
    } catch (e) {
      debugPrint('❌ Erro ao obter localização atual: $e');
      analytics.logLocationError(e.toString());
      
      // Tenta fallback em caso de erro
      return await _getFallbackLocation();
    }
  }
  
  /// Obtém última localização conhecida como fallback
  /// 
  /// Usado quando:
  /// - GPS está lento
  /// - Alta precisão falhou
  /// - Timeout ocorreu
  /// 
  /// Precisão pode ser menor, mas é melhor que nada
  Future<Position?> _getFallbackLocation() async {
    final analytics = LocationAnalyticsService.instance;
    final cache = LocationCache.instance;
    
    try {
      debugPrint('📍 Tentando obter última localização conhecida (fallback)');
      
      final lastKnown = await Geolocator.getLastKnownPosition();
      
      if (lastKnown != null) {
        debugPrint('✅ Fallback bem-sucedido com precisão: ${lastKnown.accuracy}m');
        analytics.logUsedLowAccuracyFallback();
        
        // Atualiza cache mesmo sendo menos precisa
        cache.update(lastKnown);
        unawaited(_persistentLocationCache.cachePosition(lastKnown));
        
        _lastKnownPosition = lastKnown;
        notifyListeners();
        
        return lastKnown;
      }
    } catch (e) {
      debugPrint('❌ Erro no fallback: $e');
    }
    
    return null;
  }

  /// Inicia o rastreamento contínuo de localização
  /// 
  /// Parâmetros:
  /// - `distanceFilter`: distância mínima (em metros) para notificar nova posição
  /// - `accuracy`: precisão desejada
  /// 
  /// O stream notifica automaticamente quando o usuário se move
  Future<void> startLiveTracking({
    int distanceFilter = 20,
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    if (_isTracking) {
      debugPrint('⚠️ Rastreamento já está ativo');
      return;
    }

    try {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
        ),
      ).listen(
        (Position position) {
          _lastKnownPosition = position;
          notifyListeners();
          debugPrint('📍 Nova posição: ${position.latitude}, ${position.longitude}');
          unawaited(_persistentLocationCache.cachePosition(position));
        },
        onError: (error) {
          debugPrint('❌ Erro no stream de localização: $error');
        },
      );

      _isTracking = true;
      notifyListeners();
      debugPrint('✅ Rastreamento de localização iniciado');
    } catch (e) {
      debugPrint('❌ Erro ao iniciar rastreamento: $e');
      _isTracking = false;
    }
  }

  /// Para o rastreamento contínuo de localização
  void stopLiveTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    notifyListeners();
    debugPrint('🛑 Rastreamento de localização parado');
  }

  /// Calcula a distância em metros entre a última posição conhecida e coordenadas fornecidas
  double? distanceFromLastKnown(double latitude, double longitude) {
    if (_lastKnownPosition == null) return null;

    return Geolocator.distanceBetween(
      _lastKnownPosition!.latitude,
      _lastKnownPosition!.longitude,
      latitude,
      longitude,
    );
  }

  /// Verifica se a posição mudou significativamente desde a última atualização
  /// 
  /// Útil para decidir se vale a pena atualizar o Firestore
  bool hasMovedSignificantly(
    Position newPosition, {
    double thresholdMeters = 100,
  }) {
    if (_lastKnownPosition == null) return true;

    final distance = Geolocator.distanceBetween(
      _lastKnownPosition!.latitude,
      _lastKnownPosition!.longitude,
      newPosition.latitude,
      newPosition.longitude,
    );

    return distance > thresholdMeters;
  }

  /// Retorna as coordenadas formatadas como string legível
  String? getFormattedCoordinates() {
    if (_lastKnownPosition == null) return null;

    return '${_lastKnownPosition!.latitude.toStringAsFixed(6)}, '
           '${_lastKnownPosition!.longitude.toStringAsFixed(6)}';
  }

  @override
  void dispose() {
    stopLiveTracking();
    super.dispose();
  }
}
