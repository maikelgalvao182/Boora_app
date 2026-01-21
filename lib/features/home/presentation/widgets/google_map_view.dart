import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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
  
  /// Estilo customizado do mapa carregado de assets
  String? _mapStyle;
  
  /// Zoom atual do mapa (usado para clustering)
  double _currentZoom = 12.0;

  /// Último bounds visível (expandido com buffer) usado para filtrar markers no viewport.
  LatLngBounds? _lastExpandedVisibleBounds;

  /// Cache rápido para mapear eventId -> EventModel no viewport (evita firstWhere em lista grande).
  final Map<String, EventModel> _eventsInViewportById = <String, EventModel>{};

  // Deve estar alinhado com MarkerClusterService._maxClusterZoom
  static const double _clusterZoomThreshold = 11.0;
  
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
        unawaited(_rebuildClusteredMarkers());
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
    await _rebuildClusteredMarkers();
  }

  /// Reconstrói markers com clustering baseado no zoom atual
  Future<void> _rebuildClusteredMarkers() async {
    if (!mounted) return;
    if (_isAnimating || _isCameraMoving) return;

    final allEvents = widget.viewModel.events;
    if (allEvents.isEmpty) {
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
      } catch (_) {
        // Mapa ainda não pronto - não renderiza markers
        return;
      }
    }
    
    // Sem bounds = não renderiza (evita renderizar tudo)
    if (bounds == null) return;

    final eventsByCategory = _applyCategoryFilter(allEvents);
    final viewportEvents = eventsByCategory
        .where((event) => _boundsContains(bounds!, event.lat, event.lng))
        .toList(growable: false);

    if (viewportEvents.isEmpty) return;

    // Pré-carrega avatares do viewport em background.
    // Isso aumenta a chance de, ao dar zoom in (desfazer cluster), os avatares já estarem no cache.
    unawaited(
      _markerService.preloadAvatarPinsForEvents(
        viewportEvents,
        maxUsers: 30,
      ),
    );
    
    final markers = await _markerService.buildClusteredMarkers(
      viewportEvents,
      zoom: _currentZoom,
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
    
    if (mounted) {
      setState(() => _markers = markers);
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

    // Warmup em background (não bloqueia a interação)
    _markerService
        .preloadAvatarPinsForEvents(eventsInCluster, maxUsers: 30)
        .timeout(const Duration(milliseconds: 900))
        .catchError((_) => 0);
    
    // Mantém referência do último cluster tocado (pode ser útil para ajustes futuros)
    _lastTappedClusterEventIds = eventsInCluster.map((e) => e.id).toSet();
    
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
      
      if (latDiff < 0.0001 && lngDiff < 0.0001) {
        // Eventos sobrepostos: zoom fixo no centro
        final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
        final targetZoom = (_currentZoom + 2.0).clamp(14.0, 18.0);
        
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
        
        // Atualizar zoom atual após animação
        final newPosition = await _mapController!.getVisibleRegion();
        // Estimar zoom baseado no tamanho do bounds (aproximação)
        _currentZoom = (_currentZoom + 2.0).clamp(12.0, 18.0);
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

      // Ainda assim, atualiza os markers para o novo zoom/bounds com o dataset já carregado.
      // Isso dá a sensação correta de “expandiu o cluster” sem poluir com novos eventos.
      _cameraIdleDebounce?.cancel();
      _cameraIdleDebounce = Timer(_cameraIdleDebounceDuration, () {
        if (!mounted) return;
        unawaited(_rebuildClusteredMarkers());
      });
      return;
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
        await _rebuildClusteredMarkers();
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
        await _rebuildClusteredMarkers();
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
