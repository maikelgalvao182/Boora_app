import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:partiu/core/models/user.dart' as app_user;
import 'package:partiu/core/services/location_service.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/core/services/cache/hive_initializer.dart';
import 'package:partiu/core/utils/interests_helper.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:partiu/services/location/location_query_service.dart';
import 'package:partiu/services/location/people_cloud_service.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/core/services/analytics_service.dart';

/// Serviço exclusivo para descoberta de pessoas por bounding box do mapa.
///
/// Implementa padrão similar ao MapDiscoveryService (eventos):
/// - `nearbyPeople`: lista reativa de pessoas no bounds atual
/// - `nearbyPeopleCount`: contador total de candidatos (antes do limit)
/// - Debounce + cache TTL para evitar spam durante pan/zoom
class PeopleMapDiscoveryService {
  static final PeopleMapDiscoveryService _instance = PeopleMapDiscoveryService._internal();
  factory PeopleMapDiscoveryService() => _instance;

  PeopleMapDiscoveryService._internal() {
    unawaited(_initializePersistentCache());
  }

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

  /// TTL do cache por tile. 3min reduz refetch em pan/zoom.
  static const Duration cacheTTL = Duration(seconds: 180);
  /// TTL do cache persistente (Hive) por tile.
  static const Duration persistentCacheTTL = Duration(hours: 6);
  /// Refresh em background quando o cache persistente estiver "velho".
  static const Duration persistentSoftRefreshAge = Duration(minutes: 15);
  static const Duration debounceTime = Duration(milliseconds: 300);

  /// Número máximo de tiles em memória (LRU)
  static const int maxCachedTiles = 12;

  Timer? _debounceTimer;
  MapBounds? _pendingBounds;

  final LinkedHashMap<String, _PeopleCacheEntry> _cache = LinkedHashMap();
  double? _currentZoom;

  // Cache persistente (Hive)
  final HiveCacheService<Map<String, dynamic>> _persistentCache =
      HiveCacheService<Map<String, dynamic>>('people_map_tiles');
  bool _persistentCacheReady = false;

  String _buildFiltersSignature(UserFilterOptions filters) {
    final interests = (filters.interests ?? const <String>[]).toList()..sort();
    return '${filters.gender ?? ''}|${filters.minAge ?? ''}|${filters.maxAge ?? ''}|${filters.isVerified ?? ''}|${filters.sexualOrientation ?? ''}|${filters.radiusKm ?? ''}|${interests.join(',')}';
  }

  /// Atualiza o valor de um ValueNotifier de forma segura, evitando
  /// "setState() called during build" ao adiar a notificação para
  /// o próximo frame caso esteja durante build.
  void _setNotifierValue<T>(ValueNotifier<T> notifier, T value) {
    if (notifier.value == value) {
      return;
    }
    
    // Verifica se estamos durante a fase de build do frame
    final phase = SchedulerBinding.instance.schedulerPhase;
    final isBuildPhase = phase == SchedulerPhase.persistentCallbacks;
    
    if (isBuildPhase) {
      // Adia a atualização para depois do frame atual
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (notifier.value != value) {
          notifier.value = value;
        }
      });
    } else {
      notifier.value = value;
    }
  }

  String _zoomBucket(double? zoom) {
    if (zoom == null || !zoom.isFinite) return 'unknown';
    if (zoom <= 11.0) return 'z0';
    if (zoom <= 13.0) return 'z1';
    if (zoom <= 15.0) return 'z2';
    return 'z3';
  }

  String _buildCacheKey(MapBounds bounds, String filtersSignature, double? zoom) {
    final quadkey = bounds.toQuadkey();
    return '$quadkey|$filtersSignature|${_zoomBucket(zoom)}';
  }

  _PeopleCacheEntry? _getCacheEntry(String cacheKey) {
    final entry = _cache[cacheKey];
    if (entry == null) return null;

    final elapsed = DateTime.now().difference(entry.fetchedAt);
    if (elapsed >= cacheTTL) {
      _cache.remove(cacheKey);
      return null;
    }

    // Touch LRU
    _cache.remove(cacheKey);
    _cache[cacheKey] = entry;
    return entry;
  }

  void _putCacheEntry(String cacheKey, _PeopleCacheEntry entry) {
    if (_cache.containsKey(cacheKey)) {
      _cache.remove(cacheKey);
    }
    _cache[cacheKey] = entry;

    while (_cache.length > maxCachedTiles) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<void> _initializePersistentCache() async {
    try {
      await HiveInitializer.initialize();
      await _persistentCache.initialize();
      _persistentCacheReady = true;
    } catch (e) {
      debugPrint('📦 [PeopleMapDiscovery] Hive init error: $e');
      _persistentCacheReady = false;
    }
  }

  ({List<app_user.User> people, int count, DateTime fetchedAt})?
      _getPersistentCacheEntry(String cacheKey) {
    if (!_persistentCacheReady) return null;
    final payload = _persistentCache.get(cacheKey);
    if (payload == null) return null;

    final rawList = payload['people'];
    final count = payload['count'];
    final fetchedAtMs = payload['fetchedAtMs'];

    if (rawList is! List || count is! int || fetchedAtMs is! int) {
      return null;
    }

    final people = <app_user.User>[];
    for (final item in rawList) {
      if (item is Map) {
        try {
          final data = Map<String, dynamic>.from(item);
          people.add(app_user.User.fromDocument(data));
        } catch (_) {
          // Ignora entrada inválida
        }
      }
    }

    return (
      people: people,
      count: count,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAtMs),
    );
  }

  Future<void> _putPersistentCacheEntry({
    required String cacheKey,
    required List<Map<String, dynamic>> people,
    required int count,
    required DateTime fetchedAt,
  }) async {
    if (!_persistentCacheReady) return;
    await _persistentCache.put(
      cacheKey,
      {
        'people': people,
        'count': count,
        'fetchedAtMs': fetchedAt.millisecondsSinceEpoch,
      },
      ttl: persistentCacheTTL,
    );
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

  Future<void> loadPeopleCountInBounds(MapBounds bounds, {double? zoom}) async {
    debugPrint('📍 [PeopleMapDiscovery] loadPeopleCountInBounds chamado');
    debugPrint('   📐 Bounds: minLat=${bounds.minLat.toStringAsFixed(4)}, maxLat=${bounds.maxLat.toStringAsFixed(4)}');
    
    currentBounds.value = bounds;
    _currentZoom = zoom;
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

  Future<void> forceRefresh(MapBounds bounds, {double? zoom}) async {
    debugPrint('🔄 [PeopleMapDiscovery] forceRefresh chamado');
    currentBounds.value = bounds;
    _currentZoom = zoom;
    _debounceTimer?.cancel();
    if (zoom != null && bounds != null) {
      final key = _buildCacheKey(bounds, _buildFiltersSignature(_locationQueryService.currentFilters), zoom);
      _cache.remove(key);
    }
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
    await forceRefresh(bounds, zoom: _currentZoom);
  }

  /// Refresh apenas se o último fetch estiver stale.
  /// Útil para evitar refetch ao voltar na tela.
  Future<void> refreshCurrentBoundsIfStale({Duration ttl = const Duration(minutes: 10)}) async {
    final bounds = currentBounds.value;
    if (bounds == null) {
      return;
    }
    final zoom = _currentZoom;
    final cacheKey = _buildCacheKey(bounds, _buildFiltersSignature(_locationQueryService.currentFilters), zoom);
    final entry = _getCacheEntry(cacheKey);
    if (entry != null) {
      final elapsed = DateTime.now().difference(entry.fetchedAt);
      if (elapsed < ttl) {
        debugPrint('🧊 [PeopleMapDiscovery] Refresh ignorado (TTL não expirou: ${elapsed.inSeconds}s)');
        return;
      }
    }

    debugPrint('🔄 [PeopleMapDiscovery] TTL expirou — refetch bounds atual');
    await forceRefresh(bounds, zoom: zoom);
  }

  Future<void> _executeQuery(
    MapBounds bounds, {
    bool publishToNotifiers = true,
    bool reportLoading = true,
    bool bypassCache = false,
  }) async {
    debugPrint('🔍 [PeopleMapDiscovery] _executeQuery iniciado...');
    if (reportLoading) {
      _setNotifierValue(isLoading, true);
      _setNotifierValue(lastError, null);
    }
    final activeFilters = _locationQueryService.currentFilters;
    final filtersSignature = _buildFiltersSignature(activeFilters);

    final cacheKey = _buildCacheKey(bounds, filtersSignature, _currentZoom);
    if (!bypassCache) {
      final cached = _getCacheEntry(cacheKey);
      if (cached != null) {
        debugPrint('📦 [PeopleMapDiscovery] Usando cache: ${cached.people.length} pessoas');
        if (publishToNotifiers) {
          _setNotifierValue(nearbyPeople, cached.people);
          _setNotifierValue(nearbyPeopleCount, cached.count);
        }
        if (reportLoading) {
          _setNotifierValue(isLoading, false);
        }
        return;
      }

      final persistentEntry = _getPersistentCacheEntry(cacheKey);
      if (persistentEntry != null) {
        debugPrint('📦 [PeopleMapDiscovery] Hive cache HIT: ${persistentEntry.people.length} pessoas');
        if (publishToNotifiers) {
          _setNotifierValue(nearbyPeople, persistentEntry.people);
          _setNotifierValue(nearbyPeopleCount, persistentEntry.count);
        }
        if (reportLoading) {
          _setNotifierValue(isLoading, false);
        }

        _putCacheEntry(
          cacheKey,
          _PeopleCacheEntry(
            people: persistentEntry.people,
            count: persistentEntry.count,
            fetchedAt: persistentEntry.fetchedAt,
          ),
        );

        final age = DateTime.now().difference(persistentEntry.fetchedAt);
        if (age >= persistentSoftRefreshAge) {
          unawaited(_executeQuery(
            bounds,
            publishToNotifiers: true,
            reportLoading: false,
            bypassCache: true,
          ));
        }
        return;
      }
    }

    try {
      // Obter localização atual do usuário para cálculo de distância
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        debugPrint('⚠️ [PeopleMapDiscovery] Usuário não autenticado');
        _setNotifierValue(isLoading, false);
        return;
      }

      // Otimização: Tenta usar location em memória primeiro para resposta rápida
      var userLocation = _locationService.lastKnownPosition;

      if (userLocation == null) {
        // Se não houver, busca com timeout curto (2s) para evitar "spinner infinito"
        // se o GPS estiver demorando. O fallback do LocationService entrara em ação.
        userLocation = await _locationService.getCurrentLocation(
            timeout: const Duration(seconds: 2));
      }

      if (userLocation == null) {
        debugPrint('⚠️ [PeopleMapDiscovery] Localização do usuário não disponível');
        if (reportLoading) {
          _setNotifierValue(isLoading, false);
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

      // Paralelismo: Busca dados da nuvem e do usuário local ao mesmo tempo
      final results = await Future.wait([
        _cloudService.getPeopleNearby(
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
        ),
        _userRepository.getCurrentUserData(),
      ]);

      final result = results[0] as PeopleCloudResult;
      final myUserData = results[1] as Map<String, dynamic>?;

      debugPrint('☁️ [PeopleMapDiscovery] Cloud Function retornou ${result.users.length} usuários');

        // Buscar interesses do usuário atual (cacheado no UserRepository)
        // para calcular commonInterests (matchs) nos cards.
        final myInterests = (myUserData?['interests'] as List?)
            ?.whereType<String>()
            .toList() ??
          const <String>[];

      final currentUserId = currentUser.uid;
      var selfIncludedInPage = false;

      // Converter UserWithDistance para User
      final people = <app_user.User>[];
      final serializedPeople = <Map<String, dynamic>>[];
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
          serializedPeople.add(Map<String, dynamic>.from(userData));
        } catch (e) {
          debugPrint('   ❌ Erro ao converter usuário: $e');
        }
      }

      final adjustedTotalCandidates = selfIncludedInPage
          ? (result.totalCandidates - 1).clamp(0, 1 << 30)
          : result.totalCandidates;

      _putCacheEntry(
        cacheKey,
        _PeopleCacheEntry(
          people: people,
          count: adjustedTotalCandidates,
          fetchedAt: DateTime.now(),
        ),
      );

      await _putPersistentCacheEntry(
        cacheKey: cacheKey,
        people: serializedPeople,
        count: adjustedTotalCandidates,
        fetchedAt: DateTime.now(),
      );

      debugPrint('📋 [PeopleMapDiscovery] Atualizando nearbyPeople com ${people.length} pessoas');

      // 🚀 Prioridade: Atualizar UI primeiro!
      // Libera o indicador de "digitando..." imediatamente
      if (publishToNotifiers) {
        _setNotifierValue(nearbyPeople, people);
        _setNotifierValue(nearbyPeopleCount, adjustedTotalCandidates);
      }

      if (reportLoading) {
        _setNotifierValue(isLoading, false);
      }

      AnalyticsService.instance.logEvent('find_people_query', parameters: {
        'users_returned': people.length,
        'total_candidates': adjustedTotalCandidates,
      });
      
      // ✅ Tarefas de background (Preload de avatares)
      // Executa APÓS liberar a UI para não travar a exibição da contagem
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

      debugPrint('✅ [PeopleMapDiscovery] ${people.length} pessoas encontradas (total: $adjustedTotalCandidates)');
    } catch (e, stack) {
      debugPrint('⚠️ [PeopleMapDiscovery] Falha ao buscar pessoas em bounds: $e');
      debugPrint('   Stack: $stack');
      if (reportLoading) {
        _setNotifierValue(lastError, e);
        _setNotifierValue(isLoading, false);
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
    _cache.clear();
    if (_persistentCacheReady) {
      unawaited(_persistentCache.clear());
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}

class _PeopleCacheEntry {
  final List<app_user.User> people;
  final int count;
  final DateTime fetchedAt;

  const _PeopleCacheEntry({
    required this.people,
    required this.count,
    required this.fetchedAt,
  });
}
