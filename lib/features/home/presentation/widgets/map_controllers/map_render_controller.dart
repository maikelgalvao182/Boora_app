import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:markers_cluster_google_maps_flutter/markers_cluster_google_maps_flutter.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_bitmap_generator.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/event_card_presenter.dart';
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
  
  Set<Marker> get allMarkers => {..._markers, ..._avatarOverlayMarkers};

  MarkersClusterManager? _clusterManager;
  int _lastMarkersSignature = 0;
  
  // Map of events by ID for efficient lookup
  final Map<String, EventModel> _eventById = {};

  // Timers
  Timer? _renderDebounce;
  // Aumentado levemente para aguardar estabilização do cluster manager
  static const Duration _renderDebounceDuration = Duration(milliseconds: 150);

  Timer? _realtimeClusterDebounce;
  static const Duration _realtimeClusterDebounceDuration = Duration(milliseconds: 70);

  bool _isClusterUpdateRunning = false;
  bool _hasPendingClusterUpdate = false;
  
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
  int _lastRenderedEventsVersion = -1;

  MapRenderController({
    required this.viewModel,
    required this.assets,
    required this.boundsController,
    required this.onMarkerTap,
    required this.onClusterTap,
    this.onFirstRenderApplied,
  });

  void setZoom(double zoom) {
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
    if (!isMoving && _renderPendingAfterMove) {
      _renderPendingAfterMove = false;
      scheduleRender();
    }
  }

  void setAnimating(bool isAnimating) {
    _isAnimating = isAnimating;
    if (!isAnimating && _renderPendingAfterMove) {
      _renderPendingAfterMove = false;
      scheduleRender();
    }
  }

  /// Remove um marker específico do cache visual instantaneamente.
  /// Bypassa o debounce e rebuild completo do cluster manager.
  void removeEventMarker(String eventId) {
    bool removed = false;
    
    // Remove do mapa de ID
    if (_eventById.containsKey(eventId)) {
      _eventById.remove(eventId);
    }
    
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
    _renderDebounce?.cancel();
    _realtimeClusterDebounce?.cancel();
    super.dispose();
  }

  void scheduleRender() {
    if (_isAnimating || _isCameraMoving) {
      _renderPendingAfterMove = true;
      return;
    }

    _renderDebounce?.cancel();
    _renderDebounce = Timer(_renderDebounceDuration, () {
      if (_isAnimating || _isCameraMoving) return;
      _rebuildMarkersUsingClusterManager();
    });
  }

  MarkersClusterManager _createClusterManager() {
    return MarkersClusterManager(
      clusterColor: Colors.black,
      clusterBorderThickness: 6.0,
      clusterBorderColor: Colors.white,
      clusterOpacity: 0.92,
      clusterTextStyle: const TextStyle(
        fontSize: 28,
        color: Colors.white,
        fontWeight: FontWeight.w800,
      ),
      onMarkerTap: null, // Managed manually
    );
  }

  int _extractClusterCount(Marker m) {
    final title = m.infoWindow.title;
    if (title == null) return 2; // Fallback
    final match = RegExp(r'^(\d+)\s+markers?$').firstMatch(title);
    if (match == null) return 2;
    return int.tryParse(match.group(1) ?? '') ?? 2;
  }

  int _markerSignatureForEvents(List<EventModel> events) {
    final ids = events.map((e) => e.id).toList()..sort();
    return Object.hashAll(ids);
  }

  Future<void> _syncBaseMarkersIntoClusterManager(List<EventModel> events) async {
    if (_clusterManager == null) {
      _clusterManager = _createClusterManager();
    }

    final signature = _markerSignatureForEvents(events);
    if (signature == _lastMarkersSignature) return;
    _lastMarkersSignature = signature;

    final rebuilt = _createClusterManager();

    // Warmup avatars in parallel
    unawaited(assets.warmupAvatarsForEvents(events));

    final markerFutures = events.map((event) async {
      try {
        final emojiPin = await MarkerBitmapGenerator.generateEmojiPinForGoogleMaps(
          event.emoji,
          eventId: event.id,
          size: 230,
        );
        return MapEntry(event, emojiPin);
      } catch (_) {
        return null;
      }
    }).toList();

    final results = await Future.wait(markerFutures);
    
    for (final result in results) {
      if (result == null) continue;
      final event = result.key;
      final emojiPin = result.value;
      
      rebuilt.addMarker(
        Marker(
          markerId: MarkerId('event_${event.id}'),
          position: LatLng(event.lat, event.lng),
          icon: emojiPin,
          anchor: const Offset(0.5, 1.0),
          zIndex: 1,
          onTap: () => onMarkerTap(event),
        ),
      );
    }
    
    _eventById
      ..clear()
      ..addEntries(events.map((e) => MapEntry(e.id, e)));

    _clusterManager = rebuilt;
  }

  Future<void> _rebuildMarkersUsingClusterManager() async {
    if (_isAnimating || _isCameraMoving) return;
    // Note: We don't check mounted here (no context), rely on usage.

    final allEvents = List<EventModel>.from(viewModel.events);
    if (allEvents.isEmpty) {
      if (_markers.isNotEmpty || _avatarOverlayMarkers.isNotEmpty) {
        _markers = {};
        _avatarOverlayMarkers.clear();
        notifyListeners();
      }
      return;
    }

    // Filter by category
    final categoryFiltered = _applyCategoryFilter(allEvents);

    // Filter by viewport if zoom is high
    var bounds = boundsController.lastExpandedVisibleBounds;
    // Requires boundsController to have updated bounds.
    // If null, we might skip filtering or try to get it (but we don't have mapController here easily unless passed).
    // Assuming boundsController updates it on camera move/idle.
    
    const double clusterZoomThreshold = 11.0;
    final shouldFilterByViewport = _currentZoom > clusterZoomThreshold;
    
    List<EventModel> viewportEvents = categoryFiltered;
    if (shouldFilterByViewport && bounds != null) {
       viewportEvents = categoryFiltered
        .where((event) => boundsController.boundsContains(bounds!, event.lat, event.lng))
        .toList(growable: false);
    }

    if (viewportEvents.isEmpty) {
      if (_markers.isNotEmpty || _avatarOverlayMarkers.isNotEmpty) {
        _markers = {};
        _avatarOverlayMarkers.clear();
        notifyListeners();
      }
      return;
    }

    await _syncBaseMarkersIntoClusterManager(viewportEvents);
    await _updateClustersFromManager();

    if (!_didEmitFirstRenderApplied) {
      _didEmitFirstRenderApplied = true;
      onFirstRenderApplied?.call();
    }
  }

  List<EventModel> _applyCategoryFilter(List<EventModel> events) {
    final selected = viewModel.selectedCategory;
    if (selected == null || selected.trim().isEmpty) return events;

    final normalized = selected.trim();
    return events.where((event) {
      final category = event.category;
      if (category == null) return false;
      return category.trim() == normalized;
    }).toList(growable: false);
  }

  Future<void> _updateClustersFromManager() async {
    final manager = _clusterManager;
    if (manager == null) return;

    await manager.updateClusters(zoomLevel: _currentZoom);
    final clustered = Set<Marker>.of(manager.getClusteredMarkers());

    final nextClusteredStyled = <Marker>{};
    for (final m in clustered) {
      final rawId = m.markerId.value;
      
      if (rawId.startsWith('event_')) {
        final eventId = rawId.replaceFirst('event_', '');
        final event = _eventById[eventId];
        if (event != null) {
          nextClusteredStyled.add(
            m.copyWith(
              onTapParam: () => onMarkerTap(event),
            ),
          );
        } else {
          nextClusteredStyled.add(m);
        }
        continue;
      }

      if (!rawId.startsWith('cluster_')) {
        nextClusteredStyled.add(m);
        continue;
      }

      int count = _extractClusterCount(m);
      
      final clusterPosition = m.position;
      final clusterEmoji = assets.pickClusterEmoji(clusterPosition, _eventById);
      
      final clusterPin = await assets.getClusterPinWithEmoji(count, clusterEmoji);
      
      nextClusteredStyled.add(
        m.copyWith(
          iconParam: clusterPin,
          anchorParam: const Offset(0.5, 1.0),
          zIndexParam: 1000,
          infoWindowParam: InfoWindow.noText,
          onTapParam: () => onClusterTap(clusterPosition, count),
        ),
      );
    }

    final nextAvatarOverlays = <Marker>{};
    int avatarZIndexCounter = 0;
    final updatedEmojiMarkers = <Marker>{};
    final markersToRemove = <Marker>{};
    
    for (final m in nextClusteredStyled) {
      final rawId = m.markerId.value;
      if (!rawId.startsWith('event_')) continue;
      final eventId = rawId.replaceFirst('event_', '');
      final event = _eventById[eventId];
      if (event == null) continue;

      final baseZIndex = 100 + (avatarZIndexCounter * 2);
      avatarZIndexCounter++;

      markersToRemove.add(m);
      updatedEmojiMarkers.add(m.copyWith(zIndexParam: baseZIndex.toDouble()));
      
      final avatarPin = await assets.getAvatarPinBestEffort(event);
      nextAvatarOverlays.add(
        Marker(
          markerId: MarkerId('event_avatar_$eventId'),
          position: m.position,
          icon: avatarPin,
          anchor: const Offset(0.5, 0.80),
          onTap: () => onMarkerTap(event),
          zIndex: (baseZIndex + 1).toDouble(),
        ),
      );
    }

    nextClusteredStyled.removeAll(markersToRemove);
    nextClusteredStyled.addAll(updatedEmojiMarkers);

    _avatarOverlayMarkers = nextAvatarOverlays;
    _markers = nextClusteredStyled;
    
    // Desativa loading de zoom baixo após markers serem renderizados
    if (_isLoadingLowZoom) {
      _isLoadingLowZoom = false;
    }
    
    notifyListeners();
  }

  // Realtime updates (same logic as used in GoogleMapView but inside this controller)
  void updateClustersRealtime() {
    _hasPendingClusterUpdate = true;
    if (_isClusterUpdateRunning) return;
    if (_realtimeClusterDebounce?.isActive ?? false) return;
    
    _realtimeClusterDebounce = Timer(_realtimeClusterDebounceDuration, () {
      unawaited(_processClusterUpdateQueue());
    });
  }

  Future<void> _processClusterUpdateQueue() async {
    if (_isClusterUpdateRunning) return;
    _isClusterUpdateRunning = true;

    try {
      while (_hasPendingClusterUpdate) {
        _hasPendingClusterUpdate = false;
        await _performClusterUpdate();
      }
    } catch (e) {
      debugPrint('⚠️ Erro na fila de cluster update: $e');
    } finally {
      _isClusterUpdateRunning = false;
    }
  }

  Future<void> _performClusterUpdate() async {
    final manager = _clusterManager;
    if (manager == null) return;
    
    try {
      await manager.updateClusters(zoomLevel: _currentZoom);
    } catch (e) {
      return;
    }
    
    if (_clusterManager != manager) return;
    
    final clustered = Set<Marker>.of(manager.getClusteredMarkers());
    
    final nextClusteredStyled = <Marker>{};
    for (final m in clustered) {
      final rawId = m.markerId.value;
      
      if (rawId.startsWith('event_')) {
        final eventId = rawId.replaceFirst('event_', '');
        final event = _eventById[eventId];
        if (event != null) {
          nextClusteredStyled.add(
            m.copyWith(
              onTapParam: () => onMarkerTap(event),
            ),
          );
        } else {
          nextClusteredStyled.add(m);
        }
        continue;
      }

      if (!rawId.startsWith('cluster_')) {
        nextClusteredStyled.add(m);
        continue;
      }

      int count = _extractClusterCount(m);
      final clusterPosition = m.position;
      final clusterEmoji = assets.pickClusterEmoji(clusterPosition, _eventById);
      final clusterPin = await assets.getClusterPinWithEmoji(count, clusterEmoji);

      nextClusteredStyled.add(
        m.copyWith(
          iconParam: clusterPin,
          anchorParam: const Offset(0.5, 1.0),
          zIndexParam: 1000,
          infoWindowParam: InfoWindow.noText,
          onTapParam: () => onClusterTap(clusterPosition, count),
        ),
      );
    }

    final nextAvatarOverlays = <Marker>{};
    final updatedEmojiMarkers2 = <Marker>{};
    final markersToRemove2 = <Marker>{};
    int avatarZIndexCounter2 = 0;
    
    for (final m in nextClusteredStyled) {
      final rawId = m.markerId.value;
      if (!rawId.startsWith('event_')) continue;
      final eventId = rawId.replaceFirst('event_', '');
      final event = _eventById[eventId];
      if (event == null) continue;

      final baseZIndex = 100 + (avatarZIndexCounter2 * 2);
      avatarZIndexCounter2++;

      markersToRemove2.add(m);
      updatedEmojiMarkers2.add(m.copyWith(zIndexParam: baseZIndex.toDouble()));

      final avatarPin = await assets.getAvatarPinBestEffort(event);

      nextAvatarOverlays.add(
        Marker(
          markerId: MarkerId('event_avatar_$eventId'),
          position: m.position,
          icon: avatarPin,
          anchor: const Offset(0.5, 0.80),
          onTap: () => onMarkerTap(event),
          zIndex: (baseZIndex + 1).toDouble(),
        ),
      );
    }

    nextClusteredStyled.removeAll(markersToRemove2);
    nextClusteredStyled.addAll(updatedEmojiMarkers2);

    _avatarOverlayMarkers = nextAvatarOverlays;
    _markers = nextClusteredStyled;
    notifyListeners();
  }
}
