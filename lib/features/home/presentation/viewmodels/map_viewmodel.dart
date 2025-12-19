import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/geo_distance_helper.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/repositories/event_map_repository.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/features/home/data/services/user_location_service.dart';
import 'package:partiu/features/home/presentation/services/google_event_marker_service.dart';
import 'package:partiu/services/location/location_stream_controller.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/common/state/app_state.dart';

/// ViewModel responsável por gerenciar o estado e lógica do mapa Google Maps
/// 
/// Responsabilidades:
/// - Carregar eventos com filtro de raio
/// - Gerar markers do Google Maps
/// - Gerenciar estado dos markers
/// - Fornecer dados limpos para o widget
/// - Orquestrar serviços
/// - Reagir a mudanças de raio em tempo real
/// 
/// NOTA: Este ViewModel usa EventMapRepository diretamente.
/// Para descoberta de PESSOAS, use LocationQueryService (refatorado para usuários).
class MapViewModel extends ChangeNotifier {
  /// Instância global para permitir reset durante logout
  static MapViewModel? _instance;
  static MapViewModel? get instance => _instance;
  
  final EventMapRepository _eventRepository;
  final UserLocationService _locationService;
  final GoogleEventMarkerService _googleMarkerService;
  final LocationStreamController _streamController;
  final UserRepository _userRepository;
  final EventApplicationRepository _applicationRepository;

  /// Markers para Google Maps (pré-carregados)
  Set<Marker> _googleMarkers = {};
  Set<Marker> get googleMarkers => _googleMarkers;

  /// Estado de carregamento
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Estado de mapa pronto (localização + eventos + markers carregados)
  bool _mapReady = false;
  bool get mapReady => _mapReady;

  /// Última localização obtida (Google Maps LatLng)
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
  
  /// Subscription para stream de eventos em tempo real
  StreamSubscription<List<EventModel>>? _eventsSubscription;

  MapViewModel({
    EventMapRepository? eventRepository,
    UserLocationService? locationService,
    GoogleEventMarkerService? googleMarkerService,
    LocationStreamController? streamController,
    UserRepository? userRepository,
    EventApplicationRepository? applicationRepository,
    this.onMarkerTap,
  })  : _eventRepository = eventRepository ?? EventMapRepository(),
        _locationService = locationService ?? UserLocationService(),
        _googleMarkerService = googleMarkerService ?? GoogleEventMarkerService(),
        _streamController = streamController ?? LocationStreamController(),
        _userRepository = userRepository ?? UserRepository(),
        _applicationRepository = applicationRepository ?? EventApplicationRepository() {
    _instance = this; // Registra instância global
    _initializeRadiusListener();
  }

  /// Cancela todos os streams Firestore (usar no logout)
  /// Isso evita erros de permission-denied quando o usuário é deslogado
  void cancelAllStreams() {
    debugPrint('🔌 MapViewModel: Cancelando todos os streams...');
    _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _radiusSubscription?.cancel();
    _radiusSubscription = null;
    _reloadSubscription?.cancel();
    _reloadSubscription = null;
    BlockService.instance.removeListener(_onBlockedUsersChanged);
    debugPrint('✅ MapViewModel: Streams cancelados');
  }

  /// Inicializa listener para mudanças de raio
  void _initializeRadiusListener() {
    _radiusSubscription = _streamController.radiusStream.listen((radiusKm) {
      debugPrint('🗺️ MapViewModel: Raio atualizado para $radiusKm km');
      // Recarregar eventos com novo raio
      loadNearbyEvents();
    });
    
    // Listener para mudanças de filtros (reload)
    _reloadSubscription = _streamController.reloadStream.listen((_) {
      debugPrint('🗺️ MapViewModel: Reload solicitado (filtros mudaram)');
      // Recarregar eventos com novos filtros
      loadNearbyEvents();
    });
    
    // ⬅️ LISTENER REATIVO PARA BLOQUEIOS
    BlockService.instance.addListener(_onBlockedUsersChanged);
    
    // ⬅️ STREAM DE EVENTOS EM TEMPO REAL
    _initializeEventsStream();
  }
  
  /// Inicializa stream de eventos em tempo real (reage a create/update/delete)
  void _initializeEventsStream() {
    debugPrint('🔄 MapViewModel: Iniciando stream de eventos em tempo real...');
    
    _eventsSubscription = _eventRepository.getEventsStream().listen(
      (events) async {
        debugPrint('🔄 MapViewModel: Stream recebeu ${events.length} eventos');
        debugPrint('📋 IDs dos eventos: ${events.map((e) => e.id).join(", ")}');
        
        // Obter localização atual
        if (_lastLocation == null) {
          final locationResult = await _locationService.getUserLocation();
          _lastLocation = locationResult.location;
        }
        
        // Filtrar eventos de usuários bloqueados
        final currentUserId = AppState.currentUserId;
        if (currentUserId != null && currentUserId.isNotEmpty) {
          _events = BlockService().filterBlocked<EventModel>(
            currentUserId,
            events,
            (event) => event.createdBy,
          );
          
          final filteredCount = events.length - _events.length;
          if (filteredCount > 0) {
            debugPrint('🚫 MapViewModel: $filteredCount eventos filtrados (bloqueados)');
          }
        } else {
          _events = events;
        }
        
        debugPrint('📊 MapViewModel: ${_events.length} eventos após filtros');
        
        // Enriquecer com distância e disponibilidade
        await _enrichEvents();
        
        // Gerar markers
        await _generateGoogleMarkers();
        
        debugPrint('✅ MapViewModel: Stream processado - ${_events.length} eventos, ${_googleMarkers.length} markers');
        debugPrint('🔔 Chamando notifyListeners() para atualizar UI...');
        notifyListeners();
      },
      onError: (error) {
        debugPrint('❌ MapViewModel: Erro no stream de eventos: $error');
      },
    );
  }
  
  /// Callback quando BlockService muda (via ChangeNotifier)
  void _onBlockedUsersChanged() {
    debugPrint('🔄 MapViewModel: Bloqueios mudaram - recarregando eventos do mapa...');
    // Recarrega tudo porque eventos desbloqueados não estão no cache local
    loadNearbyEvents();
  }

  /// Inicializa o ViewModel
  /// 
  /// Deve ser chamado após o mapa estar pronto
  Future<void> initialize() async {
    // Pré-carregar pins (imagens) para Google Maps
    await _googleMarkerService.preloadDefaultPins();
    
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

      // 2. Buscar eventos (EventMapRepository - raio fixo ou dinâmico)
      final events = await _eventRepository.getEventsWithinRadius(_lastLocation!);
      
      // 3. Filtrar eventos de usuários bloqueados
      final currentUserId = AppState.currentUserId;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        _events = BlockService().filterBlocked<EventModel>(
          currentUserId,
          events,
          (event) => event.createdBy,
        );
        
        final filteredCount = events.length - _events.length;
        if (filteredCount > 0) {
          debugPrint('🚫 MapViewModel: $filteredCount eventos filtrados (bloqueados)');
        }
      } else {
        _events = events;
      }

      // 4. Enriquecer com distância e disponibilidade (lógica centralizada)
      await _enrichEvents();

      // 4. Gerar markers do Google Maps
      await _generateGoogleMarkers();

      debugPrint('🗺️ MapViewModel: ${_events.length} eventos carregados');
      debugPrint('🗺️ Google Maps markers: ${_googleMarkers.length}');
      debugPrint('🗺️ onMarkerTap callback configurado: ${onMarkerTap != null}');
      
      // SOMENTE AQUI o mapa está realmente pronto
      _setMapReady(true);
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ MapViewModel: Erro ao carregar eventos: $e');
      // Erro será silencioso - markers continuam vazios
      _googleMarkers = {};
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Gera markers do Google Maps
  Future<void> _generateGoogleMarkers() async {
    final markers = await _googleMarkerService.buildEventMarkers(
      _events,
      onTap: onMarkerTap != null ? (eventId) {
        debugPrint('🟢 Google Maps marker tapped: $eventId');
        final event = _events.firstWhere((e) => e.id == eventId);
        onMarkerTap!(event);
      } : null,
    );
    _googleMarkers = markers;
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

    // Buscar dados do usuário atual para verificar premium E idade
    final currentUserDoc = await _userRepository.getUserById(currentUserId);
    final isPremium = currentUserDoc?['hasPremium'] as bool? ?? false;
    final userAge = currentUserDoc?['age'] as int?;

    // Enriquecer cada evento (agora assíncrono para buscar nomes faltantes)
    final enrichedEvents = await Future.wait(_events.map((event) async {
      // 🚨 VALIDAÇÃO: Verificar se coordenadas são válidas (detectar bug Web Mercator)
      final userLat = _lastLocation!.latitude;
      final userLng = _lastLocation!.longitude;
      final eventLat = event.lat;
      final eventLng = event.lng;
      
      // Validar coordenadas do usuário
      if (userLat < -90 || userLat > 90 || userLng < -180 || userLng > 180) {
        debugPrint('🚨 [MapViewModel] COORDENADAS INVÁLIDAS DO USUÁRIO:');
        debugPrint('   userLat: $userLat, userLng: $userLng');
        debugPrint('   Parece ser Web Mercator em vez de lat/lng em graus!');
      }
      
      // Validar coordenadas do evento
      if (eventLat < -90 || eventLat > 90 || eventLng < -180 || eventLng > 180) {
        debugPrint('🚨 [MapViewModel] COORDENADAS INVÁLIDAS DO EVENTO ${event.id}:');
        debugPrint('   eventLat: $eventLat, eventLng: $eventLng');
        debugPrint('   Parece ser Web Mercator em vez de lat/lng em graus!');
      }
      
      // 1. Calcular distância do evento para o usuário (Haversine - ~2ms por evento)
      final distance = GeoDistanceHelper.distanceInKm(
        userLat,
        userLng,
        eventLat,
        eventLng,
      );

      // 2. Verificar disponibilidade usando regra de negócio
      final isAvailable = _canApplyToEvent(
        isPremium: isPremium,
        distanceKm: distance,
      );
      
      // 🔍 LOG DE DIAGNÓSTICO: Quando evento NÃO está disponível
      if (!isAvailable) {
        debugPrint('🔒 [MapViewModel] Evento "${event.title}" (${event.id}) FORA DA ÁREA:');
        debugPrint('   📍 Usuário: ($userLat, $userLng)');
        debugPrint('   📍 Evento: ($eventLat, $eventLng)');
        debugPrint('   📏 Distância calculada: ${distance.toStringAsFixed(2)} km');
        debugPrint('   👑 isPremium: $isPremium');
        debugPrint('   🎯 Limite FREE: $FREE_ACCOUNT_MAX_EVENT_DISTANCE_KM km');
      }

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

      // 6. Validar restrições de idade usando dados que já vieram do EventModel
      bool isAgeRestricted = false;
      
      // Validar idade apenas se não for o criador e houver restrições definidas
      final isCreator = event.createdBy == currentUserId;
      if (!isCreator && event.minAge != null && event.maxAge != null && userAge != null) {
        isAgeRestricted = userAge < event.minAge! || userAge > event.maxAge!;
        
        if (isAgeRestricted) {
          debugPrint('🔒 [MapViewModel] Evento ${event.id} restrito: userAge=$userAge, range=${event.minAge}-${event.maxAge}');
        }
      }

      // 7. Retornar evento enriquecido
      return event.copyWith(
        distanceKm: distance,
        isAvailable: isAvailable,
        creatorFullName: creatorFullName,
        participants: participants,
        userApplication: userApplication,
        isAgeRestricted: isAgeRestricted,
      );
    }));
    
    // Filtrar eventos rejeitados (não mostrar eventos onde o usuário foi rejeitado)
    final eventsBeforeFilter = enrichedEvents.length;
    _events = enrichedEvents.where((event) {
      final isRejected = event.userApplication?.isRejected ?? false;
      if (isRejected) {
        debugPrint('🚫 Evento ${event.id} filtrado (aplicação rejeitada)');
      }
      return !isRejected;
    }).toList();

    final filteredCount = eventsBeforeFilter - _events.length;
    if (filteredCount > 0) {
      debugPrint('🚫 $filteredCount evento(s) rejeitado(s) removido(s) da lista');
    }

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

      // Gerar markers do Google Maps
      await _generateGoogleMarkers();

      notifyListeners();
    } catch (e) {
      debugPrint('❌ MapViewModel: Erro ao carregar eventos: $e');
      _googleMarkers = {};
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
    _googleMarkers = {};
    _events = [];
    notifyListeners();
  }

  /// Limpa recursos do ViewModel
  void clear() {
    _googleMarkers = {};
    _events = [];
    notifyListeners();
  }

  /// Obtém localização do usuário
  /// 
  /// Retorna LocationResult com informações detalhadas
  Future<LocationResult> getUserLocation() async {
    return await _locationService.getUserLocation();
  }

  /// Injeta um evento manualmente na lista (usado após criação)
  Future<void> injectEvent(EventModel event) async {
    // Verificar se já existe
    final index = _events.indexWhere((e) => e.id == event.id);
    if (index >= 0) {
      _events[index] = event;
    } else {
      _events.insert(0, event);
    }
    
    // Enriquecer este evento específico
    await _enrichEvents(); // Idealmente enriquecer só este, mas por segurança re-enriquecemos tudo
    
    // Regenerar markers
    await _generateGoogleMarkers();
    
    notifyListeners();
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
    _googleMarkerService.clearCache();
  }

  @override
  void dispose() {
    cancelAllStreams(); // Cancela streams primeiro
    _googleMarkerService.clearCache();
    _instance = null; // Limpa referência global
    super.dispose();
  }
}
