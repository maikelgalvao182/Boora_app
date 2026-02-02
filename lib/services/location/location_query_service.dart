import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/services/location/geo_utils.dart';
import 'package:partiu/services/location/distance_isolate.dart';
import 'package:partiu/services/location/location_stream_controller.dart';
import 'package:partiu/services/location/people_cloud_service.dart';
import 'package:partiu/core/constants/constants.dart';

/// Serviço principal para queries de localização com filtro de raio
/// 
/// 🔒 REFATORADO para usar Cloud Function (server-side security)
/// 
/// Responsabilidades:
/// - Chamar Cloud Function getPeople (server-side limit + ordering)
/// - Cache com TTL (30 segundos)
/// - Bounding box para queries otimizadas
/// - Cálculo de distâncias no client (melhor performance)
/// - Stream de atualizações automáticas
/// - Filtros sociais (gênero, idade, verificado, interesses)
/// 
/// SEGURANÇA:
/// - ✅ Limite de resultados aplicado no servidor (impossível burlar)
/// - ✅ Ordenação VIP garantida pelo backend
/// - ✅ Status VIP verificado no Firestore (não confia no client)
/// 
/// USO:
/// - find_people_screen.dart: Descoberta de pessoas próximas
/// 
/// NÃO USAR MAIS PARA:
/// - discover_screen.dart: Usa EventMapRepository diretamente
/// - Filtros de eventos: Lógica movida para MapViewModel
class LocationQueryService {
  /// Singleton
  static final LocationQueryService _instance =
      LocationQueryService._internal();
  factory LocationQueryService() => _instance;
  LocationQueryService._internal() {
    _initializeListeners();
  }

  /// Serviço de Cloud Function
  final _cloudService = PeopleCloudService();

  /// Cache de localização do usuário
  UserLocationCache? _userLocationCache;

  /// Cache de usuários próximos
  UsersCache? _usersCache;

  /// Filtros atuais
  UserFilterOptions _currentFilters = UserFilterOptions();

  /// Getter para outros componentes usarem os filtros atuais.
  UserFilterOptions get currentFilters => _currentFilters;

  /// Stream controller para usuários
  final _usersStreamController =
      StreamController<List<UserWithDistance>>.broadcast();

  /// Timer para debounce de reloads
  Timer? _reloadDebounceTimer;

  /// TTL do cache (30 segundos)
  static const Duration cacheTTL = Duration(seconds: 30);

  /// Stream de usuários
  Stream<List<UserWithDistance>> get usersStream =>
      _usersStreamController.stream;

  /// Inicializa listeners para mudanças de raio/localização
  void _initializeListeners() {
    final streamController = LocationStreamController();

    // Listener de mudanças de raio
    streamController.radiusStream.listen((radiusKm) {
      debugPrint('🔄 LocationQueryService: Raio mudou para $radiusKm km');
      _invalidateUsersCache();
      _scheduleReload(radiusKm: radiusKm);
    });

    // Listener de reload manual
    streamController.reloadStream.listen((_) {
      debugPrint('🔄 LocationQueryService: Reload manual solicitado');
      _invalidateAllCaches();
      _scheduleReload();
    });
  }

  /// Agenda reload com debounce para evitar queries simultâneas
  void _scheduleReload({double? radiusKm}) {
    // Cancelar reload pendente
    _reloadDebounceTimer?.cancel();
    
    // Agendar novo reload após 300ms
    _reloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _loadAndEmitUsers(radiusKm: radiusKm);
    });
  }

  /// Atualiza os filtros e recarrega usuários
  void updateFilters(UserFilterOptions filters) {
    _currentFilters = filters;
    debugPrint('🔍 LocationQueryService.updateFilters: radiusKm = ${filters.radiusKm}');
    debugPrint('🔍 LocationQueryService.updateFilters: gender = ${filters.gender}');
    debugPrint('🔍 LocationQueryService.updateFilters: age = ${filters.minAge}-${filters.maxAge}');
    debugPrint('🔍 LocationQueryService.updateFilters: verified = ${filters.isVerified}');
    debugPrint('🔍 LocationQueryService.updateFilters: interests = ${filters.interests}');
    debugPrint('🔄 LocationQueryService: Filtros atualizados');
    _invalidateUsersCache();
    
    // Usar debounce para evitar race conditions
    _scheduleReload(radiusKm: filters.radiusKm);
  }

  /// Busca usuários dentro do raio - versão única (sem stream)
  /// 
  /// 🔒 USA CLOUD FUNCTION (server-side security)
  /// 
  /// Fluxo:
  /// 1. Carrega localização do usuário
  /// 2. Calcula bounding box
  /// 3. Chama Cloud Function getPeople (limite + ordenação VIP no servidor)
  /// 4. Calcula distâncias no client (melhor performance)
  /// 5. Retorna lista já ordenada e limitada
  /// 
  /// ⚠️ LIMITE APLICADO NO SERVIDOR (impossível burlar)
  Future<List<UserWithDistance>> getUsersWithinRadiusOnce({
    double? customRadiusKm,
    UserFilterOptions? filters,
  }) async {
    try {
      final activeFilters = filters ?? _currentFilters;
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      
      if (currentUserId == null) {
        debugPrint('❌ LocationQueryService: Usuário não autenticado');
        return [];
      }

      // 1. Carregar localização do usuário
      final userLocation = await _getUserLocation();
      debugPrint('📍 LocationQueryService: User Location: ${userLocation.latitude}, ${userLocation.longitude}');

      // 2. Obter raio (prioridade: customRadiusKm → filters.radiusKm → Firestore)
      final radiusKmRaw = customRadiusKm ?? activeFilters.radiusKm ?? await _getUserRadius();
      final radiusKm = _normalizeRadiusKm(radiusKmRaw);
      debugPrint('🔍 getUsersWithinRadiusOnce: radiusKm FINAL = $radiusKm (custom=$customRadiusKm, filters=${activeFilters.radiusKm})');
      debugPrint('📍 LocationQueryService: Radius: ${radiusKm}km');

      // 3. Verificar cache de usuários (apenas se filtros não mudaram)
      if (_usersCache != null &&
          !_usersCache!.isExpired &&
          _usersCache!.radiusKm == radiusKm) {
        debugPrint('✅ LocationQueryService: Usando cache de usuários');
        return _usersCache!.users;
      }

      // 4. Calcular bounding box
      final boundingBox = GeoUtils.calculateBoundingBox(
        centerLat: userLocation.latitude,
        centerLng: userLocation.longitude,
        radiusKm: radiusKm,
      );

      // 5. Chamar Cloud Function (server-side security)
      debugPrint('☁️ LocationQueryService: Chamando Cloud Function getPeople...');
      
      final result = await _cloudService.getPeopleNearby(
        userLatitude: userLocation.latitude,
        userLongitude: userLocation.longitude,
        radiusKm: radiusKm,
        boundingBox: boundingBox,
        filters: UserCloudFilters(
          gender: activeFilters.gender,
          minAge: activeFilters.minAge,
          maxAge: activeFilters.maxAge,
          isVerified: activeFilters.isVerified,
          interests: activeFilters.interests,
          sexualOrientation: activeFilters.sexualOrientation,
        ),
      );

      debugPrint('📊 LocationQueryService: ${result.users.length} usuários retornados (limite: ${result.limitApplied})');
      
      final finalUsers = result.users;

      // 6. Ordenar por distância como tie-breaker
      finalUsers.sort((a, b) {
        // Cloud Function já ordenou por VIP e Rating
        // Apenas usar distância como desempate
        return a.distanceKm.compareTo(b.distanceKm);
      });

      // 7. Log da ordenação VIP (primeiros 5)
      if (finalUsers.isNotEmpty) {
        debugPrint('🏆 [LocationQueryService] Ordenação VIP - Primeiros ${finalUsers.length > 5 ? 5 : finalUsers.length}:');
        for (var i = 0; i < finalUsers.length && i < 5; i++) {
          final user = finalUsers[i];
          final vip = (user.userData['vip_priority'] as int?) ?? 2;
          final rating = (user.userData['overallRating'] as num?)?.toDouble() ?? 0.0;
          final name = user.userData['fullName'] ?? 'N/A';
          debugPrint('   ${i + 1}. $name - VIP:$vip ⭐${rating.toStringAsFixed(1)} 📍${user.distanceKm.toStringAsFixed(1)}km');
        }
      }

      // 8. ⚠️ REMOÇÃO DO LIMITE CLIENT-SIDE
      // O limite é aplicado no servidor, então não limitamos aqui
      // Isso garante que apenas o servidor controla o acesso

      // 9. Atualizar cache
      _usersCache = UsersCache(
        users: finalUsers,
        radiusKm: radiusKm,
        timestamp: DateTime.now(),
      );

      debugPrint(
          '✅ LocationQueryService: ${finalUsers.length} usuários retornados após todos os filtros');

      return finalUsers;
    } catch (e, stackTrace) {
      if (_isLargeAreaError(e) || _isMissingLocationError(e)) {
        debugPrint('⚠️ LocationQueryService: Erro de localização. Retornando vazio.');
        return [];
      }
      debugPrint('❌ LocationQueryService: Erro ao buscar usuários: $e');
      debugPrint('❌ LocationQueryService: StackTrace: $stackTrace');
      rethrow; // Propaga o erro para o controller tratar
    }
  }

  /// Busca usuários dentro de um bounding box (região visível do mapa).
  ///
  /// Diferença vs. getUsersWithinRadiusOnce:
  /// - Não calcula bounding box a partir do raio: o caller já fornece o bounds.
  /// - Calcula um radiusKm grande o suficiente para NÃO filtrar fora do bounds,
  ///   porque o filtro principal é o bounding box.
  /// - Mantém o cálculo de distância relativo ao usuário (para exibição no card).
  Future<List<UserWithDistance>> getUsersWithinBoundsOnce({
    required Map<String, double> boundingBox,
    UserFilterOptions? filters,
  }) async {
    final activeFilters = filters ?? _currentFilters;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) {
      debugPrint('❌ LocationQueryService: Usuário não autenticado (bounds)');
      return [];
    }

    // 1. Carregar localização do usuário (para distância no card)
    final userLocation = await _getUserLocation();

    // 2. Limitar bounding box para respeitar limite do servidor (MAX_DELTA_DEG = 0.6)
    final clampedBox = _clampBoundingBoxForServer(boundingBox);

    // 3. Definir raio: se o usuário selecionou um raio nos filtros, ele deve
    // realmente restringir os resultados. Caso contrário, usar um raio grande
    // o suficiente para cobrir o bounds (bounds como fonte de verdade).
    final radiusKm = (activeFilters.radiusKm != null)
        ? _normalizeRadiusKm(activeFilters.radiusKm!)
        : _radiusKmToCoverBoundingBox(
            centerLat: userLocation.latitude,
            centerLng: userLocation.longitude,
            boundingBox: clampedBox,
          );

    // 4. Chamar Cloud Function com o bounding box limitado
    final result = await _cloudService.getPeopleNearby(
      userLatitude: userLocation.latitude,
      userLongitude: userLocation.longitude,
      radiusKm: radiusKm,
      boundingBox: clampedBox,
      filters: UserCloudFilters(
        gender: activeFilters.gender,
        minAge: activeFilters.minAge,
        maxAge: activeFilters.maxAge,
        isVerified: activeFilters.isVerified,
        interests: activeFilters.interests,
        sexualOrientation: activeFilters.sexualOrientation,
      ),
    );

    final finalUsers = result.users;

    // Cloud Function já ordena por VIP e rating. Distância só como desempate.
    finalUsers.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    return finalUsers;
  }

  /// Busca usuários dentro do raio - versão stream (atualização automática)
  /// 
  /// Uso: Quando precisa de atualizações em tempo real de pessoas próximas
  Stream<List<UserWithDistance>> getUsersWithinRadiusStream({
    double? customRadiusKm,
  }) async* {
    while (true) {
      final users = await getUsersWithinRadiusOnce(
        customRadiusKm: customRadiusKm,
      );
      yield users;

      // Aguardar próxima atualização
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  /// Carrega usuários e emite no stream principal
  Future<void> _loadAndEmitUsers({double? radiusKm}) async {
    try {
      final users = await getUsersWithinRadiusOnce(customRadiusKm: radiusKm);
      if (!_usersStreamController.isClosed) {
        _usersStreamController.add(users);
      }
    } catch (e, stackTrace) {
      if (_isLargeAreaError(e) || _isMissingLocationError(e)) {
        debugPrint('⚠️ LocationQueryService: Erro de localização no stream. Emitindo vazio.');
        if (!_usersStreamController.isClosed) {
          _usersStreamController.add([]);
        }
        return;
      }
      debugPrint('❌ LocationQueryService: Falha ao emitir usuários: $e');
      debugPrint('❌ LocationQueryService: StackTrace: $stackTrace');
    }
  }

  bool _isLargeAreaError(Object error) {
    if (error is FirebaseFunctionsException) {
      final message = (error.message ?? '').toLowerCase();
      return message.contains('área de busca muito grande') ||
          message.contains('area de busca muito grande') ||
          message.contains('search area too large');
    }
    return false;
  }

  bool _isMissingLocationError(Object error) {
    return error is _MissingLocationException;
  }

  /// Busca localização do usuário (com cache)
  Future<UserLocationCache> _getUserLocation() async {
    // Verificar cache
    if (_userLocationCache != null && !_userLocationCache!.isExpired) {
      debugPrint('✅ LocationQueryService: Usando cache de localização (${_userLocationCache!.latitude}, ${_userLocationCache!.longitude})');
      return _userLocationCache!;
    }

    // Buscar do Firestore
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      debugPrint('❌ LocationQueryService._getUserLocation: userId é null');
      throw Exception('Usuário não autenticado');
    }

    debugPrint('🔍 LocationQueryService: Buscando localização do usuário em Users/$userId');
    
    // 🔒 Primeiro tenta buscar da subcoleção privada (localização REAL)
    final privateDoc = await FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .collection('private')
        .doc('location')
        .get();

    if (privateDoc.exists && privateDoc.data() != null) {
      final privateData = privateDoc.data()!;
      final latitude = privateData['latitude'] as double?;
      final longitude = privateData['longitude'] as double?;
      
      if (latitude != null && longitude != null) {
        debugPrint('✅ LocationQueryService: Localização carregada da subcoleção private ($latitude, $longitude)');
        _userLocationCache = UserLocationCache(
          latitude: latitude,
          longitude: longitude,
          timestamp: DateTime.now(),
        );
        return _userLocationCache!;
      }
    }
    
    // Fallback: buscar do documento principal (dados legados ou displayLatitude)
    final userDoc =
        await FirebaseFirestore.instance.collection('Users').doc(userId).get();

    if (!userDoc.exists || userDoc.data() == null) {
      debugPrint('❌ LocationQueryService: Documento do usuário NÃO ENCONTRADO em Users/$userId');
      throw Exception('Documento do usuário não existe em Users/$userId');
    }

    final data = userDoc.data()!;
    debugPrint('🔍 LocationQueryService: Documento encontrado, verificando campos...');
    debugPrint('🔍 LocationQueryService: Campos disponíveis: ${data.keys.toList()}');
    
    // Tenta latitude/longitude primeiro (legado), depois displayLatitude/displayLongitude
    final latitude = (data['latitude'] as double?) ?? (data['displayLatitude'] as double?);
    final longitude = (data['longitude'] as double?) ?? (data['displayLongitude'] as double?);
    
    debugPrint('🔍 LocationQueryService: latitude = $latitude');
    debugPrint('🔍 LocationQueryService: longitude = $longitude');

    if (latitude == null || longitude == null) {
      debugPrint('❌ LocationQueryService: Campos latitude/longitude AUSENTES!');
      if (_userLocationCache != null && !_userLocationCache!.isExpired) {
        debugPrint('⚠️ LocationQueryService: Usando cache antigo por ausência de lat/lng no Firestore');
        return _userLocationCache!;
      }
      throw _MissingLocationException(userId);
    }

    // Atualizar cache
    debugPrint('✅ LocationQueryService: Localização carregada com sucesso ($latitude, $longitude)');
    _userLocationCache = UserLocationCache(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
    );

    return _userLocationCache!;
  }

  /// Busca raio do usuário
  Future<double> _getUserRadius() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return 25.0; // Default

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;

        // Fonte preferida: advancedSettings.radiusKm (padrão atual do app)
        final settings = data['advancedSettings'] as Map<String, dynamic>?;
        final fromSettings = settings?['radiusKm'] as num?;
        if (fromSettings != null) {
          return fromSettings.toDouble();
        }

        // Fallback legado: campo top-level radiusKm
        final fromTopLevel = data['radiusKm'] as num?;
        return fromTopLevel?.toDouble() ?? 25.0;
      }
    } catch (e) {
      debugPrint('❌ LocationQueryService: Erro ao buscar raio: $e');
    }

    return 25.0; // Default
  }

  double _normalizeRadiusKm(double radiusKm) {
    if (!radiusKm.isFinite || radiusKm <= 0) {
      return DEFAULT_RADIUS_KM.clamp(MIN_RADIUS_KM, ENABLE_RADIUS_LIMIT ? MAX_RADIUS_KM : MAX_RADIUS_KM_EXTENDED);
    }

    // Alguns dados legados podem ter sido salvos em METROS (ex.: 3000) mas lidos como km.
    // Como o slider atual vai no máximo até 30km (ou 100km no modo extended),
    // qualquer valor muito acima disso é tratado como metros.
    final maxAllowed = ENABLE_RADIUS_LIMIT ? MAX_RADIUS_KM : MAX_RADIUS_KM_EXTENDED;
    final normalized = radiusKm > (maxAllowed * 10) ? (radiusKm / 1000.0) : radiusKm;

    return normalized.clamp(MIN_RADIUS_KM, maxAllowed);
  }

  /// Limite máximo do servidor para delta de latitude/longitude (~66km).
  /// Deve estar alinhado com MAX_DELTA_DEG em get_people.ts.
  static const double _maxServerDeltaDeg = 0.58; // Margem de segurança (server = 0.6)

  /// Limita o bounding box para respeitar o limite do servidor.
  /// 
  /// Se o bounds original for maior que o permitido, ele será reduzido
  /// mantendo o centro, evitando erro "Área de busca muito grande".
  Map<String, double> _clampBoundingBoxForServer(Map<String, double> boundingBox) {
    final minLat = boundingBox['minLat'];
    final maxLat = boundingBox['maxLat'];
    final minLng = boundingBox['minLng'];
    final maxLng = boundingBox['maxLng'];

    if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
      return boundingBox;
    }

    final deltaLat = (maxLat - minLat).abs();
    final deltaLng = (maxLng - minLng).abs();

    // Se ambos estão dentro do limite, retorna o original
    if (deltaLat <= _maxServerDeltaDeg && deltaLng <= _maxServerDeltaDeg) {
      return boundingBox;
    }

    // Calcula o centro e reduz o bounds para respeitar o limite
    final centerLat = (minLat + maxLat) / 2.0;
    final centerLng = (minLng + maxLng) / 2.0;

    final clampedHalfLat = math.min(deltaLat / 2.0, _maxServerDeltaDeg / 2.0);
    final clampedHalfLng = math.min(deltaLng / 2.0, _maxServerDeltaDeg / 2.0);

    debugPrint('⚠️ [LocationQueryService] Bounds muito grande, limitando:');
    debugPrint('   Original: lat=$deltaLat, lng=$deltaLng');
    debugPrint('   Limitado: lat=${clampedHalfLat * 2}, lng=${clampedHalfLng * 2}');

    return {
      'minLat': (centerLat - clampedHalfLat).clamp(-90.0, 90.0),
      'maxLat': (centerLat + clampedHalfLat).clamp(-90.0, 90.0),
      'minLng': (centerLng - clampedHalfLng).clamp(-180.0, 180.0),
      'maxLng': (centerLng + clampedHalfLng).clamp(-180.0, 180.0),
    };
  }

  double _radiusKmToCoverBoundingBox({
    required double centerLat,
    required double centerLng,
    required Map<String, double> boundingBox,
  }) {
    final minLat = boundingBox['minLat'];
    final maxLat = boundingBox['maxLat'];
    final minLng = boundingBox['minLng'];
    final maxLng = boundingBox['maxLng'];

    if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
      // Fallback conservador: 100km
      return 100.0;
    }

    final d1 = GeoUtils.calculateDistance(lat1: centerLat, lng1: centerLng, lat2: minLat, lng2: minLng);
    final d2 = GeoUtils.calculateDistance(lat1: centerLat, lng1: centerLng, lat2: minLat, lng2: maxLng);
    final d3 = GeoUtils.calculateDistance(lat1: centerLat, lng1: centerLng, lat2: maxLat, lng2: minLng);
    final d4 = GeoUtils.calculateDistance(lat1: centerLat, lng1: centerLng, lat2: maxLat, lng2: maxLng);

    // +1km de margem para evitar cortes por precisão
    final maxDist = math.max(math.max(d1, d2), math.max(d3, d4)) + 1.0;
    // Limite físico aproximado (meia circunferência terrestre)
    return maxDist.clamp(0.5, 20037.0);
  }

  /// Inicializa dados de localização do usuário no Firestore
  /// 
  /// Útil para garantir que os campos necessários existem
  Future<void> initializeUserLocation({
    required double latitude,
    required double longitude,
    double? radiusKm,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      await FirebaseFirestore.instance.collection('Users').doc(userId).set({
        'latitude': latitude,
        'longitude': longitude,
        'radiusKm': radiusKm ?? 25.0,
        'radiusUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('✅ LocationQueryService: Dados de localização inicializados');
      
      // Invalidar cache para forçar reload
      _invalidateLocationCache();
    } catch (e) {
      debugPrint('❌ LocationQueryService: Erro ao inicializar localização: $e');
    }
  }

  // --- FILTROS EM MEMÓRIA (Baseados nos dados do usuário) ---











  /// Invalida cache de localização
  void _invalidateLocationCache() {
    _userLocationCache = null;
    debugPrint('🗑️ LocationQueryService: Cache de localização invalidado');
  }

  /// Invalida cache de usuários
  void _invalidateUsersCache() {
    _usersCache = null;
    debugPrint('🗑️ LocationQueryService: Cache de usuários invalidado');
  }

  /// Invalida todos os caches
  void _invalidateAllCaches() {
    _invalidateLocationCache();
    _invalidateUsersCache();
  }

  /// Força reload manual
  void forceReload() {
    _invalidateAllCaches();
    _loadAndEmitUsers();
  }

  /// Dispose
  void dispose() {
    _reloadDebounceTimer?.cancel();
    _usersStreamController.close();
  }
}

/// Cache de localização do usuário
class UserLocationCache {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  UserLocationCache({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  /// Verifica se o cache está expirado
  bool get isExpired {
    return DateTime.now().difference(timestamp) >
        LocationQueryService.cacheTTL;
  }
}

/// Cache de usuários próximos
class UsersCache {
  final List<UserWithDistance> users;
  final double radiusKm;
  final DateTime timestamp;

  UsersCache({
    required this.users,
    required this.radiusKm,
    required this.timestamp,
  });

  /// Verifica se o cache está expirado
  bool get isExpired {
    return DateTime.now().difference(timestamp) >
        LocationQueryService.cacheTTL;
  }
}

/// Opções de filtro para usuários
class UserFilterOptions {
  final String? gender;
  final String? sexualOrientation;
  final int? minAge;
  final int? maxAge;
  final bool? isVerified;
  final List<String>? interests;
  final double? radiusKm;

  UserFilterOptions({
    this.gender,
    this.sexualOrientation,
    this.minAge,
    this.maxAge,
    this.isVerified,
    this.interests,
    this.radiusKm,
  });
}

class _MissingLocationException implements Exception {
  _MissingLocationException(this.userId);

  final String userId;

  @override
  String toString() {
    return 'Campos latitude/longitude ausentes no documento Users/$userId';
  }
}
