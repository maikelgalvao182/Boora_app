import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/subscription/services/vip_access_service.dart';
import 'package:partiu/services/location/advanced_filters_controller.dart';
import 'package:partiu/services/location/geo_utils.dart';
import 'package:partiu/services/location/distance_isolate.dart';
import 'package:partiu/services/location/location_stream_controller.dart';

/// Serviço principal para queries de localização com filtro de raio
/// 
/// ATENÇÃO: Este serviço foi REFATORADO para buscar USUÁRIOS (pessoas) ao invés de eventos.
/// 
/// Responsabilidades:
/// - Carregar USUÁRIOS dentro do raio do usuário atual
/// - Cache com TTL (30 segundos)
/// - Bounding box para queries otimizadas
/// - Isolate para cálculo de distâncias sem jank
/// - Stream de atualizações automáticas
/// - Filtros sociais (gênero, idade, verificado, interesses)
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
  /// Uso: Quando precisa de uma consulta pontual de pessoas próximas
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

      // 5. Query Firestore na coleção Users (primeira filtragem rápida - Bounding Box)
      final candidateUsers = await _filterUsersByBoundingBox(boundingBox, currentUserId);
      debugPrint('📊 LocationQueryService: ${candidateUsers.length} usuários ANTES dos filtros avançados');

      // 6. Filtros em memória (Gender, Age, Verified, Interests)
      debugPrint('🔍 Filtros ativos: gender=${activeFilters.gender}, age=${activeFilters.minAge}-${activeFilters.maxAge}, verified=${activeFilters.isVerified}, interests=${activeFilters.interests}');
      
      var filteredUsers = _filterByGender(candidateUsers, activeFilters.gender);
      debugPrint('📊 Após filtro de gênero: ${filteredUsers.length} usuários');
      
      filteredUsers = _filterByAge(filteredUsers, activeFilters.minAge, activeFilters.maxAge);
      debugPrint('📊 Após filtro de idade: ${filteredUsers.length} usuários');
      
      filteredUsers = _filterByVerified(filteredUsers, activeFilters.isVerified);
      debugPrint('📊 Após filtro verified: ${filteredUsers.length} usuários');
      
      filteredUsers = _filterByInterests(filteredUsers, activeFilters.interests);
      debugPrint('📊 Após filtro de interesses: ${filteredUsers.length} usuários');

      filteredUsers = _filterBySexualOrientation(filteredUsers, activeFilters.sexualOrientation);
      debugPrint('📊 Após filtro de orientação sexual: ${filteredUsers.length} usuários');

      // 7. Filtrar com isolate (distância exata e cálculos pesados)
      var finalUsers = await _filterUsersByDistanceIsolate(
        users: filteredUsers,
        centerLat: userLocation.latitude,
        centerLng: userLocation.longitude,
        radiusKm: radiusKm,
      );
      debugPrint('📊 Após filtro de distância (Isolate): ${finalUsers.length} usuários');

      // 7.5 Ordenar por VIP Priority e Score (Client-side enforcement of Server Logic)
      // Garante que VIPs apareçam no topo e ordenados por score
      finalUsers.sort((a, b) {
        // 1. VIP Priority (ASC: 1 vem antes de 2)
        final vipA = (a.userData['vip_priority'] as int?) ?? 2;
        final vipB = (b.userData['vip_priority'] as int?) ?? 2;
        final vipComparison = vipA.compareTo(vipB);
        if (vipComparison != 0) return vipComparison;

        // 2. Score / Rating (DESC: maior vem antes)
        final ratingA = (a.userData['overallRating'] as num?)?.toDouble() ?? 0.0;
        final ratingB = (b.userData['overallRating'] as num?)?.toDouble() ?? 0.0;
        final ratingComparison = ratingB.compareTo(ratingA);
        if (ratingComparison != 0) return ratingComparison;
        
        // 3. Distância (ASC: menor vem antes) - Tie breaker
        return a.distanceKm.compareTo(b.distanceKm);
      });

      // 8. Aplicar limite VIP (Segurança Client-Side)
      // O backend deve ter sua própria validação, mas aqui garantimos a UX
      if (!VipAccessService.isVip && finalUsers.length > VipAccessService.freePeopleLimit) {
        debugPrint('🔒 LocationQueryService: Limitando lista para ${VipAccessService.freePeopleLimit} (Usuário Free)');
        finalUsers = finalUsers.take(VipAccessService.freePeopleLimit).toList();
      }

      // 9. Atualizar cache
      _usersCache = UsersCache(
        users: finalUsers,
        radiusKm: radiusKm,
        timestamp: DateTime.now(),
      );

      debugPrint(
          '✅ LocationQueryService: ${finalUsers.length} usuários retornados após todos os filtros');

      return finalUsers;
    } catch (e) {
      debugPrint('❌ LocationQueryService: Erro ao buscar usuários: $e');
      return [];
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

  /// Query Firestore com bounding box (primeira filtragem) na coleção Users
  Future<List<UserLocation>> _filterUsersByBoundingBox(
    Map<String, double> boundingBox,
    String currentUserId,
  ) async {
    debugPrint('📦 LocationQueryService: Bounding Box: $boundingBox');

    final usersQuery = await FirebaseFirestore.instance
        .collection('Users')
        .where('latitude', isGreaterThanOrEqualTo: boundingBox['minLat'])
        .where('latitude', isLessThanOrEqualTo: boundingBox['maxLat'])
        .get();

    debugPrint('📦 LocationQueryService: Firestore returned ${usersQuery.docs.length} users based on latitude');

    final users = <UserLocation>[];

    for (final doc in usersQuery.docs) {
      // Pular o próprio usuário
      if (doc.id == currentUserId) {
        debugPrint('⏭️  LocationQueryService: Pulando próprio usuário ${doc.id}');
        continue;
      }

      final data = doc.data();
      final latitude = data['latitude'] as double?;
      final longitude = data['longitude'] as double?;

      if (latitude == null || longitude == null) {
         debugPrint('⚠️ LocationQueryService: User ${doc.id} missing lat/lng');
         continue;
      }

      // Filtro adicional de longitude (Firestore só permite 1 range query)
      if (longitude >= boundingBox['minLng']! &&
          longitude <= boundingBox['maxLng']!) {
        users.add(
          UserLocation(
            userId: doc.id,
            latitude: latitude,
            longitude: longitude,
            userData: data,
          ),
        );
      } else {
         debugPrint('⚠️ LocationQueryService: User ${doc.id} excluded by longitude. User Lng: $longitude, Range: ${boundingBox['minLng']} - ${boundingBox['maxLng']}');
      }
    }

    debugPrint(
        '📦 LocationQueryService: ${users.length} usuários candidatos do Firestore (Bounding Box)');

    return users;
  }

  // --- FILTROS EM MEMÓRIA (Baseados nos dados do usuário) ---

  List<UserLocation> _filterByGender(List<UserLocation> users, String? gender) {
    if (gender == null || gender == 'all') {
      debugPrint('🔍 _filterByGender: Filtro desabilitado (gender=$gender)');
      return users;
    }
    
    debugPrint('🔍 _filterByGender: Filtrando ${users.length} usuários por gender=$gender');
    
    // Mapeamento: valores do filtro (EN) → valores salvos no Firestore (PT)
    final Map<String, List<String>> genderMap = {
      'male': ['Masculino', 'male', 'M'],
      'female': ['Feminino', 'female', 'F'],
      'non_binary': ['Não-binário', 'non_binary', 'Non-binary', 'NB'],
    };
    
    final acceptedValues = genderMap[gender] ?? [];
    
    final filtered = users.where((u) {
      final userGender = u.userData['gender'] as String?;
      
      if (userGender == null) {
        debugPrint('   ❌ User ${u.userId}: gender=null (campo ausente)');
        return false;
      }
      
      final matches = acceptedValues.contains(userGender);
      
      if (!matches) {
        debugPrint('   ❌ User ${u.userId}: gender=$userGender NÃO match com filtro $gender (aceita: $acceptedValues)');
      } else {
        debugPrint('   ✅ User ${u.userId}: gender=$userGender MATCH!');
      }
      
      return matches;
    }).toList();
    
    debugPrint('🔍 _filterByGender: ${filtered.length} usuários passaram no filtro');
    return filtered;
  }

  List<UserLocation> _filterBySexualOrientation(List<UserLocation> users, String? orientation) {
    if (orientation == null || orientation == 'all') {
      debugPrint('🔍 _filterBySexualOrientation: Filtro desabilitado (orientation=$orientation)');
      return users;
    }
    
    debugPrint('🔍 _filterBySexualOrientation: Filtrando ${users.length} usuários por orientation=$orientation');
    
    final filtered = users.where((u) {
      final userOrientation = u.userData['sexualOrientation'] as String?;
      
      if (userOrientation == null) {
        debugPrint('   ❌ User ${u.userId}: sexualOrientation=null (campo ausente)');
        return false;
      }
      
      // Comparação exata (case sensitive ou insensitive dependendo da necessidade)
      // Assumindo que os valores salvos são os mesmos das constantes
      final matches = userOrientation == orientation;
      
      if (!matches) {
        debugPrint('   ❌ User ${u.userId}: orientation=$userOrientation NÃO match com filtro $orientation');
      } else {
        debugPrint('   ✅ User ${u.userId}: orientation=$userOrientation MATCH!');
      }
      
      return matches;
    }).toList();
    
    debugPrint('🔍 _filterBySexualOrientation: ${filtered.length} usuários passaram no filtro');
    return filtered;
  }

  List<UserLocation> _filterByAge(List<UserLocation> users, int? min, int? max) {
    if (min == null && max == null) {
      debugPrint('🔍 _filterByAge: Filtro desabilitado (min=null, max=null)');
      return users;
    }
    
    debugPrint('🔍 _filterByAge: Filtrando ${users.length} usuários com faixa ${min ?? 0}-${max ?? 100}');
    
    final filtered = users.where((u) {
      // Tentar múltiplas formas de obter idade
      dynamic ageValue = u.userData['age'];
      
      // Se age não existir, tentar calcular de birthYear
      if (ageValue == null) {
        final birthYear = u.userData['birthYear'];
        if (birthYear != null) {
          final currentYear = DateTime.now().year;
          final parsedYear = birthYear is int ? birthYear : int.tryParse(birthYear.toString());
          if (parsedYear != null) {
            ageValue = currentYear - parsedYear;
            debugPrint('🔍 User ${u.userId}: age calculada de birthYear: $ageValue');
          }
        }
      }
      
      if (ageValue == null) {
        debugPrint('❌ User ${u.userId}: age e birthYear são NULL');
        return false;
      }
      
      // Converter para int
      final age = ageValue is int ? ageValue : int.tryParse(ageValue.toString());
      
      if (age == null) {
        debugPrint('❌ User ${u.userId}: Não foi possível converter age para int (valor: $ageValue)');
        return false;
      }
      
      final userMin = min ?? 0;
      final userMax = max ?? 100;
      
      final isInRange = age >= userMin && age <= userMax;
      
      if (!isInRange) {
        debugPrint('❌ User ${u.userId}: age=$age FORA da faixa $userMin-$userMax');
      } else {
        debugPrint('✅ User ${u.userId}: age=$age DENTRO da faixa $userMin-$userMax');
      }
      
      return isInRange;
    }).toList();
    
    debugPrint('🔍 _filterByAge: ${filtered.length} usuários passaram no filtro');
    return filtered;
  }

  List<UserLocation> _filterByVerified(List<UserLocation> users, bool? isVerified) {
    if (isVerified == null || !isVerified) {
      debugPrint('🔍 _filterByVerified: Filtro desabilitado (isVerified=$isVerified)');
      return users;
    }
    
    debugPrint('🔍 _filterByVerified: Filtrando ${users.length} usuários por user_is_verified=true');
    
    final filtered = users.where((u) {
      // Verificar ambos os campos (prioridade para user_is_verified)
      final userIsVerified = u.userData['user_is_verified'] == true || 
                            u.userData['isVerified'] == true;
      
      if (!userIsVerified) {
        debugPrint('   ❌ User ${u.userId}: user_is_verified=false (NÃO verificado)');
      } else {
        debugPrint('   ✅ User ${u.userId}: user_is_verified=true (VERIFICADO)');
      }
      
      return userIsVerified;
    }).toList();
    
    debugPrint('🔍 _filterByVerified: ${filtered.length} usuários passaram no filtro');
    return filtered;
  }

  List<UserLocation> _filterByInterests(List<UserLocation> users, List<String>? interests) {
    if (interests == null || interests.isEmpty) return users;
    
    return users.where((u) {
      final userInterests = List<String>.from(u.userData['interests'] ?? []);
      // Retorna true se tiver pelo menos um interesse em comum
      return userInterests.any((i) => interests.contains(i));
    }).toList();
  }

  /// Filtra usuários com isolate (segunda filtragem precisa)
  Future<List<UserWithDistance>> _filterUsersByDistanceIsolate({
    required List<UserLocation> users,
    required double centerLat,
    required double centerLng,
    required double radiusKm,
  }) async {
    if (users.isEmpty) return [];

    final request = UserDistanceFilterRequest(
      users: users,
      centerLat: centerLat,
      centerLng: centerLng,
      radiusKm: radiusKm,
    );

    // Usar compute() para executar em isolate
    final filteredUsers = await compute(filterUsersByDistance, request);

    debugPrint(
        '🎯 LocationQueryService: ${filteredUsers.length} usuários filtrados por distância (Isolate)');

    return filteredUsers;
  }

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
