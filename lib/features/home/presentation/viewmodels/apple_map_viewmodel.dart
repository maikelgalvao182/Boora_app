import 'dart:async';
import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/repositories/event_map_repository.dart';
import 'package:partiu/features/home/data/services/user_location_service.dart';
import 'package:partiu/features/home/presentation/services/event_marker_service.dart';
import 'package:partiu/services/location/location_query_service.dart';
import 'package:partiu/services/location/location_stream_controller.dart';

/// ViewModel responsável por gerenciar o estado e lógica do mapa
/// 
/// Responsabilidades:
/// - Carregar eventos com filtro de raio
/// - Gerar markers
/// - Gerenciar estado dos markers
/// - Fornecer dados limpos para o widget
/// - Orquestrar serviços
/// - Reagir a mudanças de raio em tempo real
class AppleMapViewModel extends ChangeNotifier {
  final EventMapRepository _eventRepository;
  final UserLocationService _locationService;
  final EventMarkerService _markerService;
  final LocationQueryService _locationQueryService;
  final LocationStreamController _streamController;

  /// Markers atualmente exibidos no mapa
  Set<Annotation> _eventMarkers = {};
  Set<Annotation> get eventMarkers => _eventMarkers;

  /// Estado de carregamento
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Última localização obtida
  LatLng? _lastLocation;
  LatLng? get lastLocation => _lastLocation;

  /// Eventos carregados
  List<EventModel> _events = [];
  List<EventModel> get events => _events;

  /// Callback quando um marker é tocado
  Function(String eventId)? onMarkerTap;

  /// Subscription para mudanças de raio
  StreamSubscription<double>? _radiusSubscription;

  AppleMapViewModel({
    EventMapRepository? eventRepository,
    UserLocationService? locationService,
    EventMarkerService? markerService,
    LocationQueryService? locationQueryService,
    LocationStreamController? streamController,
    this.onMarkerTap,
  })  : _eventRepository = eventRepository ?? EventMapRepository(),
        _locationService = locationService ?? UserLocationService(),
        _markerService = markerService ?? EventMarkerService(),
        _locationQueryService = locationQueryService ?? LocationQueryService(),
        _streamController = streamController ?? LocationStreamController() {
    _initializeRadiusListener();
  }

  /// Inicializa listener para mudanças de raio
  void _initializeRadiusListener() {
    _radiusSubscription = _streamController.radiusStream.listen((radiusKm) {
      debugPrint('🗺️ AppleMapViewModel: Raio atualizado para $radiusKm km');
      // Recarregar eventos com novo raio
      loadNearbyEvents();
    });
  }

  /// Inicializa o ViewModel
  /// 
  /// Deve ser chamado após o mapa estar pronto
  Future<void> initialize() async {
    await _markerService.preloadDefaultPins();
  }

  /// Carrega eventos próximos à localização do usuário
  /// 
  /// Este método:
  /// 1. Obtém localização do usuário
  /// 2. Inicializa dados no Firestore se necessário
  /// 3. Busca eventos próximos com filtro de raio
  /// 4. Gera markers
  /// 5. Atualiza estado
  Future<void> loadNearbyEvents() async {
    if (_isLoading) return;

    _setLoading(true);

    try {
      // 1. Obter localização
      final locationResult = await _locationService.getUserLocation();
      _lastLocation = locationResult.location;

      // 2. Inicializar dados do usuário no Firestore se necessário
      // Isso garante que os campos latitude, longitude e radiusKm existem
      await _locationQueryService.initializeUserLocation(
        latitude: _lastLocation!.latitude,
        longitude: _lastLocation!.longitude,
      );

      // 3. Buscar eventos com filtro de raio usando LocationQueryService
      final eventsWithDistance = await _locationQueryService.getEventsWithinRadiusOnce();

      // 4. Converter para EventModel
      _events = eventsWithDistance.map((eventWithDistance) {
        return EventModel.fromMap(
          eventWithDistance.eventData,
          eventWithDistance.eventId,
        );
      }).toList();

      // 5. Gerar markers com callback de tap
      final markers = await _markerService.buildEventAnnotations(
        _events,
        onTap: onMarkerTap,
      );
      _eventMarkers = markers;

      debugPrint('🗺️ AppleMapViewModel: ${_events.length} eventos carregados');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ AppleMapViewModel: Erro ao carregar eventos: $e');
      // Erro será silencioso - markers continuam vazios
      _eventMarkers = {};
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Atualiza eventos para uma localização específica
  /// 
  /// Útil quando o usuário move o mapa manualmente
  Future<void> loadEventsAt(LatLng location) async {
    if (_isLoading) return;

    _setLoading(true);
    _lastLocation = location;

    try {
      final events = await _eventRepository.getEventsWithinRadius(location);
      _events = events;

      final markers = await _markerService.buildEventAnnotations(
        events,
        onTap: onMarkerTap,
      );
      _eventMarkers = markers;

      notifyListeners();
    } catch (e) {
      _eventMarkers = {};
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Recarrega eventos (força atualização)
  Future<void> refresh() async {
    if (_lastLocation != null) {
      await loadEventsAt(_lastLocation!);
    } else {
      await loadNearbyEvents();
    }
  }

  /// Limpa todos os markers
  void clearMarkers() {
    _eventMarkers = {};
    _events = [];
    notifyListeners();
  }

  /// Obtém localização do usuário
  /// 
  /// Retorna LocationResult com informações detalhadas
  Future<LocationResult> getUserLocation() async {
    return await _locationService.getUserLocation();
  }

  /// Define estado de carregamento
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// Limpa cache de markers
  void clearCache() {
    _markerService.clearCache();
  }

  @override
  void dispose() {
    _radiusSubscription?.cancel();
    _markerService.clearCache();
    super.dispose();
  }
}
