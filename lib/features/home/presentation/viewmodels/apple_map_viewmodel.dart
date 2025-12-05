import 'dart:async';
import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/geo_distance_helper.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/repositories/event_map_repository.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/features/home/data/services/user_location_service.dart';
import 'package:partiu/features/home/presentation/services/event_marker_service.dart';
import 'package:partiu/services/location/location_stream_controller.dart';
import 'package:partiu/shared/repositories/user_repository.dart';

/// ViewModel responsável por gerenciar o estado e lógica do mapa
/// 
/// Responsabilidades:
/// - Carregar eventos com filtro de raio
/// - Gerar markers
/// - Gerenciar estado dos markers
/// - Fornecer dados limpos para o widget
/// - Orquestrar serviços
/// - Reagir a mudanças de raio em tempo real
/// 
/// NOTA: Este ViewModel usa EventMapRepository diretamente.
/// Para descoberta de PESSOAS, use LocationQueryService (refatorado para usuários).
class AppleMapViewModel extends ChangeNotifier {
  final EventMapRepository _eventRepository;
  final UserLocationService _locationService;
  final EventMarkerService _markerService;
  final LocationStreamController _streamController;
  final UserRepository _userRepository;
  final EventApplicationRepository _applicationRepository;

  /// Markers atualmente exibidos no mapa
  Set<Annotation> _eventMarkers = {};
  Set<Annotation> get eventMarkers => _eventMarkers;

  /// Estado de carregamento
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Estado de mapa pronto (localização + eventos + markers carregados)
  bool _mapReady = false;
  bool get mapReady => _mapReady;

  /// Última localização obtida
  LatLng? _lastLocation;
  LatLng? get lastLocation => _lastLocation;

  /// Eventos carregados
  List<EventModel> _events = [];
  List<EventModel> get events => _events;

  /// Callback quando um marker é tocado (recebe EventModel completo)
  Function(EventModel event)? onMarkerTap;

  /// Subscription para mudanças de raio
  StreamSubscription<double>? _radiusSubscription;
  
  /// Subscription para mudanças de filtros/reload
  StreamSubscription<void>? _reloadSubscription;

  AppleMapViewModel({
    EventMapRepository? eventRepository,
    UserLocationService? locationService,
    EventMarkerService? markerService,
    LocationStreamController? streamController,
    UserRepository? userRepository,
    EventApplicationRepository? applicationRepository,
    this.onMarkerTap,
  })  : _eventRepository = eventRepository ?? EventMapRepository(),
        _locationService = locationService ?? UserLocationService(),
        _markerService = markerService ?? EventMarkerService(),
        _streamController = streamController ?? LocationStreamController(),
        _userRepository = userRepository ?? UserRepository(),
        _applicationRepository = applicationRepository ?? EventApplicationRepository() {
    _initializeRadiusListener();
  }

  /// Inicializa listener para mudanças de raio
  void _initializeRadiusListener() {
    _radiusSubscription = _streamController.radiusStream.listen((radiusKm) {
      debugPrint('🗺️ AppleMapViewModel: Raio atualizado para $radiusKm km');
      // Recarregar eventos com novo raio
      loadNearbyEvents();
    });
    
    // Listener para mudanças de filtros (reload)
    _reloadSubscription = _streamController.reloadStream.listen((_) {
      debugPrint('🗺️ AppleMapViewModel: Reload solicitado (filtros mudaram)');
      // Recarregar eventos com novos filtros
      loadNearbyEvents();
    });
  }

  /// Inicializa o ViewModel
  /// 
  /// Deve ser chamado após o mapa estar pronto
  Future<void> initialize() async {
    await _markerService.preloadDefaultPins();
    // Carregar eventos iniciais
    await loadNearbyEvents();
  }

  /// Carrega eventos próximos à localização do usuário
  /// 
  /// Este método:
  /// 1. Obtém localização do usuário
  /// 2. Busca eventos próximos (EventMapRepository - raio fixo ou dinâmico)
  /// 3. Enriquece com distância e disponibilidade (_enrichEvents)
  /// 4. Gera markers
  /// 5. Atualiza estado
  Future<void> loadNearbyEvents() async {
    if (_isLoading) return;

    _setLoading(true);

    try {
      // 1. Obter localização
      final locationResult = await _locationService.getUserLocation();
      _lastLocation = locationResult.location;

      // 2. Buscar eventos (EventMapRepository)
      _events = await _eventRepository.getEventsWithinRadius(_lastLocation!);

      // 3. Enriquecer com distância e disponibilidade (lógica centralizada)
      await _enrichEvents();

      // 4. Gerar markers com callback de tap
      final markers = await _markerService.buildEventAnnotations(
        _events,
        onTap: onMarkerTap != null ? (eventId) {
          debugPrint('🟡 ViewModel onTap callback called for: $eventId');
          final event = _events.firstWhere((e) => e.id == eventId);
          debugPrint('🟡 Event found, calling onMarkerTap: ${event.title}');
          onMarkerTap!(event);
        } : null,
      );
      _eventMarkers = markers;

      debugPrint('🗺️ AppleMapViewModel: ${_events.length} eventos carregados');
      debugPrint('🗺️ Markers criados: ${markers.length}');
      debugPrint('🗺️ onMarkerTap callback configurado: ${onMarkerTap != null}');
      
      // SOMENTE AQUI o mapa está realmente pronto
      _setMapReady(true);
      
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

  /// Enriquece eventos com distância e disponibilidade ANTES de criar markers
  /// 
  /// IMPORTANTE: Esta é a ÚNICA fonte de verdade para calcular:
  /// - distanceKm: Distância do evento para o usuário
  /// - isAvailable: Se o usuário pode ver o evento (premium OU dentro de 30km)
  /// - creatorFullName: Usa dados desnormalizados do Firestore (OTIMIZAÇÃO: elimina N+1 queries)
  /// 
  /// Os repositórios (EventMapRepository) NÃO devem incluir esses campos - 
  /// toda lógica de enriquecimento fica aqui no ViewModel
  Future<void> _enrichEvents() async {
    if (_lastLocation == null || _events.isEmpty) return;

    final currentUserId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    // Buscar dados do usuário atual para verificar premium
    final currentUserDoc = await _userRepository.getUserById(currentUserId);
    final isPremium = currentUserDoc?['hasPremium'] as bool? ?? false;

    // Enriquecer cada evento (agora assíncrono para buscar nomes faltantes)
    final enrichedEvents = await Future.wait(_events.map((event) async {
      // 1. Calcular distância do evento para o usuário (Haversine - ~2ms por evento)
      final distance = GeoDistanceHelper.distanceInKm(
        _lastLocation!.latitude,
        _lastLocation!.longitude,
        event.lat,
        event.lng,
      );

      // 2. Verificar disponibilidade usando regra de negócio
      final isAvailable = _canApplyToEvent(
        isPremium: isPremium,
        distanceKm: distance,
      );

      // 3. Garantir que creatorFullName esteja presente
      // Se não vier desnormalizado, buscar sob demanda
      String? creatorFullName = event.creatorFullName;
      if (creatorFullName == null && event.createdBy.isNotEmpty) {
        try {
          final userDoc = await _userRepository.getUserBasicInfo(event.createdBy);
          creatorFullName = userDoc?['fullName'];
        } catch (e) {
          debugPrint('⚠️ Erro ao buscar nome do criador para evento ${event.id}: $e');
        }
      }

      // 4. Buscar participantes aprovados (avatares e nomes)
      List<Map<String, dynamic>>? participants;
      try {
        participants = await _applicationRepository.getApprovedApplicationsWithUserData(event.id);
      } catch (e) {
        debugPrint('⚠️ Erro ao buscar participantes para evento ${event.id}: $e');
      }

      // 5. Buscar aplicação do usuário atual (para saber se está aprovado/pendente)
      dynamic userApplication;
      try {
        userApplication = await _applicationRepository.getUserApplication(
          eventId: event.id,
          userId: currentUserId,
        );
      } catch (e) {
        debugPrint('⚠️ Erro ao buscar aplicação do usuário para evento ${event.id}: $e');
      }

      // 6. Retornar evento enriquecido
      return event.copyWith(
        distanceKm: distance,
        isAvailable: isAvailable,
        creatorFullName: creatorFullName,
        participants: participants,
        userApplication: userApplication,
      );
    }));
    
    _events = enrichedEvents;

    debugPrint('✨ Enriquecidos ${_events.length} eventos com distância e disponibilidade');
  }

  /// Verifica se o usuário pode aplicar para um evento
  /// 
  /// Regra de negócio:
  /// - Usuários premium podem ver todos os eventos (ilimitado)
  /// - Usuários free podem ver apenas eventos dentro do limite configurado
  bool _canApplyToEvent({
    required bool isPremium,
    required double distanceKm,
  }) {
    return isPremium || distanceKm <= FREE_ACCOUNT_MAX_EVENT_DISTANCE_KM;
  }

  /// Atualiza eventos para uma localização específica
  /// 
  /// Útil quando o usuário move o mapa manualmente
  /// 
  /// Usa EventMapRepository (raio fixo/dinâmico, mesma lógica de loadNearbyEvents)
  Future<void> loadEventsAt(LatLng location) async {
    if (_isLoading) return;

    _setLoading(true);
    _lastLocation = location;

    try {
      // Buscar eventos (EventMapRepository - raio fixo)
      final events = await _eventRepository.getEventsWithinRadius(location);
      _events = events;

      // Enriquecer com distância e disponibilidade (lógica centralizada em _enrichEvents)
      await _enrichEvents();

      final markers = await _markerService.buildEventAnnotations(
        events,
        onTap: onMarkerTap != null ? (eventId) {
          final event = _events.firstWhere((e) => e.id == eventId);
          onMarkerTap!(event);
        } : null,
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

  /// Define estado de mapa pronto
  void _setMapReady(bool value) {
    _mapReady = value;
    notifyListeners();
  }

  /// Limpa cache de markers
  void clearCache() {
    _markerService.clearCache();
  }

  @override
  void dispose() {
    _radiusSubscription?.cancel();
    _reloadSubscription?.cancel();
    _markerService.clearCache();
    super.dispose();
  }
}
