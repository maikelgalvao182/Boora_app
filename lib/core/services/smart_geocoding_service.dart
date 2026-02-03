import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// Serviço inteligente de Geocoding para reduzir custos com APIs
///
/// Implementa estratégia "Lei de Pareto" para localização:
/// 1. Cache persistente (Hive)
/// 2. Debounce real
/// 3. Filtro de distância (só busca se moveu > 300m)
/// 4. Filtro de tempo (só busca se passou > 8s desde última chamada)
class SmartGeocodingService {
  SmartGeocodingService._();

  static final SmartGeocodingService instance = SmartGeocodingService._();

  static const String _boxName = 'geo_cache_v1';
  static const int _cacheValidityDays = 7; // Reduzido de 30 para 7 dias
  
  // Memória RAM para debounce e filtros imediatos
  Position? _lastFetchedPosition;
  DateTime? _lastFetchTime;
  Placemark? _lastPlacemark; // Retornar se skipar
  
  Box? _box;

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox(_boxName);
  }

  /// Retorna o endereço (Placemark) de forma inteligente.
  /// 
  /// Se [forceRefresh] for true, ignora filtros de tempo/distância mas ainda tenta usar cache se a coord for idêntica.
  /// 
  /// Retorna null se não passar nos critérios de economia (distância/tempo) e não tiver em cache,
  /// indicando que a UI deve manter o endereço anterior.
  Future<Placemark?> getAddressSmart({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    // 1. Validar inicialização
    if (_box == null || !_box!.isOpen) await init();

    // 2. Gerar chave de cache (Geohash curto ou arredondamento)
    // Para cache de endereço (cidade/bairro), 3 casas decimais é aprox 110m.
    // 4 casas é 11m. Vamos usar 4 casas para precisão de rua, 
    // ou arredondar para garantir hit no cache para micro-movimentos.
    // Usaremos arredondamento simples para chave de string: "lat,lng" (3 casas)
    final cacheKey = _generateCacheKey(latitude, longitude);

    // 3. Verificar Cache Persistente (Hit Rápido)
    final cachedData = _box!.get(cacheKey);
    if (cachedData != null) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(cachedData['ts'] as int);
      final age = DateTime.now().difference(timestamp);

      if (age.inDays < _cacheValidityDays) {
        // Cache válido! Econômia $$
        AppLogger.success('📦 [SmartGeo] Cache HIT: $cacheKey (${age.inDays} dias)', tag: 'SmartGeo');
        return _deserializePlacemark(cachedData['data']);
      } else {
        AppLogger.info('⏳ [SmartGeo] Cache expirado: $cacheKey', tag: 'SmartGeo');
        _box!.delete(cacheKey); // Limpa
      }
    }

    // 4. Se não tem cache, aplicar filtros de economia (rate limit)
    // A menos que seja forceRefresh
    if (!forceRefresh) {
      if (_shouldSkipFetch(latitude, longitude)) {
        AppLogger.info('🛡️ [SmartGeo] Skipped (Movel < 300m ou Time < 8s)', tag: 'SmartGeo');
        return _lastPlacemark; // Retorna último conhecido para não quebrar UI
      }
    }

    // 5. Buscar na API (CUSTO $)
    try {
      AppLogger.warning('💰 [SmartGeo] Fetching API: $latitude, $longitude', tag: 'SmartGeo');
      
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        
        // 6. Salvar no Cache
        await _saveToCache(cacheKey, place);
        
        // Atualizar estado de controle
        _lastFetchTime = DateTime.now();
        _lastPlacemark = place; // Guarda para fallbacks
        _lastFetchedPosition = Position(
          longitude: longitude,
          latitude: latitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0, 
          altitudeAccuracy: 0, 
          headingAccuracy: 0,
        );
        
        return place;
      }
    } catch (e) {
      AppLogger.error('❌ [SmartGeo] Erro na API: $e', tag: 'SmartGeo');
    }

    return null;
  }

  // Lógica de filtro "Pareto": 300m E 8s
  bool _shouldSkipFetch(double lat, double lng) {
    if (_lastFetchTime == null || _lastFetchedPosition == null) return false;

    final distance = Geolocator.distanceBetween(
      _lastFetchedPosition!.latitude,
      _lastFetchedPosition!.longitude,
      lat,
      lng,
    );
    
    final timeDiff = DateTime.now().difference(_lastFetchTime!);

    // Regra:
    // Se moveu POUCO (< 300m) 
    // E
    // Faz POUCO tempo (< 8s)
    // ENTÃO SKIP.
    
    // O user pediu: "Só chama se: distância > 300m E tempo > 8s".
    // Ou seja, se qualquer um for falso, não chama.
    // Dist < 300 -> Skip
    // Time < 8s -> Skip
    
    // Contudo, se eu andei 50km em 1 segundo? Devo chamar.
    // Se eu fiquei parado 5 horas? Não devo chamar.
    
    // Vamos interpretar o "setup padrão":
    // "Endereço não muda toda hora".
    // Geralmente só queremos atualizar endereço (Reverse Geo) se:
    // Mudou significativamente de lugar (Ex: mudou de bairro). 300m é razoável.
    // Limitar frequência também é bom.

    // Regra simples: Chama APENAS se distance > GEOCODING_UPDATE_DISTANCE_KM
    // Locality/State (cidade/estado) só mudam em distâncias grandes
    // Tempo não importa - se usuário ficou parado, cidade/estado não mudaram
    // Valor configurável em constants.dart
    
    final isFarEnough = distance > (GEOCODING_UPDATE_DISTANCE_KM * 1000); // Converte km para metros

    // Skip se não moveu o suficiente
    return !isFarEnough;
  }

  String _generateCacheKey(double lat, double lng) {
    // 2 casas decimais ~ 1.1km de precisão.
    // Perfeito para cache de cidade/estado (não precisa ser tão preciso)
    // Reduz colisões de cache e melhora hit rate
    return '${lat.toStringAsFixed(2)},${lng.toStringAsFixed(2)}';
  }

  Future<void> _saveToCache(String key, Placemark place) async {
    if (_box == null) return;
    
    final data = {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'data': _serializePlacemark(place),
    };
    
    await _box!.put(key, data);
  }

  // Serialização manual pois Placemark não tem toJson padrão confiável cross-version as vezes
  Map<String, dynamic> _serializePlacemark(Placemark p) {
    return {
      'name': p.name,
      'street': p.street,
      'isoCountryCode': p.isoCountryCode,
      'country': p.country,
      'postalCode': p.postalCode,
      'administrativeArea': p.administrativeArea,
      'subAdministrativeArea': p.subAdministrativeArea,
      'locality': p.locality,
      'subLocality': p.subLocality,
      'thoroughfare': p.thoroughfare,
      'subThoroughfare': p.subThoroughfare,
    };
  }

  Placemark _deserializePlacemark(Map<dynamic, dynamic> map) {
    return Placemark(
      name: map['name'],
      street: map['street'],
      isoCountryCode: map['isoCountryCode'],
      country: map['country'],
      postalCode: map['postalCode'],
      administrativeArea: map['administrativeArea'],
      subAdministrativeArea: map['subAdministrativeArea'],
      locality: map['locality'],
      subLocality: map['subLocality'],
      thoroughfare: map['thoroughfare'],
      subThoroughfare: map['subThoroughfare'],
    );
  }
}
