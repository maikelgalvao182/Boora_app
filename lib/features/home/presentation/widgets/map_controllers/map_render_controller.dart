import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/presentation/services/marker_cluster_service.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_bitmap_generator.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/map_bounds_controller.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/marker_assets.dart';
import 'package:partiu/services/events/event_creator_filters_controller.dart';

class MapRenderController extends ChangeNotifier {
  final MapViewModel viewModel;
  final MapMarkerAssets assets;
  final MapBoundsController boundsController;
  final Function(EventModel) onMarkerTap;
  final Function(LatLng, int) onClusterTap;
  final VoidCallback? onFirstRenderApplied;

  Set<Marker> _markers = {};
  Set<Marker> _avatarOverlayMarkers = {};
  
  Set<Marker> get allMarkers {
    return {..._markers, ..._avatarOverlayMarkers};
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
          '🧭 [MapRender] clear markers (reason=dataset_empty, prev=${_markers.length + _avatarOverlayMarkers.length})',
        );
        _markers = {};
        _avatarOverlayMarkers.clear();
        notifyListeners();
      }
      return;
    }

    final filteredEvents = _applyCategoryFilter(allEvents);
    if (filteredEvents.isEmpty) {
      final creatorFilters = EventCreatorFiltersController();
      final hasFilters = viewModel.selectedCategory != null || viewModel.selectedDate != null || (creatorFilters.filtersEnabled && creatorFilters.hasActiveFilters);
      if (hasFilters) {
        debugPrint(
          '🧭 [MapRender] clear markers (reason=filters_empty, prev=${_markers.length + _avatarOverlayMarkers.length})',
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
        // ✅ Evento único SEMPRE renderiza como marker individual (nunca como cluster de 1)
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
      '🧭 [MapRender] applyMarkers(boundsKey=$boundsKey, nextCount=$markersProduced)',
    );
    debugPrint(
      '🧭 [MapRender] render done (boundsKey=$boundsKey, zoom=${_currentZoom.toStringAsFixed(1)}, clusters=${clusters.length}, markersProduced=$markersProduced, individualRendered=$individualMarkersRendered, ms=$renderMs)',
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

  List<EventModel> _applyCategoryFilter(List<EventModel> events) {
    return _applyFilters(events);
  }
  
  /// Aplica filtros de categoria, data E criador aos eventos
  List<EventModel> _applyFilters(List<EventModel> events) {
    final selectedCategory = viewModel.selectedCategory;
    final selectedDate = viewModel.selectedDate;
    final creatorFilters = EventCreatorFiltersController();
    final hasCreatorFilters = creatorFilters.filtersEnabled && creatorFilters.hasActiveFilters;
    
    // Se não há filtros ativos, retorna tudo
    if ((selectedCategory == null || selectedCategory.trim().isEmpty) &&
        selectedDate == null &&
        !hasCreatorFilters) {
      return events;
    }

    final filters = hasCreatorFilters ? creatorFilters.currentFilters : null;

    // 🔍 DEBUG: log dos filtros ativos
    debugPrint('🔍 [Filter] category=$selectedCategory, date=$selectedDate, '
        'creatorFilters=${filters != null}, filtersEnabled=${creatorFilters.filtersEnabled}, '
        'hasActive=${creatorFilters.hasActiveFilters}');
    if (filters != null) {
      debugPrint('🔍 [Filter] gender=${filters.creatorGender}, '
          'orientation=${filters.creatorSexualOrientation}, '
          'minAge=${filters.creatorMinAge}, maxAge=${filters.creatorMaxAge}, '
          'verified=${filters.creatorVerified}, '
          'interests=${filters.creatorInterests}');
    }

    int rejectedByCategory = 0;
    int rejectedByDate = 0;
    int rejectedByGender = 0;
    int rejectedByOrientation = 0;
    int rejectedByAge = 0;
    int rejectedByVerified = 0;
    int rejectedByInterests = 0;

    final result = events.where((event) {
      // Filtro de categoria
      if (selectedCategory != null && selectedCategory.trim().isNotEmpty) {
        final category = event.category;
        if (category == null) { rejectedByCategory++; return false; }
        if (category.trim() != selectedCategory.trim()) { rejectedByCategory++; return false; }
      }
      
      // Filtro de data
      if (selectedDate != null) {
        final eventDate = event.scheduleDate;
        if (eventDate == null) { rejectedByDate++; return false; }
        
        if (eventDate.year != selectedDate.year ||
            eventDate.month != selectedDate.month ||
            eventDate.day != selectedDate.day) {
          rejectedByDate++;
          return false;
        }
      }

      // Filtros de criador
      if (filters != null) {
        // Gênero - case-insensitive; exclui se campo vazio/null
        if (filters.creatorGender != null) {
          final eventGender = (event.creatorGender?.trim().isNotEmpty == true) ? event.creatorGender!.trim().toLowerCase() : null;
          if (eventGender == null) { rejectedByGender++; return false; }
          if (eventGender != filters.creatorGender!.trim().toLowerCase()) { rejectedByGender++; return false; }
        }
        // Orientação sexual - case-insensitive; exclui se campo vazio/null
        if (filters.creatorSexualOrientation != null) {
          final eventOrientation = (event.creatorSexualOrientation?.trim().isNotEmpty == true) ? event.creatorSexualOrientation!.trim().toLowerCase() : null;
          if (eventOrientation == null) { rejectedByOrientation++; return false; }
          if (eventOrientation != filters.creatorSexualOrientation!.trim().toLowerCase()) { rejectedByOrientation++; return false; }
        }
        // Idade - exclui se criador não tem idade definida
        if (filters.creatorMinAge != null || filters.creatorMaxAge != null) {
          if (event.creatorAge == null) { rejectedByAge++; return false; }
          if (filters.creatorMinAge != null && event.creatorAge! < filters.creatorMinAge!) { rejectedByAge++; return false; }
          if (filters.creatorMaxAge != null && event.creatorAge! > filters.creatorMaxAge!) { rejectedByAge++; return false; }
        }
        // Verificado
        if (filters.creatorVerified == true) {
          if (!event.creatorVerified) { rejectedByVerified++; return false; }
        }
        // Interesses - exclui se criador não tem interesses definidos
        if (filters.creatorInterests != null && filters.creatorInterests!.isNotEmpty) {
          if (event.creatorInterests.isEmpty) { rejectedByInterests++; return false; }
          if (!filters.creatorInterests!.any((i) => event.creatorInterests.contains(i))) { rejectedByInterests++; return false; }
        }
      }
      
      return true;
    }).toList(growable: false);

    debugPrint('🔍 [Filter] result: ${result.length}/${events.length} passed. '
        'Rejected: cat=$rejectedByCategory, date=$rejectedByDate, '
        'gender=$rejectedByGender, orient=$rejectedByOrientation, '
        'age=$rejectedByAge, verified=$rejectedByVerified, '
        'interests=$rejectedByInterests');

    // 🔍 DEBUG: amostra de dados de criador (primeiros 3 eventos)
    if (result.isEmpty && events.isNotEmpty) {
      for (var i = 0; i < events.length && i < 3; i++) {
        final e = events[i];
        debugPrint('🔍 [Filter] sample[$i]: id=${e.id}, '
            'creatorGender=${e.creatorGender}, creatorAge=${e.creatorAge}, '
            'creatorVerified=${e.creatorVerified}, '
            'creatorOrientation=${e.creatorSexualOrientation}, '
            'creatorInterests=${e.creatorInterests}');
      }
    }

    return result;
  }

}
