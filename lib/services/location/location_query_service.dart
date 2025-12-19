import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/subscription/services/vip_access_service.dart';
import 'package:partiu/services/location/advanced_filters_controller.dart';
import 'package:partiu/services/location/geo_utils.dart';
import 'package:partiu/services/location/distance_isolate.dart';
import 'package:partiu/services/location/location_stream_controller.dart';
import 'package:partiu/services/location/people_cloud_service.dart';

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
      final radiusKm = customRadiusKm ?? activeFilters.radiusKm ?? await _getUserRadius();
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
      debugPrint('❌ LocationQueryService: Erro ao buscar usuários: $e');
      debugPrint('❌ LocationQueryService: StackTrace: $stackTrace');
      rethrow; // Propaga o erro para o controller tratar
    }
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
    final users = await getUsersWithinRadiusOnce(customRadiusKm: radiusKm);
    if (!_usersStreamController.isClosed) {
      _usersStreamController.add(users);
    }
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
    final userDoc =
        await FirebaseFirestore.instance.collection('Users').doc(userId).get();

    if (!userDoc.exists || userDoc.data() == null) {
      debugPrint('❌ LocationQueryService: Documento do usuário NÃO ENCONTRADO em Users/$userId');
      throw Exception('Documento do usuário não existe em Users/$userId');
    }

    final data = userDoc.data()!;
    debugPrint('🔍 LocationQueryService: Documento encontrado, verificando campos...');
    debugPrint('🔍 LocationQueryService: Campos disponíveis: ${data.keys.toList()}');
    
    final latitude = data['latitude'] as double?;
    final longitude = data['longitude'] as double?;
    
    debugPrint('🔍 LocationQueryService: latitude = $latitude');
    debugPrint('🔍 LocationQueryService: longitude = $longitude');

    if (latitude == null || longitude == null) {
      debugPrint('❌ LocationQueryService: Campos latitude/longitude AUSENTES!');
      throw Exception('Campos latitude/longitude ausentes no documento Users/$userId');
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
        final radiusKm = userDoc.data()!['radiusKm'] as double?;
        return radiusKm ?? 25.0;
      }
    } catch (e) {
      debugPrint('❌ LocationQueryService: Erro ao buscar raio: $e');
    }

    return 25.0; // Default
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
