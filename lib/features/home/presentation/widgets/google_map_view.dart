import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/features/home/presentation/services/event_card_action_warmup_service.dart';
import 'package:partiu/features/home/presentation/services/participant_avatar_warmup_service.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/event_card_presenter.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/map_bounds_controller.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/map_camera_controller.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/map_navigation_handler.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/map_people_controller.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/map_render_controller.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/marker_assets.dart';
import 'package:partiu/shared/stores/user_store.dart';

/// Widget de mapa Google Maps limpo e performático (Refatorado)
///
/// Arquitetura:
/// - GoogleMapView (UI e Wiring)
/// - MapRenderController (Markers, Clusters)
/// - MapBoundsController (Prefetch, Visible Region)
/// - MapCameraController (Movimento, Zoom)
/// - MapNavigationHandler (Deep Links, Eventos)
/// - MapPeopleController (Contagem de pessoas)
/// - EventCardPresenter (Modal de evento)
/// - MapMarkerAssets (Bitmaps)
class GoogleMapView extends StatefulWidget {
  final MapViewModel viewModel;
  final VoidCallback? onPlatformMapCreated;
  final VoidCallback? onFirstRenderApplied;

  const GoogleMapView({
    super.key,
    required this.viewModel,
    this.onPlatformMapCreated,
    this.onFirstRenderApplied,
  });

  @override
  State<GoogleMapView> createState() => GoogleMapViewState();
}

class GoogleMapViewState extends State<GoogleMapView> with TickerProviderStateMixin {
  // Controllers
  late final MapMarkerAssets _markerAssets;
  late final EventCardPresenter _eventPresenter;
  late final MapPeopleController _peopleController;
  late final MapBoundsController _boundsController;
  late final MapCameraController _cameraController;
  late final ParticipantAvatarWarmupService _participantWarmupService;
  late final EventCardActionWarmupService _actionWarmupService;
  MapRenderController? _renderController;
  MapNavigationHandler? _navigationHandler;

  GoogleMapController? _mapController;
  String? _mapStyle;
  double _currentZoom = 12.0;

  // Debounces
  Timer? _cameraIdleDebounce;
  Timer? _warmupDebounce;
  // Aumentado de 200ms para 600ms para evitar queries durante micro-movimentações
  static const Duration _cameraIdleDebounceDuration = Duration(milliseconds: 600);
  static const Duration _warmupDebounceDuration = Duration(milliseconds: 800);
  
  // Streams
  StreamSubscription<String>? _removalSub;
  
  /// Expõe o estado de loading para zoom baixo (usado pelo DiscoverScreen)
  bool get isLoadingLowZoom => _renderController?.isLoadingLowZoom ?? false;
  
  /// Expõe o render controller como Listenable para UI externa
  Listenable? get renderControllerListenable => _renderController;

  @override
  void initState() {
    super.initState();
    debugPrint('🧨 [GoogleMapView] initState - vou registrar services');
    debugPrint('🗺️ [GoogleMapView] viewModel hash=${identityHashCode(widget.viewModel)}');
    _loadMapStyle();
    _initializeControllers();

    // Register services initially - IMEDIATAMENTE (sem PostFrameCallback)
    // para garantir que o handler capture pendências do MapNavigationService
    // mesmo antes do primeiro frame. O handler vai enfileirar se precisar.
    _navigationHandler?.registerMapServices();
  }

  void _initializeControllers() {
    _markerAssets = MapMarkerAssets();
    _participantWarmupService = ParticipantAvatarWarmupService();
    _actionWarmupService = EventCardActionWarmupService.instance;
    
    _eventPresenter = EventCardPresenter(
      viewModel: widget.viewModel,
    );
    
    _peopleController = MapPeopleController();
    
    _boundsController = MapBoundsController(
      viewModel: widget.viewModel,
      peopleController: _peopleController,
    );
    
    _cameraController = MapCameraController(
      viewModel: widget.viewModel,
    );
    
    _renderController = MapRenderController(
      viewModel: widget.viewModel,
      assets: _markerAssets,
      boundsController: _boundsController,
      onMarkerTap: (event) {
        if (!mounted) return;
        _eventPresenter.onMarkerTap(context, event);
      },
      onClusterTap: (pos, count) {
        _cameraController.onClusterTap(pos, count, _currentZoom);
      },
      onFirstRenderApplied: () {
        widget.onFirstRenderApplied?.call();
        _scheduleWarmupForVisibleEvents(
          delay: const Duration(milliseconds: 350),
        );
      },
    );
    
    _navigationHandler = MapNavigationHandler(
      context: context,
      isMounted: () => mounted,
      viewModel: widget.viewModel,
      renderController: _renderController!,
      eventPresenter: _eventPresenter,
    );

    // Listen to View Model changes
    widget.viewModel.addListener(_onEventsChanged);
    widget.viewModel.onMarkerTap = (event) {
        if (!mounted) return;
        _eventPresenter.onMarkerTap(context, event);
    };
    
    // Listen to explicit removals
    _removalSub = widget.viewModel.onEventRemoved.listen((eventId) {
      if (!mounted) return;
      debugPrint('🗑️ [GoogleMapView] Recebido sinal de remoção para eventId: $eventId');
      _renderController?.removeEventMarker(eventId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Always register services to ensure notification handling works
    // regardless of current TickerMode/visibility
    _navigationHandler?.registerMapServices();
  }

  @override
  void dispose() {
    _cameraIdleDebounce?.cancel();
    _warmupDebounce?.cancel();
    _participantWarmupService.cancel();
    _renderController?.dispose();
    _boundsController.dispose();
    _navigationHandler?.unregisterMapServices();
    _removalSub?.cancel();
    widget.viewModel.removeListener(_onEventsChanged);
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }

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

  void _onEventsChanged() {
    if (!mounted) return;
    _renderController?.scheduleRender();
  }

  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    
    // Distribute controller
    _boundsController.setController(controller);
    _cameraController.setController(controller);
    _navigationHandler?.setController(controller);

    // Re-register services (guarantee)
    _navigationHandler?.registerMapServices();

    widget.onPlatformMapCreated?.call();

    // Initial move
    if (widget.viewModel.lastLocation != null) {
      await _cameraController.moveCameraTo(
        widget.viewModel.lastLocation!.latitude,
        widget.viewModel.lastLocation!.longitude,
        zoom: 12.0,
        animate: false,
      );
    } else {
      await _cameraController.moveCameraToUserLocation(animate: false);
    }

    // Initial Search
    try {
      _currentZoom = await controller.getZoomLevel();
      _renderController?.setZoom(_currentZoom);
      
      await _boundsController.triggerInitialEventSearch(
        _currentZoom, 
        onNewData: () => _renderController?.scheduleRender(),
      );
      _scheduleWarmupForVisibleEvents(
        delay: const Duration(milliseconds: 350),
      );
    } catch (e) {
      debugPrint('⚠️ Erro ao obter zoom inicial: $e');
    }
  }

  void _onCameraMoveStarted() {
    _renderController?.setCameraMoving(true);
    _warmupDebounce?.cancel();
    UserStore.instance.cancelAvatarPreloads();
  }

  void _onCameraMove(CameraPosition position) {
    _currentZoom = position.zoom;
    _renderController?.setZoom(_currentZoom);
    // Realtime removed: evita processar clusters durante movimentos intermediários.
    // _renderController?.updateClustersRealtime();
    _boundsController.scheduleCacheLookahead(position.target, _currentZoom);
  }

  void _onCameraIdle() {
    _renderController?.setCameraMoving(false);
    
    _cameraIdleDebounce?.cancel();
    _cameraIdleDebounce = Timer(_cameraIdleDebounceDuration, () {
      if (!mounted) return;
      _handleCameraIdleDebounced();
    });
  }

  Future<void> _handleCameraIdleDebounced() async {
    if (_mapController == null) return;
    
    // Sync Zoom
    try {
        _currentZoom = await _mapController!.getZoomLevel();
        _renderController?.setZoom(_currentZoom);

        await _boundsController.onCameraIdle(
          _currentZoom, 
          onNewData: () => _renderController?.scheduleRender(),
        );
        _scheduleWarmupForVisibleEvents();
    } catch (e) {
        debugPrint('⚠️ Erro no idle: $e');
    }
  }

  void _scheduleWarmupForVisibleEvents({Duration? delay}) {
    if (!mounted) return;

    _warmupDebounce?.cancel();
    _warmupDebounce = Timer(delay ?? _warmupDebounceDuration, () {
      if (!mounted) return;
      if (_participantWarmupService.isRunning) return;

      final events = widget.viewModel.events;
      if (events.isEmpty) return;

      _participantWarmupService.warmupParticipantsForEvents(events);
      if (!_actionWarmupService.isRunning) {
        _actionWarmupService.warmupActionStateForEvents(events);
      }
    });
  }

  /// Método público para centralizar no usuário
  void centerOnUser() {
    _cameraController.centerOnUser();
  }

  /// Pré-carrega avatares de participantes dos eventos visíveis.
  /// 
  /// Chamar após `onFirstRenderApplied` para garantir que os avatares
  /// estejam prontos quando o usuário abrir um EventCard ou ListCard.
  /// 
  /// [maxEvents] Máximo de eventos para processar (default: 15)
  /// [participantsPerEvent] Máximo de participantes por evento (default: 5)
  Future<void> warmupParticipantAvatars({
    int? maxEvents,
    int? participantsPerEvent,
  }) async {
    if (!mounted) return;
    
    final events = widget.viewModel.events;
    if (events.isEmpty) {
      debugPrint('⏳ [GoogleMapView] warmupParticipantAvatars: sem eventos disponíveis');
      return;
    }
    
    await _participantWarmupService.warmupParticipantsForEvents(
      events,
      maxEvents: maxEvents,
      participantsPerEvent: participantsPerEvent,
    );
  }

  Future<void> warmupEventCardActions({
    int? maxEvents,
  }) async {
    if (!mounted) return;

    final events = widget.viewModel.events;
    if (events.isEmpty) {
      debugPrint('[GoogleMapView] warmupEventCardActions: sem eventos disponiveis');
      return;
    }

    await _actionWarmupService.warmupActionStateForEvents(
      events,
      maxEvents: maxEvents,
    );
  }

  /// Cancela qualquer warmup de avatares em progresso
  void cancelParticipantAvatarWarmup() {
    _participantWarmupService.cancel();
  }

  void cancelEventCardActionWarmup() {
    _actionWarmupService.cancel();
  }

  /// Prefetch best-effort baseado no viewport REAL com bounds expandido.
  Future<void> prefetchExpandedBounds({double? bufferFactor}) async {
    await _boundsController.prefetchExpandedBounds(bufferFactor: bufferFactor);
  }

  /// Preload best-effort
  Future<void> preloadZoomOutClusters({
    double targetZoom = 6.0,
    Duration settleDelay = const Duration(milliseconds: 220),
  }) async {
    if (!mounted) return;
    if (widget.viewModel.events.isEmpty) return;
    _renderController?.scheduleRender();
  }

  @override
  Widget build(BuildContext context) {
    final seededLocation = widget.viewModel.lastLocation;
    final initialTarget = seededLocation ?? const LatLng(-23.5505, -46.6333);

    final controller = _renderController;

    // Proteção contra render controller nulo
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return GoogleMap(
          style: _mapStyle,
          onMapCreated: _onMapCreated,
          onTap: (_) => _eventPresenter.dismissEventCardIfOpen(context),
          
          onCameraMoveStarted: _onCameraMoveStarted,
          onCameraMove: _onCameraMove,
          onCameraIdle: _onCameraIdle,

          initialCameraPosition: CameraPosition(
            target: initialTarget,
            zoom: seededLocation != null ? 12.0 : 10.0,
          ),
          
          minMaxZoomPreference: const MinMaxZoomPreference(3.0, 20.0),

          markers: controller.allMarkers,

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
      },
    );
  }
}
