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
  LatLngBounds? prefetchedExpandedBounds;

  MapBounds? _lastRequestedQueryBounds;
  DateTime _lastRequestedQueryAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minIntervalBetweenContainedBoundsQueries = Duration(seconds: 2);

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

  Future<void> prefetchEventsForExpandedBounds(LatLngBounds visibleRegion) async {
    if (mapController == null) return;

    final expanded = expandBounds(visibleRegion, _prefetchBoundsBufferFactor);
    prefetchedExpandedBounds = expanded;

    final prefetchQuery = MapBounds.fromLatLngBounds(expanded);
    try {
      await viewModel.loadEventsInBounds(prefetchQuery);
    } catch (_) {
      // ignora
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
      viewModel.softLookaheadForBounds(lookaheadBounds);
    });
  }

  Future<void> onCameraIdle(double currentZoom, {required VoidCallback onNewData}) async {
    if (mapController == null) return;

    try {
      final visibleRegion = await mapController!.getVisibleRegion();
      viewModel.setVisibleBounds(visibleRegion, zoom: currentZoom);
      final expandedBounds = expandBounds(visibleRegion, viewportBoundsBufferFactor);
      lastExpandedVisibleBounds = expandedBounds;

      final pfExpandedBounds = expandBounds(visibleRegion, _prefetchBoundsBufferFactor);

      final queryBounds = MapBounds.fromLatLngBounds(expandedBounds);
      final peopleBounds = MapBounds.fromLatLngBounds(visibleRegion);
      
      debugPrint('📍 MapBoundsController: Câmera parou (zoom: ${currentZoom.toStringAsFixed(1)})');
      
      final now = DateTime.now();
      final withinPrevious = _lastRequestedQueryBounds != null &&
          isBoundsContained(queryBounds, _lastRequestedQueryBounds!);
      final tooSoon = now.difference(_lastRequestedQueryAt) < _minIntervalBetweenContainedBoundsQueries;

      final withinPrefetched = prefetchedExpandedBounds != null &&
          isLatLngBoundsContained(visibleRegion, prefetchedExpandedBounds!);

      if (withinPrefetched) {
        debugPrint('📦 MapBoundsController: Dentro do bounds pré-carregado, pulando refetch');
        final applied = await viewModel.softLookaheadForBounds(queryBounds);
        if (!applied) {
          _lastRequestedQueryBounds = queryBounds;
          _lastRequestedQueryAt = now;
          await viewModel.loadEventsInBounds(
            queryBounds,
            prefetchNeighbors: currentZoom > clusterZoomThreshold,
          );
          prefetchedExpandedBounds = pfExpandedBounds;
        }
        onNewData();
      } else if (withinPrevious && tooSoon) {
        debugPrint('📦 MapBoundsController: Bounds contido, pulando refetch (janela curta)');
        final applied = await viewModel.softLookaheadForBounds(queryBounds);
        if (!applied) {
          _lastRequestedQueryBounds = queryBounds;
          _lastRequestedQueryAt = now;
          await viewModel.loadEventsInBounds(
            queryBounds,
            prefetchNeighbors: currentZoom > clusterZoomThreshold,
          );
          prefetchedExpandedBounds = pfExpandedBounds;
        }
        onNewData();
      } else {
        _lastRequestedQueryBounds = queryBounds;
        _lastRequestedQueryAt = now;
        await viewModel.loadEventsInBounds(
          queryBounds,
          prefetchNeighbors: currentZoom > clusterZoomThreshold,
        );

        prefetchedExpandedBounds = pfExpandedBounds;
        onNewData();
      }

      final viewportActive = currentZoom > clusterZoomThreshold;
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
      final bounds = MapBounds.fromLatLngBounds(visibleRegion);

      unawaited(prefetchEventsForExpandedBounds(visibleRegion));
      
      debugPrint('🎯 MapBoundsController: Busca inicial de eventos em $bounds');
      
      final now = DateTime.now();
      final withinPrevious = _lastRequestedQueryBounds != null &&
          isBoundsContained(bounds, _lastRequestedQueryBounds!);
      final tooSoon = now.difference(_lastRequestedQueryAt) < _minIntervalBetweenContainedBoundsQueries;

      if (!(withinPrevious && tooSoon)) {
        _lastRequestedQueryBounds = bounds;
        _lastRequestedQueryAt = now;
        await viewModel.forceRefreshBounds(bounds);
      }

      final viewportActive = currentZoom > clusterZoomThreshold;
      peopleController.setViewportActive(viewportActive);
      if (viewportActive) {
        await peopleController.forceRefresh(bounds, zoom: currentZoom);
      }
      
      if (viewModel.events.isNotEmpty) {
        onNewData();
      }
    } catch (error) {
      debugPrint('⚠️ MapBoundsController: Erro na busca inicial: $error');
    }
  }
}
