import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/models/user.dart' as app_user;
import 'package:partiu/core/services/location_service.dart';
import 'package:partiu/core/utils/interests_helper.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:partiu/services/location/location_query_service.dart';
import 'package:partiu/services/location/people_cloud_service.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/shared/stores/user_store.dart';

/// Serviço exclusivo para descoberta de pessoas por bounding box do mapa.
///
/// Implementa padrão similar ao MapDiscoveryService (eventos):
/// - `nearbyPeople`: lista reativa de pessoas no bounds atual
/// - `nearbyPeopleCount`: contador total de candidatos (antes do limit)
/// - Debounce + cache TTL para evitar spam durante pan/zoom
class PeopleMapDiscoveryService {
  static final PeopleMapDiscoveryService _instance = PeopleMapDiscoveryService._internal();
  factory PeopleMapDiscoveryService() => _instance;

  PeopleMapDiscoveryService._internal();

  final PeopleCloudService _cloudService = PeopleCloudService();
  final LocationService _locationService = LocationService();
  final LocationQueryService _locationQueryService = LocationQueryService();
  final UserRepository _userRepository = UserRepository();

  /// Lista de pessoas próximas (similar a MapDiscoveryService.nearbyEvents)
  final ValueNotifier<List<app_user.User>> nearbyPeople = ValueNotifier<List<app_user.User>>([]);
  
  final ValueNotifier<int> nearbyPeopleCount = ValueNotifier<int>(0);
  final ValueNotifier<MapBounds?> currentBounds = ValueNotifier<MapBounds?>(null);

  /// Indica se o viewport está em um zoom "válido" para descoberta de pessoas.
  ///
  /// Regras:
  /// - true: zoom próximo (bbox faz sentido → podemos buscar/mostrar pessoas)
  /// - false: zoom muito afastado (custo alto + UX ruim → UI deve ficar inativa)
  final ValueNotifier<bool> isViewportActive = ValueNotifier<bool>(false);

  /// Estados para a UI (FindPeopleScreen/PeopleButton)
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<Object?> lastError = ValueNotifier<Object?>(null);

  static const Duration cacheTTL = Duration(seconds: 10);
  static const Duration debounceTime = Duration(milliseconds: 500);

  Timer? _debounceTimer;
  MapBounds? _pendingBounds;

  List<app_user.User> _cachedPeople = [];
  int _cachedCount = 0;
  DateTime _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastQuadkey;
  String? _lastFiltersSignature;

  String _buildFiltersSignature(UserFilterOptions filters) {
    final interests = (filters.interests ?? const <String>[]).toList()..sort();
    return '${filters.gender ?? ''}|${filters.minAge ?? ''}|${filters.maxAge ?? ''}|${filters.isVerified ?? ''}|${filters.sexualOrientation ?? ''}|${filters.radiusKm ?? ''}|${interests.join(',')}';
  }

  bool _shouldUseCache(String quadkey, String filtersSignature) {
    if (_lastQuadkey != quadkey) return false;
    if (_lastFiltersSignature != filtersSignature) return false;
    final elapsed = DateTime.now().difference(_lastFetchTime);
    return elapsed < cacheTTL;
  }

  void setViewportActive(bool active) {
    if (isViewportActive.value == active) return;
    isViewportActive.value = active;

    if (!active) {
      // Limpa para evitar valores stale quando o usuário dá zoom out.
      _debounceTimer?.cancel();
      _pendingBounds = null;
      currentBounds.value = null;
      nearbyPeopleCount.value = 0;
      nearbyPeople.value = const [];
      isLoading.value = false;
      lastError.value = null;
    }
  }

  Future<void> loadPeopleCountInBounds(MapBounds bounds) async {
    debugPrint('📍 [PeopleMapDiscovery] loadPeopleCountInBounds chamado');
    debugPrint('   📐 Bounds: minLat=${bounds.minLat.toStringAsFixed(4)}, maxLat=${bounds.maxLat.toStringAsFixed(4)}');
    
    currentBounds.value = bounds;
    _pendingBounds = bounds;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceTime, () {
      final b = _pendingBounds;
      if (b != null) {
        _pendingBounds = null;
        unawaited(_executeQuery(b));
      }
    });
  }

  Future<void> forceRefresh(MapBounds bounds) async {
    debugPrint('🔄 [PeopleMapDiscovery] forceRefresh chamado');
    currentBounds.value = bounds;
    _debounceTimer?.cancel();
    _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(0);
    await _executeQuery(bounds);
  }

  /// Faz preload (best-effort) de pessoas/avatares para um bounds, sem
  /// publicar resultados em `nearbyPeople/nearbyPeopleCount`.
  ///
  /// Útil para warmup: aquece cache de imagens sem causar “flash” de dados
  /// de um raio aproximado antes do viewport real do mapa estar disponível.
  Future<void> preloadForBounds(MapBounds bounds) async {
    await _executeQuery(
      bounds,
      publishToNotifiers: false,
      reportLoading: false,
    );
  }

  Future<void> refreshCurrentBounds() async {
    debugPrint('🔄 [PeopleMapDiscovery] refreshCurrentBounds chamado');
    final bounds = currentBounds.value;
    if (bounds == null) {
      debugPrint('⚠️ [PeopleMapDiscovery] currentBounds é null - nada a fazer');
      return;
    }
    debugPrint('   📐 Bounds atual: minLat=${bounds.minLat.toStringAsFixed(4)}, maxLat=${bounds.maxLat.toStringAsFixed(4)}');
    await forceRefresh(bounds);
  }

  Future<void> _executeQuery(
    MapBounds bounds, {
    bool publishToNotifiers = true,
    bool reportLoading = true,
  }) async {
    debugPrint('🔍 [PeopleMapDiscovery] _executeQuery iniciado...');
    if (reportLoading) {
      isLoading.value = true;
      lastError.value = null;
    }
    final quadkey = bounds.toQuadkey();

    final activeFilters = _locationQueryService.currentFilters;
    final filtersSignature = _buildFiltersSignature(activeFilters);

    if (_shouldUseCache(quadkey, filtersSignature)) {
      debugPrint('📦 [PeopleMapDiscovery] Usando cache: ${_cachedPeople.length} pessoas');
      if (publishToNotifiers) {
        nearbyPeople.value = _cachedPeople;
        nearbyPeopleCount.value = _cachedCount;
      }
      if (reportLoading) {
        isLoading.value = false;
      }
      return;
    }

    try {
      // Obter localização atual do usuário para cálculo de distância
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        debugPrint('⚠️ [PeopleMapDiscovery] Usuário não autenticado');
        isLoading.value = false;
        return;
      }

      final userLocation = await _locationService.getCurrentLocation();
      if (userLocation == null) {
        debugPrint('⚠️ [PeopleMapDiscovery] Localização do usuário não disponível');
        if (reportLoading) {
          isLoading.value = false;
        }
        return;
      }

      // IMPORTANTE: a lista do mapa deve ser determinada pelo BOUNDING BOX,
      // não por um raio fixo (ex.: 30km). Como o PeopleCloudService ainda
      // filtra por radiusKm ao calcular distâncias, aqui calculamos um raio
      // grande o suficiente para cobrir todo o bounding box a partir do usuário.
      final radiusKm = (activeFilters.radiusKm != null)
          ? (activeFilters.radiusKm!).clamp(1.0, 20000.0)
          : _radiusKmToCoverBoundsFromUser(
              bounds: bounds,
              userLat: userLocation.latitude,
              userLng: userLocation.longitude,
            );

      debugPrint('🔍 [PeopleMapDiscovery] Chamando Cloud Function...');
      debugPrint('   📍 User: (${userLocation.latitude}, ${userLocation.longitude})');
      debugPrint('   📏 Radius: ${radiusKm.toStringAsFixed(1)}km');
      debugPrint('   📐 Bounds: ${bounds.minLat.toStringAsFixed(4)},${bounds.maxLat.toStringAsFixed(4)},${bounds.minLng.toStringAsFixed(4)},${bounds.maxLng.toStringAsFixed(4)}');

      final result = await _cloudService.getPeopleNearby(
        userLatitude: userLocation.latitude,
        userLongitude: userLocation.longitude,
        radiusKm: radiusKm,
        boundingBox: {
          'minLat': bounds.minLat,
          'maxLat': bounds.maxLat,
          'minLng': bounds.minLng,
          'maxLng': bounds.maxLng,
        },
        filters: UserCloudFilters(
          gender: activeFilters.gender,
          minAge: activeFilters.minAge,
          maxAge: activeFilters.maxAge,
          isVerified: activeFilters.isVerified,
          interests: activeFilters.interests,
          sexualOrientation: activeFilters.sexualOrientation,
        ),
      );

      debugPrint('☁️ [PeopleMapDiscovery] Cloud Function retornou ${result.users.length} usuários');

        // Buscar interesses do usuário atual (cacheado no UserRepository)
        // para calcular commonInterests (matchs) nos cards.
        final myUserData = await _userRepository.getCurrentUserData();
        final myInterests = (myUserData?['interests'] as List?)
            ?.whereType<String>()
            .toList() ??
          const <String>[];

      final currentUserId = currentUser.uid;
      var selfIncludedInPage = false;

      // Converter UserWithDistance para User
      final people = <app_user.User>[];
      for (final uwd in result.users) {
        try {
          final userData = Map<String, dynamic>.from(uwd.userData);

          final candidateId = (userData['userId'] ?? userData['uid'] ?? userData['id'])?.toString();
          if (candidateId != null && candidateId == currentUserId) {
            selfIncludedInPage = true;
            continue;
          }

          userData['distance'] = uwd.distanceKm;

          // Enriquecer com interesses em comum (se possível)
          // (não depende de Firestore por usuário, só usa o payload já retornado)
          final userInterests = (userData['interests'] as List?)
                  ?.whereType<String>()
                  .toList() ??
              const <String>[];
          if (myInterests.isNotEmpty && userInterests.isNotEmpty) {
            userData['commonInterests'] = InterestsHelper.getCommonInterestsList(
              userInterests,
              myInterests,
            );
          } else {
            userData['commonInterests'] = const <String>[];
          }

          final user = app_user.User.fromDocument(userData);
          people.add(user);
          debugPrint('   ✅ Convertido: ${user.userFullname} (${uwd.distanceKm.toStringAsFixed(1)}km)');
        } catch (e) {
          debugPrint('   ❌ Erro ao converter usuário: $e');
        }
      }

      // ✅ Pré-carregar avatares no UserStore para o StableAvatar renderizar sem delay.
      // Estratégia viewport-first:
      // - Só tenta aquecer cache quando a lista atual do viewport chega
      // - Limita concorrência global via fila no UserStore
      // - Prioriza usuários mais próximos
      final userStore = UserStore.instance;
      final usersWithPhoto = people.where((u) => u.photoUrl.isNotEmpty).toList()
        ..sort((a, b) {
          final distanceA = a.distance ?? double.infinity;
          final distanceB = b.distance ?? double.infinity;
          return distanceA.compareTo(distanceB);
        });

      const maxViewportPreload = 60;
      final preloadLimit = usersWithPhoto.length > maxViewportPreload
          ? maxViewportPreload
          : usersWithPhoto.length;

      for (final user in usersWithPhoto.take(preloadLimit)) {
        userStore.preloadAvatar(user.userId, user.photoUrl);
      }

      final adjustedTotalCandidates = selfIncludedInPage
          ? (result.totalCandidates - 1).clamp(0, 1 << 30)
          : result.totalCandidates;

      _cachedPeople = people;
      _cachedCount = adjustedTotalCandidates;
      _lastFetchTime = DateTime.now();
      _lastQuadkey = quadkey;
      _lastFiltersSignature = filtersSignature;

      debugPrint('📋 [PeopleMapDiscovery] Atualizando nearbyPeople com ${people.length} pessoas');
      if (publishToNotifiers) {
        nearbyPeople.value = people;
        nearbyPeopleCount.value = adjustedTotalCandidates;
      }

      if (reportLoading) {
        isLoading.value = false;
      }

      debugPrint('✅ [PeopleMapDiscovery] ${people.length} pessoas encontradas (total: $adjustedTotalCandidates)');
    } catch (e, stack) {
      debugPrint('⚠️ [PeopleMapDiscovery] Falha ao buscar pessoas em bounds: $e');
      debugPrint('   Stack: $stack');
      if (reportLoading) {
        lastError.value = e;
        isLoading.value = false;
      }
    }
  }

  /// Calcula um raio (km) grande o suficiente para cobrir o bounding box
  /// a partir da posição do usuário.
  ///
  /// Motivo: o PeopleCloudService calcula distâncias e filtra por radiusKm.
  /// Para que o bounding box seja a fonte de verdade da lista, precisamos
  /// garantir que radiusKm não exclua usuários que estão dentro do bounds.
  double _radiusKmToCoverBoundsFromUser({
    required MapBounds bounds,
    required double userLat,
    required double userLng,
  }) {
    final corners = <({double lat, double lng})>[
      (lat: bounds.minLat, lng: bounds.minLng),
      (lat: bounds.minLat, lng: bounds.maxLng),
      (lat: bounds.maxLat, lng: bounds.minLng),
      (lat: bounds.maxLat, lng: bounds.maxLng),
    ];

    var maxKm = 0.0;
    for (final c in corners) {
      final d = _haversineKm(
        lat1: userLat,
        lng1: userLng,
        lat2: c.lat,
        lng2: c.lng,
      );
      if (d > maxKm) maxKm = d;
    }

    // Pequena folga para garantir cobertura.
    final radiusKm = maxKm + 1.0;

    // Proteção contra valores absurdos (pan/zoom muito distante).
    // 20.000km cobre praticamente qualquer deslocamento na Terra.
    return radiusKm.clamp(1.0, 20000.0);
  }

  double _haversineKm({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final rLat1 = _degToRad(lat1);
    final rLat2 = _degToRad(lat2);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) * math.cos(rLat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);

  void clearCache() {
    _cachedPeople = [];
    _cachedCount = 0;
    _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(0);
    _lastQuadkey = null;
    _lastFiltersSignature = null;
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}
