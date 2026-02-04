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
  static const Duration persistentCacheTTL = Duration(hours: 24);
  /// Refresh em background quando o cache persistente estiver "velho".
  static const Duration persistentSoftRefreshAge = Duration(hours: 6);
  static const Duration debounceTime = Duration(milliseconds: 300);
  static const Duration softRefreshCooldown = Duration(minutes: 10);
  static const Duration softRefreshMinIdle = Duration(seconds: 4);
  static const double _expandMarginDefault = 0.30;
  static const double _expandMarginHighZoom = 0.18;

  /// Número máximo de tiles em memória (LRU)
  static const int maxCachedTiles = 24;

  Timer? _debounceTimer;
  MapBounds? _pendingBounds;

  final LinkedHashMap<String, _PeopleCacheEntry> _cache = LinkedHashMap();
  final Map<String, Future<void>> _inFlightRequests = {};
  final Map<String, DateTime> _softRefreshByKey = {};
  double? _currentZoom;
  DateTime? _lastQueryAt;
  DateTime? _lastCameraIdleAt;
  MapBounds? _coverageBounds;
  String? _coverageFiltersSignature;
  String? _coverageZoomBucket;
  MapBounds? _lastQueryBounds;
  double? _lastQueryZoom;

  int _callsTotal = 0;
  int _callsIdle = 0;
  int _callsRefresh = 0;
  int _callsPreload = 0;
  int _callsStale = 0;
  int _cacheHitMemory = 0;
  int _cacheHitHive = 0;
  int _cacheMiss = 0;
  int _inFlightJoined = 0;

  final bool _sampleSession = math.Random().nextInt(100) == 0;
  final List<Map<String, Object?>> _sampleKeys = <Map<String, Object?>>[];

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
      _coverageBounds = null;
      _coverageFiltersSignature = null;
      _coverageZoomBucket = null;
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
    _lastCameraIdleAt = DateTime.now();

    _pendingBounds = _expandBounds(bounds, _expandMarginForZoom(zoom));

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceTime, () {
      final b = _pendingBounds;
      if (b != null) {
        _pendingBounds = null;
        unawaited(_executeQuery(b, throttleMs: 2000, trigger: 'idle'));
      }
    });
  }

  Future<void> forceRefresh(MapBounds bounds, {double? zoom}) async {
    debugPrint('🔄 [PeopleMapDiscovery] forceRefresh chamado');
    currentBounds.value = bounds;
    _currentZoom = zoom;
    _coverageBounds = null;
    _coverageFiltersSignature = null;
    _coverageZoomBucket = null;
    _debounceTimer?.cancel();
    if (zoom != null && bounds != null) {
      final key = _buildCacheKey(bounds, _buildFiltersSignature(_locationQueryService.currentFilters), zoom);
      _cache.remove(key);
    }
    await _executeQuery(bounds, throttleMs: 0, trigger: 'refresh');
  }

  /// Faz preload (best-effort) de pessoas/avatares para um bounds, sem
  /// publicar resultados em `nearbyPeople/nearbyPeopleCount`.
  ///
  /// Útil para warmup: aquece cache de imagens sem causar “flash” de dados
  /// de um raio aproximado antes do viewport real do mapa estar disponível.
  Future<void> preloadForBounds(MapBounds bounds) async {
    final filtersSignature = _buildFiltersSignature(_locationQueryService.currentFilters);
    final zoomBucket = _zoomBucket(_currentZoom);
    final coverage = _coverageBounds;
    if (coverage != null &&
        _coverageFiltersSignature == filtersSignature &&
        _coverageZoomBucket == zoomBucket &&
        _isBoundsContained(bounds, coverage)) {
      return;
    }

    final cacheKey = _buildCacheKey(bounds, filtersSignature, _currentZoom);
    if (_inFlightRequests.containsKey(cacheKey)) {
      return;
    }

    await _executeQuery(
      bounds,
      publishToNotifiers: false,
      reportLoading: false,
      throttleMs: 0,
      trigger: 'preload',
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
    int throttleMs = 0,
    String trigger = 'unknown',
  }) async {
    debugPrint('🔍 [PeopleMapDiscovery] _executeQuery iniciado...');
    if (reportLoading) {
      _setNotifierValue(isLoading, true);
      _setNotifierValue(lastError, null);
    }
    final activeFilters = _locationQueryService.currentFilters;
    final filtersSignature = _buildFiltersSignature(activeFilters);

    final cacheKey = _buildCacheKey(bounds, filtersSignature, _currentZoom);
    final inFlight = _inFlightRequests[cacheKey];
    if (inFlight != null) {
      _inFlightJoined++;
      await inFlight;
      return;
    }

    bool shouldSoftRefresh(DateTime fetchedAt) {
      if (!publishToNotifiers) return false;
      if (!isViewportActive.value) return false;
      if (_inFlightRequests.containsKey(cacheKey)) return false;

      final lastIdleAt = _lastCameraIdleAt;
      if (lastIdleAt != null) {
        final idleFor = DateTime.now().difference(lastIdleAt);
        if (idleFor < softRefreshMinIdle) return false;
      }

      final lastRefreshAt = _softRefreshByKey[cacheKey];
      if (lastRefreshAt != null) {
        final sinceLast = DateTime.now().difference(lastRefreshAt);
        if (sinceLast < softRefreshCooldown) return false;
      }

      final age = DateTime.now().difference(fetchedAt);
      return age >= persistentSoftRefreshAge;
    }

    final request = () async {
      if (!bypassCache) {
        final cached = _getCacheEntry(cacheKey);
        if (cached != null) {
          _cacheHitMemory++;
          debugPrint('📦 [PeopleMapDiscovery] Usando cache: ${cached.people.length} pessoas');
          if (publishToNotifiers) {
            _setNotifierValue(nearbyPeople, cached.people);
            _setNotifierValue(nearbyPeopleCount, cached.count);
          }
          if (reportLoading) {
            _setNotifierValue(isLoading, false);
          }
          _trackSample(cacheKey, trigger, cached.fetchedAt, bounds, _currentZoom);
          return;
        }

        final persistentEntry = _getPersistentCacheEntry(cacheKey);
        if (persistentEntry != null) {
          _cacheHitHive++;
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

          _trackSample(cacheKey, trigger, persistentEntry.fetchedAt, bounds, _currentZoom);

          if (shouldSoftRefresh(persistentEntry.fetchedAt)) {
            _softRefreshByKey[cacheKey] = DateTime.now();
            unawaited(_executeQuery(
              bounds,
              publishToNotifiers: true,
              reportLoading: false,
              bypassCache: true,
              throttleMs: 0,
              trigger: 'stale',
            ));
          }
          return;
        }
      }

      _cacheMiss++;

      final now = DateTime.now();
      if (throttleMs > 0 && _lastQueryAt != null) {
        final elapsed = now.difference(_lastQueryAt!);
        if (elapsed.inMilliseconds < throttleMs) {
          if (reportLoading) {
            _setNotifierValue(isLoading, false);
          }
          return;
        }
      }

      _lastQueryAt = now;
      _callsTotal++;
      if (trigger == 'idle') _callsIdle++;
      if (trigger == 'refresh') _callsRefresh++;
      if (trigger == 'preload') _callsPreload++;
      if (trigger == 'stale') _callsStale++;

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
        
        // Limita o bounding box para respeitar o limite do servidor (MAX_DELTA_DEG = 0.6)
        // que corresponde a ~66km de lado. Áreas maiores serão cortadas a partir do centro.
        final clampedBounds = _clampBoundsForServer(bounds);
        
        final radiusKm = (activeFilters.radiusKm != null)
            ? (activeFilters.radiusKm!).clamp(1.0, 20000.0)
            : _radiusKmToCoverBoundsFromUser(
                bounds: clampedBounds,
                userLat: userLocation.latitude,
                userLng: userLocation.longitude,
              );

        debugPrint('🔍 [PeopleMapDiscovery] Chamando Cloud Function...');
        debugPrint('   📍 User: (${userLocation.latitude}, ${userLocation.longitude})');
        debugPrint('   📏 Radius: ${radiusKm.toStringAsFixed(1)}km');
        debugPrint('   📐 Bounds: ${clampedBounds.minLat.toStringAsFixed(4)},${clampedBounds.maxLat.toStringAsFixed(4)},${clampedBounds.minLng.toStringAsFixed(4)},${clampedBounds.maxLng.toStringAsFixed(4)}');

        // Paralelismo: Busca dados da nuvem e do usuário local ao mesmo tempo
        final results = await Future.wait([
          _cloudService.getPeopleNearby(
            userLatitude: userLocation.latitude,
            userLongitude: userLocation.longitude,
            radiusKm: radiusKm,
            boundingBox: {
              'minLat': clampedBounds.minLat,
              'maxLat': clampedBounds.maxLat,
              'minLng': clampedBounds.minLng,
              'maxLng': clampedBounds.maxLng,
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
        _trackSample(cacheKey, trigger, DateTime.now(), bounds, _currentZoom);
      } catch (e, stack) {
        debugPrint('⚠️ [PeopleMapDiscovery] Falha ao buscar pessoas em bounds: $e');
        debugPrint('   Stack: $stack');
        // Importante: manter último count/people na UI em caso de erro de rede.
        // Não zera a UI para evitar instabilidade visual.
        if (reportLoading) {
          _setNotifierValue(lastError, e);
          _setNotifierValue(isLoading, false);
        }
      }
    };

    final requestFuture = request();
    _inFlightRequests[cacheKey] = requestFuture;
    try {
      await requestFuture;
      _coverageBounds = bounds;
      _coverageFiltersSignature = filtersSignature;
      _coverageZoomBucket = _zoomBucket(_currentZoom);
    } finally {
      if (_inFlightRequests[cacheKey] == requestFuture) {
        _inFlightRequests.remove(cacheKey);
      }
    }
  }

  void _trackSample(
    String cacheKey,
    String trigger,
    DateTime fetchedAt,
    MapBounds bounds,
    double? zoom,
  ) {
    if (!_sampleSession) return;

    final lastBounds = _lastQueryBounds;
    final lastZoom = _lastQueryZoom;

    double? movementKm;
    double? zoomDelta;
    if (lastBounds != null) {
      final lastCenterLat = (lastBounds.minLat + lastBounds.maxLat) / 2.0;
      final lastCenterLng = (lastBounds.minLng + lastBounds.maxLng) / 2.0;
      final centerLat = (bounds.minLat + bounds.maxLat) / 2.0;
      final centerLng = (bounds.minLng + bounds.maxLng) / 2.0;
      movementKm = _haversineKm(
        lat1: lastCenterLat,
        lng1: lastCenterLng,
        lat2: centerLat,
        lng2: centerLng,
      );
    }

    if (lastZoom != null && zoom != null) {
      zoomDelta = (zoom - lastZoom).abs();
    }

    final ageSeconds = DateTime.now().difference(fetchedAt).inSeconds;
    _sampleKeys.add({
      'key': cacheKey,
      'trigger': trigger,
      'age_s': ageSeconds,
      'move_km': movementKm,
      'zoom_d': zoomDelta,
    });

    if (_sampleKeys.length > 10) {
      _sampleKeys.removeAt(0);
    }

    if (_sampleKeys.length == 10) {
      debugPrint('🧪 [PeopleMapDiscovery] sample_keys=${_sampleKeys.toList()}');
    }

    _lastQueryBounds = bounds;
    _lastQueryZoom = zoom;
  }

  bool _isBoundsContained(MapBounds inner, MapBounds outer) {
    return inner.minLat >= outer.minLat &&
        inner.maxLat <= outer.maxLat &&
        inner.minLng >= outer.minLng &&
        inner.maxLng <= outer.maxLng;
  }

  /// Limite máximo do servidor para delta de latitude/longitude (~66km).
  /// Deve estar alinhado com MAX_DELTA_DEG em get_people.ts.
  static const double _maxServerDeltaDeg = 0.58; // Margem de segurança (server = 0.6)

  /// Limita o bounding box para respeitar o limite do servidor.
  /// 
  /// Se o bounds original for maior que o permitido, ele será reduzido
  /// mantendo o centro, evitando erro "Área de busca muito grande".
  MapBounds _clampBoundsForServer(MapBounds bounds) {
    final deltaLat = (bounds.maxLat - bounds.minLat).abs();
    final deltaLng = (bounds.maxLng - bounds.minLng).abs();

    // Se ambos estão dentro do limite, retorna o original
    if (deltaLat <= _maxServerDeltaDeg && deltaLng <= _maxServerDeltaDeg) {
      return bounds;
    }

    // Calcula o centro e reduz o bounds para respeitar o limite
    final centerLat = (bounds.minLat + bounds.maxLat) / 2.0;
    final centerLng = (bounds.minLng + bounds.maxLng) / 2.0;

    final clampedHalfLat = math.min(deltaLat / 2.0, _maxServerDeltaDeg / 2.0);
    final clampedHalfLng = math.min(deltaLng / 2.0, _maxServerDeltaDeg / 2.0);

    debugPrint('⚠️ [PeopleMapDiscovery] Bounds muito grande, limitando:');
    debugPrint('   Original: lat=$deltaLat, lng=$deltaLng');
    debugPrint('   Limitado: lat=${clampedHalfLat * 2}, lng=${clampedHalfLng * 2}');

    return MapBounds(
      minLat: (centerLat - clampedHalfLat).clamp(-90.0, 90.0),
      maxLat: (centerLat + clampedHalfLat).clamp(-90.0, 90.0),
      minLng: (centerLng - clampedHalfLng).clamp(-180.0, 180.0),
      maxLng: (centerLng + clampedHalfLng).clamp(-180.0, 180.0),
    );
  }

  MapBounds _expandBounds(MapBounds bounds, double marginFactor) {
    final centerLat = (bounds.minLat + bounds.maxLat) / 2.0;
    final centerLng = (bounds.minLng + bounds.maxLng) / 2.0;
    final latSpan = (bounds.maxLat - bounds.minLat).abs();
    final lngSpan = (bounds.maxLng - bounds.minLng).abs();

    final scale = 1.0 + (marginFactor * 2.0);
    final halfLat = (latSpan * scale) / 2.0;
    final halfLng = (lngSpan * scale) / 2.0;

    double clampLat(double v) => v.clamp(-90.0, 90.0);
    double clampLng(double v) => v.clamp(-180.0, 180.0);

    return MapBounds(
      minLat: clampLat(centerLat - halfLat),
      maxLat: clampLat(centerLat + halfLat),
      minLng: clampLng(centerLng - halfLng),
      maxLng: clampLng(centerLng + halfLng),
    );
  }

  double _expandMarginForZoom(double? zoom) {
    return _zoomBucket(zoom) == 'z3'
        ? _expandMarginHighZoom
        : _expandMarginDefault;
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
