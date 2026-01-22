import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/core/models/user.dart' as app_user;
import 'package:partiu/core/services/block_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:partiu/features/home/data/services/people_map_discovery_service.dart';
import 'package:partiu/features/home/presentation/services/google_event_marker_service.dart';
import 'package:partiu/features/home/presentation/services/map_navigation_service.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/screens/chat/chat_screen_refactored.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/widgets/confetti_celebration.dart';

/// Widget de mapa Google Maps limpo e performático
/// 
/// Responsabilidades:
/// - Renderizar o Google Map
/// - Exibir localização do usuário
/// - Exibir markers com clustering inteligente baseado em zoom
/// - Controlar câmera
/// 
/// Clustering:
/// - Zoom > 10: Apenas markers individuais (SEM clustering)
/// - Zoom <= 10: Clustering ativado (agrupa eventos próximos)
/// - Ao tocar em cluster: zoom in para expandir
/// 
/// Toda lógica de negócio foi extraída para:
/// - MapViewModel (orquestração)
/// - EventMarkerService (markers + clustering)
/// - UserLocationService (localização)
/// - AvatarService (avatares)
/// - MarkerClusterService (algoritmo de clustering)
class GoogleMapView extends StatefulWidget {
  final MapViewModel viewModel;
  final VoidCallback? onPlatformMapCreated;

  const GoogleMapView({
    super.key,
    required this.viewModel,
    this.onPlatformMapCreated,
  });

  @override
  State<GoogleMapView> createState() => GoogleMapViewState();
}

class GoogleMapViewState extends State<GoogleMapView> {
  /// Controller do mapa Google Maps
  GoogleMapController? _mapController;
  
  /// Serviço para gerar markers customizados (com clustering)
  final GoogleEventMarkerService _markerService = GoogleEventMarkerService();

  /// Serviço para contagem de pessoas por bounding box
  final PeopleMapDiscoveryService _peopleCountService = PeopleMapDiscoveryService();
  
  /// Markers atuais do mapa (clusterizados)
  Set<Marker> _markers = {};

  // ===== Debug / observabilidade =====
  // Deixe true enquanto estivermos caçando o bug de “0 clusters/0 markers”.
  static const bool _debugMarkers = true;
  static const int _debugSampleEvents = 5;

  void _dlog(String message) {
    if (!_debugMarkers) return;
    debugPrint(message);
  }

  /// Token incremental para garantir que apenas o último rebuild assíncrono
  /// aplica o resultado (evita corrida onde um rebuild “velho” sobrescreve o novo).
  int _renderSeq = 0;

  /// Pipeline único de render: qualquer trigger chama `scheduleRender()`.
  ///
  /// - Cancela render agendado anterior
  /// - Executa em debounce curto
  /// - Usa snapshot + token dentro de `_rebuildClusteredMarkers()`
  Timer? _renderDebounce;
  static const Duration _renderDebounceDuration = Duration(milliseconds: 80);

  /// Se um render foi solicitado enquanto `_isCameraMoving`/`_isAnimating` estava true,
  /// guardamos pendência para executar assim que a câmera ficar idle.
  bool _renderPendingAfterMove = false;
  
  /// Estilo customizado do mapa carregado de assets
  String? _mapStyle;
  
  /// Zoom atual do mapa (usado para clustering)
  double _currentZoom = 12.0;

  /// Último bounds visível (expandido com buffer) usado para filtrar markers no viewport.
  LatLngBounds? _lastExpandedVisibleBounds;

  /// Cache rápido para mapear eventId -> EventModel no viewport (evita firstWhere em lista grande).
  final Map<String, EventModel> _eventsInViewportById = <String, EventModel>{};

  /// Última versão do dataset (MapViewModel.eventsVersion) que foi usada
  /// para renderizar markers.
  int _lastRenderedEventsVersion = -1;

  // Deve estar alinhado com MarkerClusterService._maxClusterZoom
  static const double _clusterZoomThreshold = 11.0;

  // Ao tocar num cluster pequeno (2-3 itens), queremos garantir que ele realmente
  // expanda em markers individuais. Para isso, forçamos um zoom mínimo acima do
  // limiar de clustering.
  static const int _smallClusterMaxSize = 3;
  static const double _clusterExpandMinZoom = 14.5;

  // No cold start, renderizar TODOS os eventos no viewport pode atrasar o
  // primeiro paint (principalmente se houver muitos). Para a UX, é melhor
  // mostrar um subconjunto rapidamente e depois completar.
  static const int _initialViewportRenderCap = 60;
  bool _didProgressiveFirstRender = false;
  
  /// Flag para evitar rebuilds durante animação de câmera
  bool _isAnimating = false;

  /// Flag para evitar rebuild pesado enquanto o usuário move o mapa
  bool _isCameraMoving = false;

  /// Controla o fluxo de expansão de cluster para manter coerência visual.
  /// Quando true, o próximo onCameraIdle não deve refetch/rebuild (é apenas o término
  /// da animação iniciada por um tap em cluster).
  bool _isExpandingCluster = false;

  /// Guarda o último cluster tocado (pelo conjunto de ids) para permitir “tap 2 abre lista”.
  Set<String>? _lastTappedClusterEventIds;
  DateTime? _lastClusterTapAt;
  static const Duration _doubleTapClusterWindow = Duration(milliseconds: 900);

  Timer? _cameraIdleDebounce;
  static const Duration _cameraIdleDebounceDuration = Duration(milliseconds: 200);

  VoidCallback? _avatarBitmapsListener;
  Timer? _avatarBitmapsDebounce;
  static const Duration _avatarBitmapsDebounceDuration = Duration(milliseconds: 150);

  static const double _viewportBoundsBufferFactor = 1.3;

  MapBounds? _lastRequestedQueryBounds;
  DateTime _lastRequestedQueryAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minIntervalBetweenContainedBoundsQueries = Duration(seconds: 2);

  bool _isBoundsContained(MapBounds inner, MapBounds outer) {
    return inner.minLat >= outer.minLat &&
        inner.maxLat <= outer.maxLat &&
        inner.minLng >= outer.minLng &&
        inner.maxLng <= outer.maxLng;
  }

  LatLngBounds _expandBounds(LatLngBounds bounds, double factor) {
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

  bool _boundsContains(LatLngBounds bounds, double lat, double lng) {
    final sw = bounds.southwest;
    final ne = bounds.northeast;

    final minLat = sw.latitude < ne.latitude ? sw.latitude : ne.latitude;
    final maxLat = sw.latitude < ne.latitude ? ne.latitude : sw.latitude;
    final withinLat = lat >= minLat && lat <= maxLat;

    // Normalmente (Brasil) não cruza antimeridiano; ainda assim, trata caso sw.lng > ne.lng.
    final swLng = sw.longitude;
    final neLng = ne.longitude;
    final withinLng = swLng <= neLng ? (lng >= swLng && lng <= neLng) : (lng >= swLng || lng <= neLng);

    return withinLat && withinLng;
  }

  /// Método público para centralizar no usuário
  void centerOnUser() {
    _moveCameraToUserLocation();
  }

  /// Preload leve de clusters via "zoom out" seguido de retorno ao zoom anterior.
  ///
  /// Objetivo: aquecer a criação de clusters/bitmaps logo após o primeiro frame,
  /// sem bloquear a UI nem mexer nos dados (não refetch).
  ///
  /// - Não faz nada se o mapa ainda não foi criado.
  /// - Evita disparar `loadEventsInBounds` durante a animação (marca `_isExpandingCluster`).
  /// - No final, faz um rebuild dos markers para o zoom/bounds atual.
  Future<void> preloadZoomOutClusters({
    double targetZoom = 6.0,
    Duration settleDelay = const Duration(milliseconds: 220),
  }) async {
    if (!mounted) return;
    final controller = _mapController;
    if (controller == null) return;

    // Se ainda não temos eventos, não há o que clusterizar.
    if (widget.viewModel.events.isEmpty) return;

    // Evitar competir com interação do usuário.
    if (_isCameraMoving || _isAnimating) return;

    try {
      // ⚠️ Importante: mexer na câmera (zoom out) no cold start gera um bounds
      // ENORME e dispara MapDiscoveryService para o "mundo todo", que é exatamente
      // o que está causando os ~7s + múltiplos refetchs.
      //
      // Aqui o objetivo é só "aquecer" o clustering/bitmaps com o dataset atual.
      // Então: apenas rebuild dos markers em um zoom baixo (clusters), sem animar.
      final previousZoom = _currentZoom;
      final warmZoom = targetZoom;

      _isAnimating = true;
      _isExpandingCluster = true;

      _currentZoom = warmZoom;
  scheduleRender();

      _currentZoom = previousZoom;
  scheduleRender();
    } catch (_) {
      // Best-effort.
    } finally {
      _isAnimating = false;
      _isExpandingCluster = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    widget.viewModel.onMarkerTap = (event) => _onMarkerTap(event);
    MapNavigationService.instance.registerMapHandler(
      (eventId, {showConfetti = false}) {
        _handleEventNavigation(eventId, showConfetti: showConfetti);
      },
    );
    widget.viewModel.addListener(_onEventsChanged);

    // Quando um avatar termina de carregar em background, o Marker do Google Maps
    // NÃO se atualiza sozinho: precisamos reconstruir o Set<Marker> para trocar o ícone.
    _avatarBitmapsListener = () {
      if (!mounted || _isAnimating || _isCameraMoving) return;
      if (widget.viewModel.events.isEmpty) return;

      _avatarBitmapsDebounce?.cancel();
      _avatarBitmapsDebounce = Timer(_avatarBitmapsDebounceDuration, () {
        if (!mounted || _isAnimating || _isCameraMoving) return;
  scheduleRender();
      });
    };
    _markerService.avatarBitmapsVersion.addListener(_avatarBitmapsListener!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  /// Carrega o estilo do mapa de assets
  Future<void> _loadMapStyle() async {
    try {
      final style = await rootBundle.loadString('assets/map_styles/clean.json');
      if (!mounted) return;
      setState(() {
        _mapStyle = style;
      });
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar estilo do mapa: $e');
    }
  }
  
  /// Callback quando eventos mudarem
  void _onEventsChanged() async {
    if (!mounted || _isAnimating) return;
    scheduleRender();
  }

  /// Agenda um rebuild de markers num pipeline único.
  void scheduleRender() {
    if (!mounted) return;
    if (_mapController == null) return;

    // Se estamos em movimento/animação, não tentamos render agora (evita churn),
    // mas garante que o próximo idle execute um render obrigatório.
    if (_isAnimating || _isCameraMoving) {
      _renderPendingAfterMove = true;
      return;
    }

    _renderDebounce?.cancel();
    _renderDebounce = Timer(_renderDebounceDuration, () {
      if (!mounted) return;
      if (_isAnimating || _isCameraMoving) return;
      unawaited(_rebuildClusteredMarkers());
    });
  }

  /// Reconstrói markers com clustering baseado no zoom atual
  Future<void> _rebuildClusteredMarkers() async {
    final int seq = ++_renderSeq;

    final rebuildStartedAt = DateTime.now();
    _dlog(
      '🧭 [MapRender#$seq] rebuild start '
      '(moving=$_isCameraMoving animating=$_isAnimating zoom=${_currentZoom.toStringAsFixed(2)} '
      'events=${widget.viewModel.events.length} markersCur=${_markers.length})',
    );

    if (!mounted) return;
    if (_isAnimating || _isCameraMoving) return;

  // Snapshot do estado atual para manter consistência durante awaits.
  final allEvents = List<EventModel>.from(widget.viewModel.events);
  final zoomSnapshot = _currentZoom;

    if (allEvents.isEmpty) {
      _dlog('🧭 [MapRender#$seq] abort: allEvents.isEmpty');
      if (_markers.isNotEmpty) {
        setState(() => _markers = {});
      }
      return;
    }

    // Se não temos bounds ainda, tenta obter do mapa
    var bounds = _lastExpandedVisibleBounds;
    if (bounds == null && _mapController != null) {
      try {
        final visibleRegion = await _mapController!.getVisibleRegion();
        bounds = _expandBounds(visibleRegion, _viewportBoundsBufferFactor);
        _lastExpandedVisibleBounds = bounds;

        _dlog(
          '🧭 [MapRender#$seq] fetched bounds from map '
          'SW(${bounds.southwest.latitude.toStringAsFixed(4)},${bounds.southwest.longitude.toStringAsFixed(4)}) '
          'NE(${bounds.northeast.latitude.toStringAsFixed(4)},${bounds.northeast.longitude.toStringAsFixed(4)})',
        );
      } catch (_) {
        _dlog('🧭 [MapRender#$seq] abort: getVisibleRegion failed (map not ready?)');
        // Mapa ainda não pronto: manter estado consistente (sem markers).
        if (_markers.isNotEmpty) {
          setState(() => _markers = {});
        }
        return;
      }
    }
    
    // Sem bounds = não renderiza (evita renderizar tudo)
    if (bounds == null) {
  _dlog('🧭 [MapRender#$seq] abort: bounds == null (clearing markers)');
      // Sem bounds: manter estado consistente (sem markers), para evitar ficar
      // preso com markers stale quando há mudanças de categoria/dataset.
      if (_markers.isNotEmpty) {
        setState(() => _markers = {});
      }
      return;
    }

    // ✅ Importante: em zoom out (clustering), NÃO filtramos por viewport.
    // Em zoom baixo, o viewport pode ser enorme/instável e esse filtro acaba
    // causando "0 markers" mesmo com dataset cheio. O clustering já resolve o custo.
    final shouldFilterByViewport = zoomSnapshot > _clusterZoomThreshold;

    final selectedCategory = widget.viewModel.selectedCategory;
    _dlog(
      '🧭 [MapRender#$seq] snapshot '
      'zoom=$zoomSnapshot (effective clustering=${zoomSnapshot <= _clusterZoomThreshold}) '
      'filterViewport=$shouldFilterByViewport '
      'category=${selectedCategory == null ? 'null' : "\"$selectedCategory\""} '
      'boundsExpand=SW(${bounds.southwest.latitude.toStringAsFixed(3)},${bounds.southwest.longitude.toStringAsFixed(3)}) '
      'NE(${bounds.northeast.latitude.toStringAsFixed(3)},${bounds.northeast.longitude.toStringAsFixed(3)})',
    );

    final categoryFiltered = _applyCategoryFilter(allEvents);
    _dlog('🧭 [MapRender#$seq] categoryFilter: ${allEvents.length} -> ${categoryFiltered.length}');

    int insideBoundsCount = 0;
    if (shouldFilterByViewport) {
      final b = bounds;
      for (final e in categoryFiltered) {
        if (_boundsContains(b, e.lat, e.lng)) insideBoundsCount++;
      }
      _dlog('🧭 [MapRender#$seq] boundsFilter: inside=$insideBoundsCount of ${categoryFiltered.length}');
    }

    final b = bounds;
    var viewportEvents = categoryFiltered
        .where((event) {
          if (!shouldFilterByViewport) return true;
          return _boundsContains(b, event.lat, event.lng);
        })
        .toList(growable: false);

    if (_debugMarkers) {
      final sample = viewportEvents.take(_debugSampleEvents).toList(growable: false);
      for (final e in sample) {
        _dlog(
          '🧭 [MapRender#$seq] sample event id=${e.id} '
          'lat=${e.lat.toStringAsFixed(5)} lng=${e.lng.toStringAsFixed(5)} '
          'cat=${e.category ?? 'null'}',
        );
      }
    }

    // Progressive render (apenas no primeiro paint com dados): mostra algo rápido.
    if (!_didProgressiveFirstRender && viewportEvents.length > _initialViewportRenderCap) {
      viewportEvents = viewportEvents.take(_initialViewportRenderCap).toList(growable: false);
    }

    if (viewportEvents.isEmpty) {
      _dlog(
        '🧭 [MapRender#$seq] abort: viewportEvents.isEmpty '
        '(filterViewport=$shouldFilterByViewport, categoryFiltered=${categoryFiltered.length})',
      );
      // ✅ Estado consistente: se não há eventos visíveis, limpamos markers.
      // Isso evita ficar preso com markers antigos quando uma mudança de bounds/
      // categoria deixa o viewport vazio por um frame.
      if (_markers.isNotEmpty) {
        setState(() => _markers = {});
      }
      return;
    }

    // ✅ Pré-carrega avatares do viewport ANTES de construir markers.
    // Aguardar com timeout curto para que markers já nasçam com avatar,
    // evitando o "flash" do empty state.
    // Se timeout estourar, continuamos (best-effort) - avatares virão depois via listener.
    try {
      await _markerService
          .preloadAvatarPinsForEvents(viewportEvents, maxUsers: 30)
          .timeout(const Duration(milliseconds: 800));
      _dlog('🧭 [MapRender#$seq] avatars preloaded (within timeout)');
    } catch (_) {
      _dlog('🧭 [MapRender#$seq] avatars preload timeout/error - continuing with defaults');
    }

    // Verificar se ainda somos o render atual após o await
    if (!mounted || seq != _renderSeq) {
      _dlog('🧭 [MapRender#$seq] discard after avatar preload (currentSeq=$_renderSeq)');
      return;
    }
    
  // 🎯 Importante para UX: no cold start, forçamos clustering mesmo em zoom alto
  // para aparecer "algo" rapidamente.
  //
  // Porém, durante a expansão de cluster (tap), precisamos usar o zoom REAL para
  // desfazer o cluster. Então o clamp só acontece no primeiro paint.
  final shouldForceClusters = !_didProgressiveFirstRender && !_isExpandingCluster;
  final effectiveZoom = shouldForceClusters
    ? zoomSnapshot.clamp(0.0, _clusterZoomThreshold)
    : zoomSnapshot;

    final markersBuildStart = DateTime.now();
    _dlog(
      '🧭 [MapRender#$seq] markerService.buildClusteredMarkers '
      'inputEvents=${viewportEvents.length} zoomEffective=${effectiveZoom.toStringAsFixed(2)}',
    );

    final markers = await _markerService.buildClusteredMarkers(
      viewportEvents,
      zoom: effectiveZoom,
      visibleBounds: bounds,
      onSingleTap: (eventId) {
        final event = _eventsInViewportById[eventId] ??
            widget.viewModel.events.firstWhere((e) => e.id == eventId);
        _onMarkerTap(event);
      },
      onClusterTap: (eventsInCluster) => _onClusterTap(eventsInCluster),
    );

    _eventsInViewportById
      ..clear()
      ..addEntries(viewportEvents.map((e) => MapEntry(e.id, e)));

    _dlog(
      '🧭 [MapRender#$seq] markerService result markers=${markers.length} '
      '(took ${DateTime.now().difference(markersBuildStart).inMilliseconds}ms)',
    );
    
  if (!mounted || seq != _renderSeq) {
      // Descarta resultado atrasado (um rebuild mais novo já foi disparado).
      _dlog('🧭 [MapRender#$seq] discard: stale result (currentSeq=$_renderSeq)');
      return;
    }

    if (mounted) {
      setState(() => _markers = markers);
    }

    _dlog(
      '🧭 [MapRender#$seq] applied markers=${markers.length} '
      'totalTook=${DateTime.now().difference(rebuildStartedAt).inMilliseconds}ms',
    );

  // Marca que o render aplicou a versão atual do dataset.
  _lastRenderedEventsVersion = widget.viewModel.eventsVersion.value;

    // Depois do primeiro render com cap, agenda completar o render com tudo.
    if (!_didProgressiveFirstRender) {
      _didProgressiveFirstRender = true;
      if (widget.viewModel.events.isNotEmpty) {
        // Próximo frame, completa com todos os eventos (best-effort).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          scheduleRender();
        });
      }
    }
  }

  List<EventModel> _applyCategoryFilter(List<EventModel> events) {
    final selected = widget.viewModel.selectedCategory;
    if (selected == null || selected.trim().isEmpty) return events;

    final normalized = selected.trim();
    return events.where((event) {
      final category = event.category;
      if (category == null) return false;
      return category.trim() == normalized;
    }).toList(growable: false);
  }

  /// Callback quando cluster é tocado
  /// 
  /// Comportamento:
  /// - Calcula bounds que enquadra todos os eventos do cluster
  /// - Anima câmera para mostrar todos os markers no frame
  /// - Mantém coerência visual evitando refetch/rebuild no 1º onCameraIdle após animação
  void _onClusterTap(List<EventModel> eventsInCluster) async {
    if (_mapController == null || eventsInCluster.isEmpty) return;

    // Tap 2 no mesmo cluster: abre lista dos eventos (sem depender de zoom/expand).
    final idsNow = eventsInCluster.map((e) => e.id).toSet();
    final now = DateTime.now();
    final withinWindow = _lastClusterTapAt != null && now.difference(_lastClusterTapAt!) <= _doubleTapClusterWindow;
    final isSameCluster = _lastTappedClusterEventIds != null && setEquals(_lastTappedClusterEventIds, idsNow);
    if (withinWindow && isSameCluster) {
      _lastClusterTapAt = now;
      _showClusterEventsSheet(eventsInCluster);
      return;
    }

    // ✅ Pré-carrega avatares do cluster ANTES de animar.
    // Aguardamos com timeout curto para que markers individuais já tenham avatar.
    try {
      await _markerService
          .preloadAvatarPinsForEvents(eventsInCluster, maxUsers: 30)
          .timeout(const Duration(milliseconds: 600));
    } catch (_) {
      // Best-effort: se timeout, continuamos (avatares virão depois via listener)
    }
    
  // Mantém referência do último cluster tocado (tap 2 abre lista)
  _lastTappedClusterEventIds = idsNow;
  _lastClusterTapAt = now;
    
    // 🎯 Calcular bounds que enquadra todos os eventos
    double minLat = eventsInCluster.first.lat;
    double maxLat = eventsInCluster.first.lat;
    double minLng = eventsInCluster.first.lng;
    double maxLng = eventsInCluster.first.lng;
    
    for (final e in eventsInCluster) {
      if (e.lat < minLat) minLat = e.lat;
      if (e.lat > maxLat) maxLat = e.lat;
      if (e.lng < minLng) minLng = e.lng;
      if (e.lng > maxLng) maxLng = e.lng;
    }
    
    // Marcar que está animando para evitar rebuilds intermediários
    _isAnimating = true;

    // Marcar que estamos expandindo cluster: o próximo onCameraIdle não deve refetch/rebuild.
    _isExpandingCluster = true;
    
    try {
      // Se todos os eventos estão no mesmo ponto (ou muito próximos), fazer zoom fixo
      final latDiff = maxLat - minLat;
      final lngDiff = maxLng - minLng;

      final isSmallCluster = eventsInCluster.length <= _smallClusterMaxSize;
      
      if (latDiff < 0.0001 && lngDiff < 0.0001) {
        // Eventos sobrepostos: zoom fixo no centro
        final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
        final targetZoom = isSmallCluster
            ? (_currentZoom + 3.0).clamp(_clusterExpandMinZoom, 18.0)
            : (_currentZoom + 2.0).clamp(14.0, 18.0);
        
        debugPrint(
          '🔍 Expandindo cluster (sobrepostos): ${eventsInCluster.length} eventos, '
          'zoom ${_currentZoom.toStringAsFixed(1)} -> ${targetZoom.toStringAsFixed(1)}',
        );
        
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(center, targetZoom),
        );
        
  _currentZoom = targetZoom;
      } else {
        // Eventos espalhados: usar bounds para enquadrar todos
        final bounds = LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        );
        
        debugPrint(
          '🔍 Expandindo cluster: ${eventsInCluster.length} eventos, '
          'bounds: SW(${minLat.toStringAsFixed(4)}, ${minLng.toStringAsFixed(4)}) '
          'NE(${maxLat.toStringAsFixed(4)}, ${maxLng.toStringAsFixed(4)})',
        );
        
        // Padding de 80px para não colar nos cantos
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 80.0),
        );

        // Para clusters pequenos, o bounds pode manter zoom baixo e o cluster continua.
        // Garantimos um zoom acima do limiar para realmente separar em markers.
        if (isSmallCluster) {
          final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              center,
              (_currentZoom + 3.0).clamp(_clusterExpandMinZoom, 18.0),
            ),
          );
        }

        // Atualizar zoom atual após animação (valor real)
        _currentZoom = await _mapController!.getZoomLevel();
      }

      // 🧩 Importante: em alguns devices/timings, o onCameraIdle pode demorar ou
      // não disparar do jeito esperado para "desfazer" cluster pequeno.
      // Então fazemos um rebuild best-effort logo após a animação.
      if (mounted) {
  scheduleRender();
      }
      
    } finally {
      _isAnimating = false;
    }
    
    // O onCameraIdle vai disparar automaticamente e fazer o rebuild dos markers
  }

  /// Callback quando o mapa é criado
  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;

    // Sinaliza que o PlatformView do mapa já foi criado (evita tela branca sem feedback)
    widget.onPlatformMapCreated?.call();
    
    // Mover câmera para localização inicial (já carregada)
    if (widget.viewModel.lastLocation != null) {
      await _moveCameraTo(
        widget.viewModel.lastLocation!.latitude,
        widget.viewModel.lastLocation!.longitude,
        zoom: 12.0, // Visão regional para ver mais eventos
        animate: false,
      );
    } else {
      await _moveCameraToUserLocation(animate: false);
    }

    // Fazer busca inicial de eventos na região visível
    // Isso garante que o drawer tenha dados logo ao abrir
    await _triggerInitialEventSearch();
  }

  /// Callback quando a câmera para de se mover
  /// 
  /// Responsável por:
  /// 1. Capturar bounding box visível
  /// 2. Buscar eventos na região
  /// 3. Recalcular clusters se zoom mudou
  Future<void> _onCameraIdle() async {
    _isCameraMoving = false;

    if (_mapController == null || _isAnimating) return;

    // Se acabamos de animar por causa de um tap em cluster, não tratamos como navegação normal.
    // Isso evita refetch/rebuild que mistura eventos “novos” e quebra a percepção do cluster.
    if (_isExpandingCluster) {
      _isExpandingCluster = false;

      // ✅ Boa prática: ao finalizar a animação do cluster, garantir que estamos
      // reconstruindo com zoom/bounds REAIS do frame atual.
      try {
        final newZoom = await _mapController!.getZoomLevel();
        _currentZoom = newZoom;

        final visibleRegion = await _mapController!.getVisibleRegion();
        _lastExpandedVisibleBounds = _expandBounds(visibleRegion, _viewportBoundsBufferFactor);
      } catch (_) {
        // Best-effort.
      }

      // Ainda assim, atualiza os markers para o novo zoom/bounds com o dataset já carregado.
      // Isso dá a sensação correta de “expandiu o cluster” sem poluir com novos eventos.
      _cameraIdleDebounce?.cancel();
      _cameraIdleDebounce = Timer(_cameraIdleDebounceDuration, () {
        if (!mounted) return;
        // Sempre drena um render pendente após movimento/animação.
        if (_renderPendingAfterMove) {
          _renderPendingAfterMove = false;
        }
        scheduleRender();
      });
      return;
    }

    // Se algum listener pediu render durante o pan, garantimos um render no idle,
    // mesmo que zoom não tenha mudado.
    if (_renderPendingAfterMove) {
      _renderPendingAfterMove = false;
      scheduleRender();
    }

    _cameraIdleDebounce?.cancel();
    _cameraIdleDebounce = Timer(_cameraIdleDebounceDuration, () {
      if (!mounted) return;
      unawaited(_handleCameraIdleDebounced());
    });
  }

  Future<void> _handleCameraIdleDebounced() async {
    if (_mapController == null || _isAnimating) return;

    try {
      // Obter zoom atual
      final previousZoom = _currentZoom;
      final newZoom = await _mapController!.getZoomLevel();
      final zoomChanged = (newZoom - previousZoom).abs() > 0.5;

      // Recalcular quando cruzar o limiar de clustering, mesmo se a variação for pequena
      final crossedClusterThreshold =
          (previousZoom <= _clusterZoomThreshold && newZoom > _clusterZoomThreshold) ||
          (previousZoom > _clusterZoomThreshold && newZoom <= _clusterZoomThreshold);

      // Atualizar zoom atual
      _currentZoom = newZoom;

      final visibleRegion = await _mapController!.getVisibleRegion();
      final expandedBounds = _expandBounds(visibleRegion, _viewportBoundsBufferFactor);
      _lastExpandedVisibleBounds = expandedBounds;

      // Fonte de verdade para drawer/chips: bounds VISÍVEL (frame).
      // O bounds expandido é usado apenas para reduzir churn de render de markers.
      final queryBounds = MapBounds.fromLatLngBounds(visibleRegion);
      // Pessoas devem ser determinadas pelo que está DENTRO do frame.
      final peopleBounds = MapBounds.fromLatLngBounds(visibleRegion);
      
      debugPrint('📍 GoogleMapView: Câmera parou (zoom: ${newZoom.toStringAsFixed(1)}, mudou: $zoomChanged)');
      
      // Recalcular clusters se zoom mudou significativamente OU se cruzou o limiar de clustering
      if ((zoomChanged || crossedClusterThreshold) && widget.viewModel.events.isNotEmpty) {
        debugPrint('🔄 GoogleMapView: Zoom mudou - recalculando clusters');
  scheduleRender();
      }
      
      // Disparar busca de eventos no bounding box
      final now = DateTime.now();
      final withinPrevious = _lastRequestedQueryBounds != null &&
          _isBoundsContained(queryBounds, _lastRequestedQueryBounds!);
      final tooSoon = now.difference(_lastRequestedQueryAt) < _minIntervalBetweenContainedBoundsQueries;

      if (withinPrevious && tooSoon) {
        debugPrint('📦 GoogleMapView: Bounds contido, pulando refetch (janela curta)');
      } else {
        _lastRequestedQueryBounds = queryBounds;
        _lastRequestedQueryAt = now;
  await widget.viewModel.loadEventsInBounds(queryBounds);

  // ✅ Correção de confiabilidade:
  // Se o dataset chegou enquanto o usuário estava em pan (_isCameraMoving == true),
  // o listener de eventos pode ter tentado rebuild e abortado.
  // Em um pan sem zoom, zoomChanged/crossedThreshold = false, então o rebuild
  // não aconteceria e os markers podem ficar "presos" no estado anterior.
  scheduleRender();
      }

      // Fallback de confiabilidade: mesmo num pan sem mudança de zoom,
      // se o dataset mudou desde o último render, garantimos um render no idle.
      final currentVersion = widget.viewModel.eventsVersion.value;
      if (currentVersion != _lastRenderedEventsVersion) {
        _lastRenderedEventsVersion = currentVersion;
        scheduleRender();
      }

      // Atualizar contagem/lista de pessoas SOMENTE quando o zoom está próximo
      // (clusters desfeitos). Em zoom out (clustering), isso vira custo alto e
      // não representa a UI (região é grande demais).
      //
      // Importante: pessoas usam o bounds VISÍVEL (frame), não o expandido.
      final viewportActive = _currentZoom > _clusterZoomThreshold;
      _peopleCountService.setViewportActive(viewportActive);
      if (viewportActive) {
        await _peopleCountService.loadPeopleCountInBounds(peopleBounds);
      }
    } catch (error) {
      debugPrint('⚠️ GoogleMapView: Erro ao capturar bounding box: $error');
    }
  }

  void _onCameraMoveStarted() {
    _isCameraMoving = true;
    // Evita acumular downloads enquanto o usuário está pan/zoom no mapa.
    UserStore.instance.cancelAvatarPreloads();
  }

  /// Faz busca inicial de eventos na região visível
  /// 
  /// Chamado logo após o mapa ser criado para garantir
  /// que o drawer tenha dados ao abrir pela primeira vez.
  /// Também inicializa o zoom para clustering.
  Future<void> _triggerInitialEventSearch() async {
    if (_mapController == null) return;

    try {
      // Pequeno delay para garantir que o mapa terminou de carregar
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Obter zoom inicial para clustering
      _currentZoom = await _mapController!.getZoomLevel();
      debugPrint('🔲 GoogleMapView: Zoom inicial: ${_currentZoom.toStringAsFixed(1)}');
      
      final visibleRegion = await _mapController!.getVisibleRegion();
      _lastExpandedVisibleBounds = _expandBounds(visibleRegion, _viewportBoundsBufferFactor);
      final bounds = MapBounds.fromLatLngBounds(visibleRegion);
      
      debugPrint('🎯 GoogleMapView: Busca inicial de eventos em $bounds');
      
      // Forçar busca imediata para categorias do drawer (ignora debounce)
      // mas evita duplicar com um refetch que possa ter sido disparado no 1º onCameraIdle.
      final now = DateTime.now();
      final withinPrevious = _lastRequestedQueryBounds != null &&
          _isBoundsContained(bounds, _lastRequestedQueryBounds!);
      final tooSoon = now.difference(_lastRequestedQueryAt) < _minIntervalBetweenContainedBoundsQueries;

      if (!(withinPrevious && tooSoon)) {
        _lastRequestedQueryBounds = bounds;
        _lastRequestedQueryAt = now;
        await widget.viewModel.forceRefreshBounds(bounds);
      }

      // Contagem/lista de pessoas só faz sentido quando zoom está próximo
      // (clusters desfeitos). Em zoom out, não fazemos preload.
      final viewportActive = _currentZoom > _clusterZoomThreshold;
      _peopleCountService.setViewportActive(viewportActive);
      if (viewportActive) {
        await _peopleCountService.forceRefresh(bounds);
      }
      
      // Gerar markers iniciais com clustering
      if (widget.viewModel.events.isNotEmpty) {
        // ✅ Warmup: pré-carrega avatares APENAS do viewport inicial (bounding box visível)
        // para que os markers já nasçam com avatar, sem passar pelo empty state.
        try {
          final eventsByCategory = _applyCategoryFilter(widget.viewModel.events);
          final viewportEvents = eventsByCategory
              .where((event) => _boundsContains(visibleRegion, event.lat, event.lng))
              .toList(growable: false);

          // Warmup inicial: timeout maior (5s) para primeira impressão do usuário.
          if (viewportEvents.isNotEmpty) {
            debugPrint('🔥 GoogleMapView: Warmup inicial de ${viewportEvents.length} avatares...');
            final loaded = await _markerService
                .preloadAvatarPinsForEvents(viewportEvents, maxUsers: 30)
                .timeout(const Duration(seconds: 5));
            debugPrint('✅ GoogleMapView: Warmup concluído ($loaded avatares carregados)');
          }
        } catch (e) {
          debugPrint('⚠️ GoogleMapView: Warmup inicial falhou: $e');
        }
  scheduleRender();
      }
    } catch (error) {
      debugPrint('⚠️ GoogleMapView: Erro na busca inicial: $error');
    }
  }

  /// Move a câmera para a localização do usuário
  Future<void> _moveCameraToUserLocation({bool animate = true}) async {
    final result = await widget.viewModel.getUserLocation();

    // Exibir mensagem de erro se houver
    if (result.hasError && mounted) {
      _showMessage(result.errorMessage!);
    }

    // Mover câmera
    await _moveCameraTo(
      result.location.latitude,
      result.location.longitude,
      zoom: 12.0, // Visão regional para ver mais eventos
      animate: animate,
    );
  }

  /// Move a câmera para uma coordenada específica
  Future<void> _moveCameraTo(
    double lat,
    double lng, {
    double zoom = 14.0,
    bool animate = true,
  }) async {
    if (_mapController == null) return;

    try {
      final update = CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(lat, lng),
          zoom: zoom,
        ),
      );

      if (animate) {
        await _mapController!.animateCamera(update);
      } else {
        await _mapController!.moveCamera(update);
      }
    } catch (e) {
      // Falha silenciosa - câmera continua onde está
    }
  }

  /// Exibe mensagem para o usuário
  void _showMessage(String message) {
    if (!mounted) return;

    ToastService.showInfo(message: message);
  }

  void _showClusterEventsSheet(List<EventModel> events) {
    if (!mounted) return;

    final sorted = [...events]
      ..sort((a, b) => (a.title).toLowerCase().compareTo((b.title).toLowerCase()));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 500),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Eventos neste cluster (${sorted.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = sorted[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text(e.emoji, style: const TextStyle(fontSize: 20)),
                        title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: e.category == null
                            ? null
                            : Text(e.category!, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.of(context).pop();
                          unawaited(_onMarkerTap(e));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Handler de navegação chamado pelo MapNavigationService
  /// 
  /// Responsável por:
  /// 1. Encontrar o evento na lista de eventos carregados
  /// 2. Mover câmera para o evento
  /// 3. Abrir o EventCard
  /// 
  /// [showConfetti] - Se true, mostra confetti ao abrir o card (usado após criar evento)
  void _handleEventNavigation(String eventId, {bool showConfetti = false}) async {
    debugPrint('🗺️ [GoogleMapView] Navegando para evento: $eventId (confetti: $showConfetti)');
    
    if (!mounted) return;
    
    // Buscar evento na lista de eventos carregados
    final event = widget.viewModel.events.firstWhere(
      (e) => e.id == eventId,
      orElse: () {
        debugPrint('⚠️ [GoogleMapView] Evento não encontrado na lista: $eventId');
        // Se não encontrou, forçar refresh dos bounds atuais
        if (_lastRequestedQueryBounds != null) {
          widget.viewModel.forceRefreshBounds(_lastRequestedQueryBounds!);
        } else {
          widget.viewModel.loadNearbyEvents();
        }
        throw Exception('Evento não encontrado');
      },
    );
    
    debugPrint('✅ [GoogleMapView] Evento encontrado: ${event.title}');
    
    // Mover câmera para o evento
    if (_mapController != null) {
      final target = LatLng(event.lat, event.lng);
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(target, 15.0),
      );
      debugPrint('📍 [GoogleMapView] Câmera movida para: ${event.title}');
    }
    
    // Aguardar animação da câmera
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted) return;
    
    // Abrir EventCard (com confetti se for evento recém-criado)
    _onMarkerTap(event, showConfetti: showConfetti);
  }

  /// Callback quando usuário toca em um marker
  /// 
  /// [showConfetti] - Se true, mostra confetti ao abrir o card (usado após criar evento)
  Future<void> _onMarkerTap(EventModel event, {bool showConfetti = false}) async {
    debugPrint('🔴🔴🔴 GoogleMapView._onMarkerTap CHAMADO! 🔴🔴🔴');
    debugPrint('🔴 GoogleMapView._onMarkerTap called for: ${event.id} - ${event.title}');
    
    final firestore = FirebaseFirestore.instance;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    // ✅ Pré-carregar TODOS os dados necessários em paralelo
    String? creatorFullName = event.creatorFullName;
    List<Map<String, dynamic>>? participants = event.participants;
    dynamic userApplication = event.userApplication;
    
    try {
      final futures = <Future>[];
      
      // 1. Buscar creatorFullName se necessário
      if (creatorFullName == null && event.createdBy.isNotEmpty) {
        futures.add(
          firestore.collection('Users').doc(event.createdBy).get().then((doc) {
            creatorFullName = doc.data()?['fullName'] as String?;
            debugPrint('✅ creatorFullName: $creatorFullName');
          }),
        );
      }
      
      // 2. Buscar participants se necessário
      if (participants == null || participants!.isEmpty) {
        futures.add(
          firestore
              .collection('EventApplications')
              .where('eventId', isEqualTo: event.id)
              .where('status', whereIn: ['approved', 'autoApproved'])
              .get()
              .then((snapshot) async {
            final userIds = snapshot.docs.map((d) => d.data()['userId'] as String).toList();
            if (userIds.isEmpty) {
              participants = [];
              return;
            }
            
            // Buscar dados dos usuários em batch
            final usersSnapshot = await firestore
                .collection('Users')
                .where(FieldPath.documentId, whereIn: userIds.take(10).toList())
                .get();
            
            participants = usersSnapshot.docs.map((doc) {
              final data = doc.data();
              return {
                'userId': doc.id,
                'photoUrl': data['photoUrl'] as String?,
                'fullName': data['fullName'] as String?,
              };
            }).toList();
            debugPrint('✅ participants: ${participants?.length}');
          }),
        );
      }
      
      // 3. Buscar userApplication se necessário
      if (userApplication == null && currentUserId != null) {
        futures.add(
          firestore
              .collection('EventApplications')
              .where('eventId', isEqualTo: event.id)
              .where('userId', isEqualTo: currentUserId)
              .limit(1)
              .get()
              .then((snapshot) {
            if (snapshot.docs.isNotEmpty) {
              userApplication = snapshot.docs.first;
              debugPrint('✅ userApplication: ${snapshot.docs.first.data()['status']}');
            }
          }),
        );
      }
      
      // Aguardar todas as queries terminarem
      await Future.wait(futures);
      
    } catch (e) {
      debugPrint('⚠️ Erro ao pré-carregar dados: $e');
    }
    
    // Criar evento enriquecido com todos os dados
    final enrichedEvent = event.copyWith(
      creatorFullName: creatorFullName,
      participants: participants,
      // userApplication é tratado separadamente no controller
    );
    
    debugPrint('📦 EventModel enriquecido:');
    debugPrint('   - creatorFullName: ${enrichedEvent.creatorFullName}');
    debugPrint('   - participants: ${enrichedEvent.participants?.length ?? 0}');
    
    // Criar controller com evento enriquecido
    final controller = EventCardController(
      eventId: enrichedEvent.id,
      preloadedEvent: enrichedEvent,
    );
    
    debugPrint('🔴 Controller criado com dados pré-carregados');
    debugPrint('🔴 Abrindo showModalBottomSheet');
    
    // Mostrar confetti se for evento recém-criado
    if (showConfetti) {
      ConfettiOverlay.show(context);
    }
    
    // Abrir o card imediatamente
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(
        maxWidth: 500,
      ),
      builder: (context) => EventCard(
        controller: controller,
        onActionPressed: () async {
          // Capturar o navigator antes de fechar o modal
          final navigator = Navigator.of(context);
          
          // Fechar o card
          navigator.pop();
          
          // Se for o criador ou estiver aprovado, navegar para o chat
          if (controller.isCreator || controller.isApproved) {
            // Usar dados do evento pré-carregado
            final eventName = event.title;
            final emoji = event.emoji;
            
            // Criar User com dados do evento usando campos corretos do SessionManager
            final chatUser = app_user.User.fromDocument({
              'userId': 'event_${event.id}',
              'fullName': eventName,
              'photoUrl': emoji,
              'gender': '',
              'birthDay': 1,
              'birthMonth': 1,
              'birthYear': 2000,
              'jobTitle': '',
              'bio': '',
              'country': '',
              'locality': '',
              'latitude': 0.0,
              'longitude': 0.0,
              'status': 'active',
              'level': '',
              'isVerified': false,
              'registrationDate': DateTime.now().toIso8601String(),
              'lastLoginDate': DateTime.now().toIso8601String(),
              'totalLikes': 0,
              'totalVisits': 0,
              'isOnline': false,
            });
            
            // Verificar se usuário está bloqueado
            final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
            if (currentUserId.isNotEmpty && 
                BlockService().isBlockedCached(currentUserId, event.createdBy)) {
              final i18n = AppLocalizations.of(context);
              ToastService.showWarning(
                message: i18n.translate('user_blocked_cannot_message'),
              );
              return;
            }
            
            // Usar o navigator capturado anteriormente
            navigator.push(
              MaterialPageRoute(
                builder: (context) => ChatScreenRefactored(
                  user: chatUser,
                  isEvent: true,
                  eventId: event.id,
                ),
              ),
            );
          }
        },
      ),
    ).whenComplete(() {
      // Garantir limpeza do controller ao fechar o modal
      controller.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Widget limpo - apenas UI
    // Toda lógica delegada ao ViewModel
    final seededLocation = widget.viewModel.lastLocation;
    final initialTarget = seededLocation ?? const LatLng(-23.5505, -46.6333);

    return GoogleMap(
      style: _mapStyle,
      // Callback de criação
      onMapCreated: _onMapCreated,

      onCameraMoveStarted: _onCameraMoveStarted,

      // Callback quando câmera para (após movimento)
      onCameraIdle: _onCameraIdle,

      // Posição inicial: usa localização persistida (Firestore) quando disponível.
      // Fallback para São Paulo apenas se não houver coords em cache/memória.
      initialCameraPosition: CameraPosition(
        target: initialTarget,
        zoom: seededLocation != null ? 12.0 : 10.0,
      ),
      
      // Permitir zoom de 3.0 (visão continental) até 20.0 (visão de rua detalhada)
      minMaxZoomPreference: const MinMaxZoomPreference(3.0, 20.0),

      // Markers customizados gerados pelo GoogleEventMarkerService
      markers: _markers,

      // Configurações do mapa
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      mapType: MapType.normal,
      compassEnabled: true,
      rotateGesturesEnabled: true,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      tiltGesturesEnabled: false,
    );
  }

  @override
  void dispose() {
    _cameraIdleDebounce?.cancel();
  _renderDebounce?.cancel();
    _avatarBitmapsDebounce?.cancel();
    final listener = _avatarBitmapsListener;
    if (listener != null) {
      _markerService.avatarBitmapsVersion.removeListener(listener);
    }
    widget.viewModel.removeListener(_onEventsChanged);
    MapNavigationService.instance.unregisterMapHandler();
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }
}
