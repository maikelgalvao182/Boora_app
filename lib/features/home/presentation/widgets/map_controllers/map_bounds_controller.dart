import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/map_people_controller.dart';

class MapBoundsController {
  final MapViewModel viewModel;
  final MapPeopleController peopleController;
  GoogleMapController? mapController;

  // Buffer do viewport usado para filtrar markers em zoom alto.
  static const double viewportBoundsBufferFactor = 3.0;

  // Prefetch por "zona de gordura"
  static const double _prefetchBoundsBufferFactor = 4.0;
  
  // ========================================
  // ✅ ESTADO ROBUSTO DE PREFETCH
  // ========================================
  /// Flag indicando se um prefetch está em andamento
  bool _prefetchInFlight = false;
  
  /// Timestamp de quando o último prefetch completou com sucesso
  DateTime? _prefetchCompletedAt;
  
  /// Bounds que foi efetivamente carregado no último prefetch bem-sucedido
  LatLngBounds? _prefetchCoverageBounds;
  
  /// TTL para considerar o prefetch como "fresco"
  static const Duration _prefetchFreshTtl = Duration(seconds: 60);

  MapBounds? _lastRequestedQueryBounds;
  DateTime _lastRequestedQueryAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minIntervalBetweenContainedBoundsQueries = Duration(seconds: 2);

  // Controle de zoom bucket para forçar refetch quando modo de render muda
  int? _lastZoomBucket;

  // Lookahead cache durante pan (throttle)
  Timer? _cacheLookaheadThrottle;
  static const Duration _cacheLookaheadThrottleDuration = Duration(milliseconds: 160);
  LatLng? _pendingLookaheadCenter;
  
  // Limiar de UX: acima disso tendemos a filtrar por viewport para reduzir custo.
  static const double clusterZoomThreshold = 11.0;
  
  LatLngBounds? lastExpandedVisibleBounds;

  MapBoundsController({
    required this.viewModel,
    required this.peopleController,
  });

  /// Calcula o bucket de zoom para detectar mudanças significativas.
  /// 
  /// Buckets:
  /// - 0: zoom <= 8 (muito afastado, clusters grandes)
  /// - 1: zoom 8-11 (clusters médios)
  /// - 2: zoom 11-14 (transição cluster → individual)
  /// - 3: zoom > 14 (zoom próximo, markers individuais)
  int _zoomBucket(double zoom) {
    if (zoom <= 8) return 0;
    if (zoom <= 11) return 1;
    if (zoom <= 14) return 2;
    return 3;
  }

  void setController(GoogleMapController? controller) {
    mapController = controller;
  }

  void dispose() {
    _cacheLookaheadThrottle?.cancel();
  }

  // ===== Bounds Helper Methods =====

  bool isLatLngBoundsContained(LatLngBounds inner, LatLngBounds outer) {
    final innerSw = inner.southwest;
    final innerNe = inner.northeast;
    final outerSw = outer.southwest;
    final outerNe = outer.northeast;

    final innerMinLat = innerSw.latitude < innerNe.latitude ? innerSw.latitude : innerNe.latitude;
    final innerMaxLat = innerSw.latitude < innerNe.latitude ? innerNe.latitude : innerSw.latitude;
    final outerMinLat = outerSw.latitude < outerNe.latitude ? outerSw.latitude : outerNe.latitude;
    final outerMaxLat = outerSw.latitude < outerNe.latitude ? outerNe.latitude : outerSw.latitude;

    final latContained = innerMinLat >= outerMinLat && innerMaxLat <= outerMaxLat;

    final outerCrosses = outerSw.longitude > outerNe.longitude;
    final innerCrosses = innerSw.longitude > innerNe.longitude;

    if (innerCrosses && !outerCrosses) return false;

    if (!outerCrosses) {
      final minLng = outerSw.longitude;
      final maxLng = outerNe.longitude;
      final innerMinLng = innerSw.longitude;
      final innerMaxLng = innerNe.longitude;
      return latContained && innerMinLng >= minLng && innerMaxLng <= maxLng;
    }

    final swOk = (innerSw.longitude >= outerSw.longitude) || (innerSw.longitude <= outerNe.longitude);
    final neOk = (innerNe.longitude >= outerSw.longitude) || (innerNe.longitude <= outerNe.longitude);
    return latContained && swOk && neOk;
  }

  bool isBoundsContained(MapBounds inner, MapBounds outer) {
    return inner.minLat >= outer.minLat &&
        inner.maxLat <= outer.maxLat &&
        inner.minLng >= outer.minLng &&
        inner.maxLng <= outer.maxLng;
  }

  LatLngBounds expandBounds(LatLngBounds bounds, double factor) {
    final sw = bounds.southwest;
    final ne = bounds.northeast;

    final centerLat = (sw.latitude + ne.latitude) / 2.0;
    final centerLng = (sw.longitude + ne.longitude) / 2.0;

    final halfLatSpan = (ne.latitude - sw.latitude).abs() * factor / 2.0;
    final halfLngSpan = (ne.longitude - sw.longitude).abs() * factor / 2.0;

    double clampLat(double v) => v.clamp(-90.0, 90.0);
    double clampLng(double v) => v.clamp(-180.0, 180.0);

    return LatLngBounds(
      southwest: LatLng(
        clampLat(centerLat - halfLatSpan),
        clampLng(centerLng - halfLngSpan),
      ),
      northeast: LatLng(
        clampLat(centerLat + halfLatSpan),
        clampLng(centerLng + halfLngSpan),
      ),
    );
  }

  bool boundsContains(LatLngBounds bounds, double lat, double lng) {
    final sw = bounds.southwest;
    final ne = bounds.northeast;

    final minLat = sw.latitude < ne.latitude ? sw.latitude : ne.latitude;
    final maxLat = sw.latitude < ne.latitude ? ne.latitude : sw.latitude;
    final withinLat = lat >= minLat && lat <= maxLat;

    final swLng = sw.longitude;
    final neLng = ne.longitude;
    final withinLng = swLng <= neLng ? (lng >= swLng && lng <= neLng) : (lng >= swLng || lng <= neLng);

    return withinLat && withinLng;
  }

  MapBounds boundsFromCenterWithSpan(LatLng center, LatLngBounds reference) {
    final latSpan = (reference.northeast.latitude - reference.southwest.latitude).abs();
    final lngSpan = (reference.northeast.longitude - reference.southwest.longitude).abs();

    final halfLat = latSpan / 2.0;
    final halfLng = lngSpan / 2.0;

    double clampLat(double v) => v.clamp(-90.0, 90.0);
    double clampLng(double v) => v.clamp(-180.0, 180.0);

    return MapBounds(
      minLat: clampLat(center.latitude - halfLat),
      maxLat: clampLat(center.latitude + halfLat),
      minLng: clampLng(center.longitude - halfLng),
      maxLng: clampLng(center.longitude + halfLng),
    );
  }

  // ===== Logic Methods =====

  /// Executa prefetch de eventos para a região expandida.
  /// 
  /// ✅ ROBUSTO: Marca estado de início/fim para evitar falso positivo no skip.
  /// 
  /// IMPORTANTE: [expandedBounds] já deve vir expandido! Não expande de novo.
  Future<void> prefetchEventsForExpandedBounds(LatLngBounds expandedBounds) async {
    if (mapController == null) return;
    
    // Evita prefetch duplicado
    if (_prefetchInFlight) {
      debugPrint('⏳ [PREFETCH] Já existe prefetch em andamento, ignorando');
      return;
    }

    // ✅ FIX: Não expande de novo - já vem expandido
    final prefetchQuery = MapBounds.fromLatLngBounds(expandedBounds);
    final startedAt = DateTime.now();
    
    _prefetchInFlight = true;
    debugPrint('🚀 [PREFETCH] Iniciando prefetch para bounds expandido...');

    try {
      await viewModel.loadEventsInBounds(prefetchQuery);
      
      // ✅ Sucesso: marca como completado
      _prefetchCoverageBounds = expandedBounds;
      _prefetchCompletedAt = DateTime.now();
      
      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint('✅ [PREFETCH] Concluído em ${elapsed}ms, events=${viewModel.events.length}');
    } catch (e) {
      debugPrint('❌ [PREFETCH] Falhou: $e');
      // Não marca como completado em caso de erro
    } finally {
      _prefetchInFlight = false;
    }
  }
  
  Future<void> prefetchExpandedBounds({double? bufferFactor}) async {
    final controller = mapController;
    if (controller == null) return;

    try {
      final visibleRegion = await controller.getVisibleRegion();
      final factor = bufferFactor ?? _prefetchBoundsBufferFactor;
      final expanded = expandBounds(visibleRegion, factor);
      await prefetchEventsForExpandedBounds(expanded);
    } catch (_) {
      // Best-effort.
    }
  }

  void scheduleCacheLookahead(LatLng center, double currentZoom) {
    if (currentZoom <= clusterZoomThreshold) return;

    _pendingLookaheadCenter = center;
    if (_cacheLookaheadThrottle?.isActive ?? false) return;

    _cacheLookaheadThrottle = Timer(_cacheLookaheadThrottleDuration, () {
      final target = _pendingLookaheadCenter;
      _pendingLookaheadCenter = null;
      if (target == null) return;

      final reference = lastExpandedVisibleBounds;
      if (reference == null) return;

      final lookaheadBounds = boundsFromCenterWithSpan(target, reference);
      // Passa zoom do último bucket conhecido para consistência de cacheKey
      final zoom = _lastZoomBucket != null ? _lastZoomBucket!.toDouble() * 3.0 + 10.0 : null;
      viewModel.softLookaheadForBounds(lookaheadBounds, zoom: zoom);
    });
  }

  Future<void> onCameraIdle(double currentZoom, {required VoidCallback onNewData}) async {
    if (mapController == null) return;

    try {
      String boundsKey(MapBounds bounds) {
        return '${bounds.minLat.toStringAsFixed(3)}_'
            '${bounds.minLng.toStringAsFixed(3)}_'
            '${bounds.maxLat.toStringAsFixed(3)}_'
            '${bounds.maxLng.toStringAsFixed(3)}';
      }

      final visibleRegion = await mapController!.getVisibleRegion();
      viewModel.setVisibleBounds(visibleRegion, zoom: currentZoom);
      final expandedBounds = expandBounds(visibleRegion, viewportBoundsBufferFactor);
      lastExpandedVisibleBounds = expandedBounds;

      final visibleKey = boundsKey(MapBounds.fromLatLngBounds(visibleRegion));
      final expandedKey = boundsKey(MapBounds.fromLatLngBounds(expandedBounds));
      debugPrint(
        '📷 MapBoundsController: cameraIdle(boundsKey=$visibleKey, zoom=${currentZoom.toStringAsFixed(1)}, visible=$visibleKey, expanded=$expandedKey)',
      );

      final pfExpandedBounds = expandBounds(visibleRegion, _prefetchBoundsBufferFactor);
      final queryBounds = MapBounds.fromLatLngBounds(expandedBounds);
      
      debugPrint('📍 MapBoundsController: Câmera parou (zoom: ${currentZoom.toStringAsFixed(1)})');
      
      final now = DateTime.now();

      // ========================================
      // ✅ PASSO 1: Detectar mudança de zoomBucket
      // ========================================
      final currentZoomBucket = _zoomBucket(currentZoom);
      final previousZoomBucket = _lastZoomBucket;
      final zoomBucketChanged = previousZoomBucket != null && previousZoomBucket != currentZoomBucket;
      _lastZoomBucket = currentZoomBucket;

      if (zoomBucketChanged) {
        debugPrint('🔄 MapBoundsController: Zoom bucket mudou ($previousZoomBucket → $currentZoomBucket)');
      }

      // ========================================
      // ✅ PASSO 2: SEMPRE aplicar cache local e renderizar PRIMEIRO
      // Isso garante que "não precisa mexer de novo"
      // ========================================
      final appliedCache = await viewModel.softLookaheadForBounds(queryBounds, zoom: currentZoom);
      debugPrint('📦 [DIAG] appliedCache=$appliedCache, eventsCount=${viewModel.events.length}');
      
      // ✅ SEMPRE chamar onNewData() para re-render com dados locais
      // Mesmo se dentro do prefetch, o zoomBucket pode ter mudado
      onNewData();

      // ========================================
      // ✅ PASSO 3: Decidir se precisa fetch de REDE (não bloqueia render)
      // ========================================
      
      // Verificações de contenção geométrica
      final withinPrevious = _lastRequestedQueryBounds != null &&
          isBoundsContained(queryBounds, _lastRequestedQueryBounds!);
      final tooSoon = now.difference(_lastRequestedQueryAt) < _minIntervalBetweenContainedBoundsQueries;
      final isMapEmpty = viewModel.events.isEmpty;
      
      // ========================================
      // ✅ ESTADO ROBUSTO DE PREFETCH
      // ========================================
      // Verificar se está dentro do bounds que foi EFETIVAMENTE carregado
      final withinPrefetchCoverage = _prefetchCoverageBounds != null &&
          isLatLngBoundsContained(visibleRegion, _prefetchCoverageBounds!);
      
      // Verificar se o prefetch está "fresco" (não expirou TTL)
      final prefetchIsFresh = _prefetchCompletedAt != null &&
          now.difference(_prefetchCompletedAt!) < _prefetchFreshTtl;
      
      // Só pode usar prefetch se: completou E está fresco E cobre a região
      final canSkipBecausePrefetched = withinPrefetchCoverage && prefetchIsFresh && !_prefetchInFlight;
      
      // Gerar chave resumida do prefetch coverage para logs
      String? prefetchCoverageKey;
      if (_prefetchCoverageBounds != null) {
        final b = _prefetchCoverageBounds!;
        prefetchCoverageKey = '${b.southwest.latitude.toStringAsFixed(2)}_${b.northeast.latitude.toStringAsFixed(2)}';
      }
      
      // Log detalhado do estado de prefetch
      debugPrint('📦 [DIAG] withinPrefetchCoverage=$withinPrefetchCoverage '
          'prefetchIsFresh=$prefetchIsFresh '
          'inFlight=$_prefetchInFlight '
          'completedAt=${_prefetchCompletedAt?.toIso8601String() ?? "null"} '
          'coverageKey=$prefetchCoverageKey');

      // ========================================
      // ✅ CONDIÇÃO FINAL DE SKIP
      // ========================================
      // Só pula rede quando:
      // - Prefetch realmente completou E está fresco E cobre a região
      // - Mapa não está vazio
      // - Zoom bucket não mudou
      // - ✅ REGRA DE OURO: appliedCache=true (cache local cobriu os bounds)
      final skipNetworkFetch = canSkipBecausePrefetched && !isMapEmpty && !zoomBucketChanged && appliedCache;
      
      // Determinar razão do skip para log
      String skipReason = 'none';
      if (skipNetworkFetch) {
        skipReason = 'prefetch_valid';
      } else if (!appliedCache) {
        skipReason = 'cache_miss';  // ✅ Cache não cobriu bounds -> TEM que buscar rede
      } else if (_prefetchInFlight) {
        skipReason = 'prefetch_in_flight';
      } else if (!withinPrefetchCoverage) {
        skipReason = 'outside_prefetch_coverage';
      } else if (!prefetchIsFresh) {
        skipReason = 'prefetch_stale';
      } else if (isMapEmpty) {
        skipReason = 'map_empty';
      } else if (zoomBucketChanged) {
        skipReason = 'zoom_bucket_changed';
      }

      if (skipNetworkFetch) {
        debugPrint('📦 [DIAG] skipNetworkFetch: true, reason=$skipReason '
            'fresh=$prefetchIsFresh inFlight=$_prefetchInFlight '
            'completedAt=${_prefetchCompletedAt?.toIso8601String() ?? "null"}');
      } else if (withinPrevious && tooSoon && !isMapEmpty && !zoomBucketChanged) {
        debugPrint('📦 [DIAG] skipNetworkFetch: true, reason=contained_bounds_min_interval');
      } else {
        // ✅ PASSO 4: Fetch de rede em PARALELO (não bloqueia)
        debugPrint('🌐 [DIAG] Disparando fetch de rede (reason=$skipReason)...');
        _lastRequestedQueryBounds = queryBounds;
        _lastRequestedQueryAt = now;
        
        // ✅ FIX: Capturar o bounds expandido para atualizar coverage após fetch
        final fetchExpandedBounds = pfExpandedBounds;

        // Fire-and-forget: não espera o resultado
        unawaited(
          viewModel.loadEventsInBounds(
            queryBounds,
            prefetchNeighbors: currentZoom > clusterZoomThreshold,
            zoom: currentZoom,
          ).then((_) {
            // ✅ FIX: Atualizar coverage quando fetch de rede completar
            _prefetchCoverageBounds = fetchExpandedBounds;
            _prefetchCompletedAt = DateTime.now();
            
            debugPrint('🌐 [DIAG] Fetch de rede completo, coverage atualizado, agendando re-render');
            onNewData();
          }).catchError((e) {
            debugPrint('⚠️ [DIAG] Erro no fetch de rede: $e');
          }),
        );
      }

      // Delegar para controller de pessoas
      await peopleController.onCameraIdle(visibleRegion, currentZoom, clusterZoomThreshold);
    } catch (error) {
      debugPrint('⚠️ MapBoundsController: Erro ao capturar bounding box: $error');
    }
  }

  Future<void> triggerInitialEventSearch(double currentZoom, {required VoidCallback onNewData}) async {
    if (mapController == null) return;

    try {
      await Future.delayed(const Duration(milliseconds: 500));
      
      final visibleRegion = await mapController!.getVisibleRegion();
      viewModel.setVisibleBounds(visibleRegion);
      lastExpandedVisibleBounds = expandBounds(visibleRegion, viewportBoundsBufferFactor);
      
      // ✅ Usar bounds EXPANDIDO para busca inicial
      final pfExpandedBounds = expandBounds(visibleRegion, _prefetchBoundsBufferFactor);
      final expandedQueryBounds = MapBounds.fromLatLngBounds(pfExpandedBounds);
      
      debugPrint('🎯 MapBoundsController: Busca inicial de eventos em $expandedQueryBounds');
      
      final now = DateTime.now();
      final withinPrevious = _lastRequestedQueryBounds != null &&
          isBoundsContained(expandedQueryBounds, _lastRequestedQueryBounds!);
      final tooSoon = now.difference(_lastRequestedQueryAt) < _minIntervalBetweenContainedBoundsQueries;

      // ✅ Inicializar zoom bucket
      _lastZoomBucket = _zoomBucket(currentZoom);

      if (!(withinPrevious && tooSoon)) {
        _lastRequestedQueryBounds = expandedQueryBounds;
        _lastRequestedQueryAt = now;
        
        // ✅ ESTADO ROBUSTO: Marcar início do prefetch
        _prefetchInFlight = true;
        debugPrint('🚀 [INITIAL] Iniciando busca inicial (prefetch expandido)...');
        
        try {
          await viewModel.forceRefreshBounds(expandedQueryBounds);
          
          // ✅ Marcar prefetch como completado com sucesso
          _prefetchCoverageBounds = pfExpandedBounds;
          _prefetchCompletedAt = DateTime.now();
          
          debugPrint('✅ [INITIAL] Busca inicial concluída, events=${viewModel.events.length}');
        } catch (e) {
          debugPrint('❌ [INITIAL] Busca inicial falhou: $e');
        } finally {
          _prefetchInFlight = false;
        }
      }

      final viewportActive = currentZoom > clusterZoomThreshold;
      peopleController.setViewportActive(viewportActive);
      if (viewportActive) {
        await peopleController.forceRefresh(expandedQueryBounds, zoom: currentZoom);
      }
      
      if (viewModel.events.isNotEmpty) {
        onNewData();
      }
    } catch (error) {
      debugPrint('⚠️ MapBoundsController: Erro na busca inicial: $error');
    }
  }
}
