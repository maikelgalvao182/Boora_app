import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/presentation/services/marker_cluster_service.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_bitmap_generator.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/map_bounds_controller.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/marker_assets.dart';

class MapRenderController extends ChangeNotifier {
  final MapViewModel viewModel;
  final MapMarkerAssets assets;
  final MapBoundsController boundsController;
  final Function(EventModel) onMarkerTap;
  final Function(LatLng, int) onClusterTap;
  final VoidCallback? onFirstRenderApplied;

  Set<Marker> _markers = {};
  Set<Marker> _avatarOverlayMarkers = {};
  final Map<MarkerId, Marker> _staleMarkers = {};
  final Map<MarkerId, DateTime> _staleMarkersExpiry = {};
  Timer? _staleMarkersTimer;

  static const Duration _staleMarkersTtl = Duration(seconds: 6);
  
  Set<Marker> get allMarkers {
    final merged = <MarkerId, Marker>{};
    for (final entry in _staleMarkers.entries) {
      merged[entry.key] = entry.value;
    }
    for (final marker in _markers) {
      merged[marker.markerId] = marker;
    }
    for (final marker in _avatarOverlayMarkers) {
      merged[marker.markerId] = marker;
    }
    return merged.values.toSet();
  }

  final MarkerClusterService _clusterService = MarkerClusterService();

  // Timers
  Timer? _renderDebounce;
  // Aumentado levemente para aguardar estabilização do cluster manager
  static const Duration _renderDebounceDuration = Duration(milliseconds: 150);

  
  // State from view
  double _currentZoom = 12.0;
  bool _isAnimating = false;
  bool _isCameraMoving = false;
  
  // Loading state for low zoom (clusters)
  static const double lowZoomThreshold = 5.0;
  static const double _individualMarkerZoomThreshold = 12.0;
  static const int _maxIndividualMarkers = 150;
  bool _isLoadingLowZoom = false;
  bool get isLoadingLowZoom => _isLoadingLowZoom && _currentZoom <= lowZoomThreshold;
  
  // Flags
  bool _didEmitFirstRenderApplied = false;
  bool _renderPendingAfterMove = false;
  bool _isDisposed = false;

  MapRenderController({
    required this.viewModel,
    required this.assets,
    required this.boundsController,
    required this.onMarkerTap,
    required this.onClusterTap,
    this.onFirstRenderApplied,
  });

  void setZoom(double zoom) {
    if ((_currentZoom - zoom).abs() < 0.05) return;
    final previousZoom = _currentZoom;
    _currentZoom = zoom;
    
    // Se entramos na zona de zoom baixo (≤5.0), ativar loading até markers renderizarem
    if (zoom <= lowZoomThreshold && previousZoom > lowZoomThreshold) {
      _isLoadingLowZoom = true;
      notifyListeners();
    }
  }

  void setCameraMoving(bool isMoving) {
    _isCameraMoving = isMoving;
    // Se parou de mover e tinha render pendente, executa DEPOIS de um delay
    // para garantir que o mapa estabilizou o viewport interno.
    if (!isMoving && _renderPendingAfterMove) {
      _renderPendingAfterMove = false;
      // Damos um tempo extra pro Google Maps estabilizar bounds antes de clusterizar
      Future.delayed(const Duration(milliseconds: 100), scheduleRender);
    }
  }

  void setAnimating(bool isAnimating) {
    _isAnimating = isAnimating;
    if (!isAnimating && _renderPendingAfterMove) {
      _renderPendingAfterMove = false;
      Future.delayed(const Duration(milliseconds: 100), scheduleRender);
    }
  }

  /// Remove um marker específico do cache visual instantaneamente.
  /// Bypassa o debounce e rebuild completo do cluster manager.
  void removeEventMarker(String eventId) {
    bool removed = false;
    
    // Remove dos markers isolados
    final initialSize = _markers.length;
    _markers.removeWhere((m) => m.markerId.value == 'event_$eventId');
    if (_markers.length < initialSize) removed = true;
    
    // Remove dos overlays de avatar
    _avatarOverlayMarkers.removeWhere((m) {
      if (m.markerId.value == 'event_$eventId') {
        removed = true; // count as removed
        return true;
      }
      return false;
    });
    
    // Se removido de algum set local, notifica imediatamente
    if (removed) {
      notifyListeners();
    }
    
    // Agendar rebuild completo para garantir consistência do ClusterManager
    // (o marker pode estar "dentro" de um cluster e não nos sets soltos)
    scheduleRender();
  }

  void dispose() {
    _isDisposed = true;
    _renderDebounce?.cancel();
    _staleMarkersTimer?.cancel();
    super.dispose();
  }

  void scheduleRender() {
    if (_isDisposed) return;
    
    // Durante zoom/pan, cancelamos renders ativos para evitar flicker
    if (_isAnimating || _isCameraMoving) {
      _renderDebounce?.cancel(); // Cancela timer anterior se houver
      _renderPendingAfterMove = true;
      return;
    }

    _renderDebounce?.cancel();
    _renderDebounce = Timer(_renderDebounceDuration, () {
      if (_isDisposed) return;
      // Dupla checagem: se começou a mover nesse meio tempo, aborta
      if (_isAnimating || _isCameraMoving) {
          _renderPendingAfterMove = true;
          return;
      }
      _rebuildMarkersUsingClusterService();
    });
  }

  Future<void> _rebuildMarkersUsingClusterService() async {
    if (_isDisposed) return;
    if (_isAnimating || _isCameraMoving) return;

    final renderStart = DateTime.now();

    final allEvents = List<EventModel>.from(viewModel.events);
    if (allEvents.isEmpty) {
      if (_markers.isNotEmpty || _avatarOverlayMarkers.isNotEmpty) {
        debugPrint(
          '🧭 [MapRender] clear markers (reason=dataset_empty, prev=${_markers.length + _avatarOverlayMarkers.length}, stale=${_staleMarkers.length})',
        );
        _addStaleMarkers(
          previousMarkers: {..._markers, ..._avatarOverlayMarkers},
          nextMarkers: const <Marker>{},
        );
        _markers = {};
        _avatarOverlayMarkers.clear();
        notifyListeners();
      }
      return;
    }

    final filteredEvents = _applyCategoryFilter(allEvents);
    if (filteredEvents.isEmpty) {
      final hasFilters = viewModel.selectedCategory != null || viewModel.selectedDate != null;
      if (hasFilters) {
        debugPrint(
          '🧭 [MapRender] clear markers (reason=filters_empty, prev=${_markers.length + _avatarOverlayMarkers.length}, stale=${_staleMarkers.length})',
        );
        _addStaleMarkers(
          previousMarkers: {..._markers, ..._avatarOverlayMarkers},
          nextMarkers: const <Marker>{},
        );
        _markers = {};
        _avatarOverlayMarkers.clear();
        notifyListeners();
      }
      return;
    }

    // Warmup avatars in parallel (best-effort)
    unawaited(assets.warmupAvatarsForEvents(filteredEvents));

    // Garantir que o Fluster está preparado com o dataset atual
    _clusterService.buildFluster(filteredEvents);

    // Calcular zoomBucket para verificação de estado do cluster
    // IMPORTANTE: usar floor() para consistência com clustersForView() que usa zoomInt
    final zoomInt = _currentZoom.floor();
    final zoomBucket = zoomInt <= 8 ? 0 : zoomInt <= 11 ? 1 : zoomInt <= 14 ? 2 : 3;

    final bounds = boundsController.lastExpandedVisibleBounds;
    var clusters = bounds != null
        ? _clusterService.clustersForView(bounds: bounds, zoom: _currentZoom)
        : _clusterService.clusterEvents(events: filteredEvents, zoom: _currentZoom);

    // Verificar se cluster está sincronizado APÓS chamar clustersForView
    // (clustersForView atualiza _lastBuiltKey internamente)
    final eventsHash = _clusterService.eventsHash;
    final isClusterReady = eventsHash == null || _clusterService.isReadyFor(eventsHash: eventsHash, zoomBucket: zoomBucket);

    // Se o bounds atual não intersecta o dataset (ex.: corrida entre bounds e eventos),
    // evitamos “mapa vazio” usando clusterização global como fallback.
    if (clusters.isEmpty && filteredEvents.isNotEmpty) {
      debugPrint(
        '🧭 [MapRender] clusters empty (events=${filteredEvents.length}, zoom=${_currentZoom.toStringAsFixed(1)}) -> fallback global',
      );
      clusters = _clusterService.clusterEvents(
        events: filteredEvents,
        zoom: _currentZoom,
      );
    }

    // Removido: placeholder com BitmapDescriptor.defaultMarker causava flash de markers nativos
    // Os markers personalizados são gerados diretamente abaixo

    final nextMarkers = <Marker>{};
    final nextAvatarOverlays = <Marker>{};

    int zIndexCounter = 0;
    int individualMarkersRendered = 0;

    for (final cluster in clusters) {
      if (cluster.isSingleEvent) {
        final allowIndividual = _currentZoom >= _individualMarkerZoomThreshold &&
            individualMarkersRendered < _maxIndividualMarkers;
        if (!allowIndividual) {
          // Em zoom baixo ou com muitos markers, renderiza como cluster com emoji
          final event = cluster.firstEvent;
          final clusterPin = await assets.getClusterPinWithEmoji(
            1, // count = 1 para evento único
            event.emoji,
          );
          nextMarkers.add(
            Marker(
              markerId: MarkerId(cluster.id),
              position: cluster.center,
              icon: clusterPin,
              anchor: const Offset(0.5, 1.0),
              zIndex: 1000,
              infoWindow: InfoWindow.noText,
              onTap: () => onMarkerTap(event),
            ),
          );
          continue;
        }

        final event = cluster.firstEvent;
        final position = cluster.center;
        final baseZIndex = 100 + (zIndexCounter * 2);
        zIndexCounter++;
        individualMarkersRendered++;

        final emojiPin = await MarkerBitmapGenerator.generateEmojiPinForGoogleMaps(
          event.emoji,
          eventId: event.id,
          size: 230,
        );

        nextMarkers.add(
          Marker(
            markerId: MarkerId('event_${event.id}'),
            position: position,
            icon: emojiPin,
            anchor: const Offset(0.5, 1.0),
            zIndex: baseZIndex.toDouble(),
            onTap: () => onMarkerTap(event),
          ),
        );

        final avatarPin = await assets.getAvatarPinBestEffort(event);
        nextAvatarOverlays.add(
          Marker(
            markerId: MarkerId('event_avatar_${event.id}'),
            position: position,
            icon: avatarPin,
            anchor: const Offset(0.5, 0.80),
            onTap: () => onMarkerTap(event),
            zIndex: (baseZIndex + 1).toDouble(),
          ),
        );
      } else {
        final clusterPin = await assets.getClusterPinWithEmoji(
          cluster.count,
          cluster.representativeEmoji,
        );

        nextMarkers.add(
          Marker(
            markerId: MarkerId(cluster.id),
            position: cluster.center,
            icon: clusterPin,
            anchor: const Offset(0.5, 1.0),
            zIndex: 1000,
            infoWindow: InfoWindow.noText,
            onTap: () => onClusterTap(cluster.center, cluster.count),
          ),
        );
      }
    }

    _addStaleMarkers(
      previousMarkers: {..._markers, ..._avatarOverlayMarkers},
      nextMarkers: {...nextMarkers, ...nextAvatarOverlays},
    );

    _avatarOverlayMarkers = nextAvatarOverlays;
    _markers = nextMarkers;

    final markersProduced = nextMarkers.length + nextAvatarOverlays.length;
    final renderMs = DateTime.now().difference(renderStart).inMilliseconds;
    final boundsKey = bounds == null
        ? 'null'
        : '${bounds.southwest.latitude.toStringAsFixed(3)}_'
            '${bounds.southwest.longitude.toStringAsFixed(3)}_'
            '${bounds.northeast.latitude.toStringAsFixed(3)}_'
            '${bounds.northeast.longitude.toStringAsFixed(3)}';
    debugPrint(
      '🧭 [MapRender] applyMarkers(boundsKey=$boundsKey, nextCount=$markersProduced, stale=${_staleMarkers.length})',
    );
    debugPrint(
      '🧭 [MapRender] render done (boundsKey=$boundsKey, zoom=${_currentZoom.toStringAsFixed(1)}, clusters=${clusters.length}, markersProduced=$markersProduced, individualRendered=$individualMarkersRendered, stale=${_staleMarkers.length}, ms=$renderMs)',
    );

    if (_isLoadingLowZoom && _currentZoom <= lowZoomThreshold) {
      _isLoadingLowZoom = false;
    }

    notifyListeners();

    if (!_didEmitFirstRenderApplied) {
      _didEmitFirstRenderApplied = true;
      onFirstRenderApplied?.call();
    }

    // 🔄 Se o cluster não estava pronto no início do render, agenda um re-render
    // para garantir que os markers estejam corretos após o build finalizar
    if (!isClusterReady) {
      debugPrint('🔄 [MapRender] Cluster não estava pronto, agendando re-render');
      Future.microtask(() {
        if (!_isDisposed && !_isAnimating && !_isCameraMoving) {
          scheduleRender();
        }
      });
    }
  }

  void _addStaleMarkers({
    required Set<Marker> previousMarkers,
    required Set<Marker> nextMarkers,
  }) {
    final nextIds = nextMarkers.map((m) => m.markerId).toSet();
    final now = DateTime.now();

    for (final marker in previousMarkers) {
      if (nextIds.contains(marker.markerId)) continue;
      _staleMarkers[marker.markerId] = marker.copyWith(
        alphaParam: 0.0,
        onTapParam: null,
        zIndexParam: -10000,
        infoWindowParam: InfoWindow.noText,
      );
      _staleMarkersExpiry[marker.markerId] = now.add(_staleMarkersTtl);
    }

    _pruneStaleMarkers(now);

    _staleMarkersTimer?.cancel();
    _staleMarkersTimer = Timer(_staleMarkersTtl, () {
      if (_isDisposed) return;
      _pruneStaleMarkers(DateTime.now());
      notifyListeners();
    });
  }

  void _pruneStaleMarkers(DateTime now) {
    final expired = <MarkerId>[];
    _staleMarkersExpiry.forEach((id, expiry) {
      if (expiry.isBefore(now)) {
        expired.add(id);
      }
    });
    for (final id in expired) {
      _staleMarkersExpiry.remove(id);
      _staleMarkers.remove(id);
    }
  }

  List<EventModel> _applyCategoryFilter(List<EventModel> events) {
    return _applyFilters(events);
  }
  
  /// Aplica filtros de categoria E data aos eventos
  List<EventModel> _applyFilters(List<EventModel> events) {
    final selectedCategory = viewModel.selectedCategory;
    final selectedDate = viewModel.selectedDate;
    
    // Se não há filtros ativos, retorna tudo
    if ((selectedCategory == null || selectedCategory.trim().isEmpty) &&
        selectedDate == null) {
      return events;
    }

    return events.where((event) {
      // Filtro de categoria
      if (selectedCategory != null && selectedCategory.trim().isNotEmpty) {
        final category = event.category;
        if (category == null) return false;
        if (category.trim() != selectedCategory.trim()) return false;
      }
      
      // Filtro de data
      if (selectedDate != null) {
        final eventDate = event.scheduleDate;
        if (eventDate == null) return false;
        
        // Comparar apenas dia/mês/ano
        if (eventDate.year != selectedDate.year ||
            eventDate.month != selectedDate.month ||
            eventDate.day != selectedDate.day) {
          return false;
        }
      }
      
      return true;
    }).toList(growable: false);
  }

}
