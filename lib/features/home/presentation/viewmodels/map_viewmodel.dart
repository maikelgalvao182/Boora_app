import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/geo_distance_helper.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:partiu/features/home/data/services/map_discovery_service.dart';
import 'package:partiu/features/home/data/repositories/event_map_repository.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/features/home/data/services/user_location_service.dart';
import 'package:partiu/features/home/presentation/services/google_event_marker_service.dart';
import 'package:partiu/services/location/location_stream_controller.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/core/utils/app_logger.dart';

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
  final MapDiscoveryService _mapDiscoveryService;

  List<String> _availableCategoriesInBounds = const [];

  int _eventsInBoundsCount = 0;
  int _matchingEventsInBoundsCount = 0;

  Map<String, int> _eventsInBoundsCountByCategory = const {};

  int get eventsInBoundsCount => _eventsInBoundsCount;
  int get matchingEventsInBoundsCount => _matchingEventsInBoundsCount;
  Map<String, int> get eventsInBoundsCountByCategory => _eventsInBoundsCountByCategory;

  /// Markers para Google Maps (pré-carregados)
  Set<Marker> _googleMarkers = {};
  Set<Marker> get googleMarkers => _googleMarkers;

  /// Estado de carregamento
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Estado de mapa pronto (localização + eventos + markers carregados)
  bool _mapReady = false;
  bool get mapReady => _mapReady;

  bool _didInitialize = false;

  /// Última localização obtida (Google Maps LatLng)
  LatLng? _lastLocation;
  LatLng? get lastLocation => _lastLocation;

  /// Seta uma localização inicial (ex.: persistida no Firestore) apenas se
  /// ainda não existe uma `_lastLocation` em memória.
  ///
  /// Objetivo: permitir que o GoogleMap comece na cidade correta no primeiro
  /// frame, sem pular do fallback (ex.: São Paulo) para a localização real.
  void seedInitialLocation(LatLng location) {
    if (_lastLocation != null) return;
    _lastLocation = location;
    notifyListeners();
  }

  /// Eventos carregados
  List<EventModel> _events = [];
  List<EventModel> get events => _events;

  /// Versão monotônica do dataset de eventos exposto ao mapa.
  ///
  /// Motivo: evitar o gap "ids iguais -> não notifica" + permitir que a UI
  /// detecte mudanças de dataset e force um render no idle.
  final ValueNotifier<int> eventsVersion = ValueNotifier<int>(0);

  /// Assinatura leve do snapshot atual para evitar o caso
  /// "ids iguais -> não notifica" quando o visual precisa re-renderizar
  /// (ex.: corrida aplicou markers vazios, mas o dataset é o mesmo).
  ///
  /// A assinatura é atualizada junto com `_events` e incluí:
  /// - quantidade de eventos
  /// - contagem por categoria (derivada do snapshot)
  /// - versão do snapshot (incrementada a cada sync do viewport)
  String _eventsSignature = '';

  /// Incrementa a cada tentativa de sincronizar o viewport (load/refresh bounds).
  /// Isso evita o caso: "ids iguais -> não notifica" quando a UI precisa
  /// reconstruir markers por ter aplicado um estado visual incorreto por corrida.
  int _boundsSnapshotVersion = 0;

  /// Filtro de categoria selecionado para o mapa
  /// - null: mostrar todas
  /// - String: mostrar apenas eventos daquela categoria
  String? _selectedCategory;
  String? get selectedCategory => _selectedCategory;

  /// Categorias disponíveis, derivadas dos eventos carregados (coleção Events)
  List<String> get availableCategories {
    return _availableCategoriesInBounds;
  }

  void setCategoryFilter(String? category) {
    final normalized = category?.trim();
    final next = (normalized == null || normalized.isEmpty) ? null : normalized;
    if (_selectedCategory == next) return;
    _selectedCategory = next;
    _recomputeCountsInBounds();
    notifyListeners();
  }

  void _recomputeCountsInBounds() {
    final boundsEvents = _mapDiscoveryService.nearbyEvents.value;

    final countsByCategory = <String, int>{};
    for (final event in boundsEvents) {
      final category = event.category;
      if (category == null) continue;
      final normalized = category.trim();
      if (normalized.isEmpty) continue;
      countsByCategory[normalized] = (countsByCategory[normalized] ?? 0) + 1;
    }

    _eventsInBoundsCount = boundsEvents.length;
    _eventsInBoundsCountByCategory = Map<String, int>.unmodifiable(countsByCategory);

    final selected = _selectedCategory;
    if (selected == null || selected.trim().isEmpty) {
      _matchingEventsInBoundsCount = _eventsInBoundsCount;
    } else {
      _matchingEventsInBoundsCount =
          _eventsInBoundsCountByCategory[selected.trim()] ?? 0;
    }
  }

  /// Callback quando um marker é tocado (recebe EventModel completo)
  Function(EventModel event)? onMarkerTap;

  /// Subscription para mudanças de raio
  StreamSubscription<double>? _radiusSubscription;
  
  /// Subscription para mudanças de filtros/reload
  StreamSubscription<void>? _reloadSubscription;
  
  /// Subscription para stream de eventos em tempo real
  // (stream global removido)

  MapViewModel({
    EventMapRepository? eventRepository,
    UserLocationService? locationService,
    GoogleEventMarkerService? googleMarkerService,
    LocationStreamController? streamController,
    UserRepository? userRepository,
    EventApplicationRepository? applicationRepository,
    MapDiscoveryService? mapDiscoveryService,
    this.onMarkerTap,
  })  : _eventRepository = eventRepository ?? EventMapRepository(),
        _locationService = locationService ?? UserLocationService(),
        _googleMarkerService = googleMarkerService ?? GoogleEventMarkerService(),
        _streamController = streamController ?? LocationStreamController(),
        _userRepository = userRepository ?? UserRepository(),
        _applicationRepository = applicationRepository ?? EventApplicationRepository(),
        _mapDiscoveryService = mapDiscoveryService ?? MapDiscoveryService() {
    _instance = this; // Registra instância global
    _initializeRadiusListener();
    _startBoundsCategoriesListener();
  }

  void _startBoundsCategoriesListener() {
    // Mantém chips sincronizados com o bounding box (viewport)
    _mapDiscoveryService.nearbyEvents.addListener(_onBoundsEventsChanged);
    // Atualiza imediatamente com o valor atual (seeded)
    _onBoundsEventsChanged();
  }

  void _stopBoundsCategoriesListener() {
    _mapDiscoveryService.nearbyEvents.removeListener(_onBoundsEventsChanged);
  }

  void _onBoundsEventsChanged() {
    var changed = false;

    final previousTotal = _eventsInBoundsCount;
    final previousMatching = _matchingEventsInBoundsCount;
    final previousCountsByCategory = _eventsInBoundsCountByCategory;

    _recomputeCountsInBounds();

    if (_eventsInBoundsCount != previousTotal ||
        _matchingEventsInBoundsCount != previousMatching ||
        !mapEquals(previousCountsByCategory, _eventsInBoundsCountByCategory)) {
      changed = true;
    }

    final next = _eventsInBoundsCountByCategory.keys.toList()..sort();
    if (!listEquals(_availableCategoriesInBounds, next)) {
      _availableCategoriesInBounds = next;
      changed = true;
    }

    // Se a categoria selecionada não existe mais no viewport, reseta para "Todas"
    final selected = _selectedCategory;
    if (selected != null && selected.trim().isNotEmpty) {
      final normalized = selected.trim();
      if (!_availableCategoriesInBounds.contains(normalized)) {
        _selectedCategory = null;
        _recomputeCountsInBounds();
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// Cancela todos os streams Firestore (usar no logout)
  /// Isso evita erros de permission-denied quando o usuário é deslogado
  void cancelAllStreams() {
    debugPrint('🔌 MapViewModel: Cancelando todos os streams...');
    _radiusSubscription?.cancel();
    _radiusSubscription = null;
    _reloadSubscription?.cancel();
    _reloadSubscription = null;
    _stopBoundsCategoriesListener();
    BlockService.instance.removeListener(_onBlockedUsersChanged);

    // ✅ IMPORTANTE: limpar estado em memória para evitar markers “fantasmas” após logout/delete.
    // Sem isso, o GoogleMapView pode manter markers antigos porque o stream foi cancelado
    // e nenhum novo evento chega para disparar rebuild.
    _events = const [];
    _googleMarkers = <Marker>{};
    _mapReady = false;
    _lastLocation = null;
    _selectedCategory = null;
    _availableCategoriesInBounds = const [];
    _eventsInBoundsCount = 0;
    _matchingEventsInBoundsCount = 0;
    _eventsInBoundsCountByCategory = const {};

    notifyListeners();
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
    
    // ✅ Importante: não iniciar mais um stream global de eventos aqui.
    // A fonte de verdade para o mapa deve ser o viewport/bounds do GoogleMapView
    // (loadEventsInBounds/forceRefreshBounds), para evitar churn e tráfego
    // desnecessário.
  }
  
  // (Stream global removido — ver comentário no construtor)
  
  /// Callback quando BlockService muda (via ChangeNotifier)
  void _onBlockedUsersChanged() {
    debugPrint('🔄 MapViewModel: Bloqueios mudaram - recarregando eventos do mapa...');
    // Recarrega tudo porque eventos desbloqueados não estão no cache local
    loadNearbyEvents();
  }

  /// Inicializa o ViewModel
  /// 
  /// Deve ser chamado após o mapa estar pronto
  /// 
  /// Este método:
  /// 1. Pré-carrega pins padrão
  /// 2. Carrega eventos próximos (popula cache de bitmaps durante geração de markers)
  /// 
  /// NOTA: O cache de bitmaps é SINGLETON (GoogleEventMarkerService)
  /// então os bitmaps gerados aqui serão reutilizados pelo GoogleMapView.
  Future<void> initialize() async {
    if (_didInitialize) {
      return;
    }

    _didInitialize = true;

    try {
      // Pré-carregar pins (imagens) para Google Maps
      await _googleMarkerService.preloadDefaultPins();

      // Carregar eventos iniciais apenas se ainda não temos nada em memória.
      // Evita competir com o stream de eventos em tempo real.
      final hasEvents = _events.isNotEmpty;
      if (!hasEvents && !_mapReady) {
        await loadNearbyEvents();
      }
    } catch (e, stack) {
      AppLogger.error(
        'Falha ao inicializar MapViewModel',
        tag: 'MAP',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Carrega eventos próximos à localização do usuário
  /// 
  /// **REFATORADO (PR2):** Agora delega para o fluxo bounds-based, que é
  /// otimizado com cache TTL e debounce. Não faz mais N+1 queries.
  /// 
  /// Este método:
  /// 1. Obtém localização do usuário
  /// 2. Cria bounds de ~10km ao redor da localização
  /// 3. Delega para loadEventsInBounds() (cache + debounce + sem N+1)
  Future<void> loadNearbyEvents() async {
    if (_isLoading) return;

    _setLoading(true);

    try {
      // 1. Obter localização
      final locationResult = await _locationService.getUserLocation();
      _lastLocation = locationResult.location;

      if (_lastLocation == null) {
        AppLogger.warning('Localização não disponível', tag: 'MAP');
        return;
      }

      // 2. Criar bounds de ~10km ao redor da localização
      // (~0.09 graus ≈ 10km de raio)
      const radiusDegrees = 0.09;
      final bounds = MapBounds(
        minLat: _lastLocation!.latitude - radiusDegrees,
        maxLat: _lastLocation!.latitude + radiusDegrees,
        minLng: _lastLocation!.longitude - radiusDegrees,
        maxLng: _lastLocation!.longitude + radiusDegrees,
      );

      // 3. Delegar para fluxo bounds-based (cache TTL + debounce)
      await loadEventsInBounds(bounds);
      
      AppLogger.info('Eventos carregados via bounds: ${_events.length}', tag: 'MAP');
      
      // SOMENTE AQUI o mapa está realmente pronto
      _setMapReady(true);
      
    } catch (e) {
      AppLogger.error('Erro ao carregar eventos do mapa', tag: 'MAP', error: e);
      // Erro será silencioso - markers continuam vazios
      _googleMarkers = {};
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Gera markers do Google Maps
  /// 
  /// NOTA: Os markers gerados aqui podem não ter callbacks corretos
  /// porque onMarkerTap é configurado pelo GoogleMapView.initState()
  /// Os BITMAPS pré-carregados são o que importa para performance
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
  /// ⚠️ **DEPRECATED (PR2):** Este método faz N+1 queries (busca creator, participants,
  /// userApplication para CADA evento). Não deve ser usado no fluxo do mapa.
  /// 
  /// Se precisar de dados enriquecidos (ex: ao abrir EventCard), use um serviço
  /// com cache TTL por eventId.
  /// 
  /// IMPORTANTE: Esta é a ÚNICA fonte de verdade para calcular:
  /// - distanceKm: Distância do evento para o usuário
  /// - isAvailable: Se o usuário pode ver o evento (premium OU dentro de 30km)
  /// - creatorFullName: Usa dados desnormalizados do Firestore (OTIMIZAÇÃO: elimina N+1 queries)
  /// 
  /// Os repositórios (EventMapRepository) NÃO devem incluir esses campos - 
  /// toda lógica de enriquecimento fica aqui no ViewModel
  @Deprecated('Use cache por eventId ao abrir card. Não chamar no fluxo do mapa.')
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
  /// **REFATORADO (PR2):** Agora delega para o fluxo bounds-based.
  Future<void> loadEventsAt(LatLng location) async {
    if (_isLoading) return;

    _setLoading(true);
    _lastLocation = location;

    try {
      // Criar bounds de ~10km ao redor da localização
      const radiusDegrees = 0.09;
      final bounds = MapBounds(
        minLat: location.latitude - radiusDegrees,
        maxLat: location.latitude + radiusDegrees,
        minLng: location.longitude - radiusDegrees,
        maxLng: location.longitude + radiusDegrees,
      );

      // Delegar para fluxo bounds-based (cache TTL + debounce)
      await loadEventsInBounds(bounds);

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

  /// Atualiza categorias do drawer baseado no bounding box visível
  /// 
  /// Chamado pelo GoogleMapView quando a câmera para de mover.
  /// Isso mantém os chips de categoria sincronizados com o viewport.
  Future<void> loadEventsInBounds(MapBounds bounds) async {
    debugPrint('🔵 [MapVM] loadEventsInBounds start (events.length=${_events.length})');
    // Estratégia A (stale-while-revalidate): mantém eventos atuais durante o fetch.
    // A UI pode reagir ao loading (spinner), mas não apaga markers por um "vazio" transitório.
    _setLoading(true);
    try {
      await _mapDiscoveryService.loadEventsInBounds(bounds);
      debugPrint('🔵 [MapVM] loadEventsInBounds after service (nearbyEvents.value.length=${_mapDiscoveryService.nearbyEvents.value.length})');
      await _syncEventsFromBounds();
      debugPrint('🔵 [MapVM] loadEventsInBounds after sync (events.length=${_events.length})');
    } finally {
      _setLoading(false);
    }
  }

  /// Força refresh imediato das categorias do drawer
  /// 
  /// Ignora cache e debounce. Usado na inicialização do mapa.
  Future<void> forceRefreshBounds(MapBounds bounds) async {
    // Refresh forçado: aqui o resultado (inclusive vazio) é considerado "confirmado".
    _setLoading(true);
    try {
      await _mapDiscoveryService.forceRefresh(bounds);
      await _syncEventsFromBounds(forceEmpty: true);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _syncEventsFromBounds({bool forceEmpty = false}) async {
    debugPrint('🟣 [MapVM] _syncEventsFromBounds start (forceEmpty=$forceEmpty)');
    // Mesmo que a lista final não mude, houve uma tentativa de sync do viewport.
    // Atualizamos a versão para permitir notificar a UI quando necessário.
    _boundsSnapshotVersion = (_boundsSnapshotVersion + 1).clamp(0, 1 << 30);
    final boundsEvents = _mapDiscoveryService.nearbyEvents.value;
    debugPrint('🟣 [MapVM] boundsEvents.length=${boundsEvents.length} isLoading=${_mapDiscoveryService.isLoading}');
    if (boundsEvents.isEmpty) {
      // "Vazio" pode ser transitório por debounce / in-flight request.
      // Estratégia A: manter dados atuais enquanto o MapDiscovery ainda está carregando.
      final emptyConfirmed = forceEmpty || !_mapDiscoveryService.isLoading;
      debugPrint('🟣 [MapVM] boundsEvents.isEmpty => emptyConfirmed=$emptyConfirmed');

      if (emptyConfirmed) {
        if (_events.isNotEmpty) {
          debugPrint('🟣 [MapVM] clearing _events (was ${_events.length})');
          _events = const [];
          eventsVersion.value = (eventsVersion.value + 1).clamp(0, 1 << 30);
          notifyListeners();
        }
      }
      return;
    }

    // Obter dados do usuário para calcular distância e verificar premium
    final currentUserId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    bool isPremium = false;
    
    if (currentUserId != null) {
      try {
        final userDoc = await _userRepository.getUserById(currentUserId);
        isPremium = userDoc?['hasPremium'] as bool? ?? false;
      } catch (_) {}
    }

    // Converte EventLocation -> EventModel
    // ✅ Agora extrai TODOS os campos necessários do eventData
    final mapped = boundsEvents
        .map((e) {
          final data = e.eventData;
          final location = data['location'] as Map<String, dynamic>?;
          final participantsData = data['participants'] as Map<String, dynamic>?;
          final scheduleData = data['schedule'] as Map<String, dynamic>?;
          
          // Parse schedule date
          DateTime? scheduleDate;
          final dateField = scheduleData?['date'];
          if (dateField != null) {
            try {
              scheduleDate = dateField.toDate();
            } catch (_) {}
          }
          
          // Parse photoReferences
          List<String>? photoReferences;
          final photoRefs = location?['photoReferences'] as List<dynamic>?;
          if (photoRefs != null) {
            photoReferences = photoRefs.map((ref) => ref.toString()).toList();
          }
          
          // ✅ Calcular distância e disponibilidade
          double? distanceKm;
          bool isAvailable = true;
          
          if (_lastLocation != null) {
            distanceKm = GeoDistanceHelper.distanceInKm(
              _lastLocation!.latitude,
              _lastLocation!.longitude,
              e.latitude,
              e.longitude,
            );
            
            // Regra de negócio: Premium pode aplicar em qualquer evento,
            // Free só pode aplicar em eventos dentro de 30km
            isAvailable = isPremium || distanceKm <= FREE_ACCOUNT_MAX_EVENT_DISTANCE_KM;
          }
          
          return EventModel(
            id: e.eventId,
            emoji: e.emoji,
            createdBy: e.createdBy,
            lat: e.latitude,
            lng: e.longitude,
            title: data['activityText'] as String? ?? e.title,
            category: e.category?.trim(),
            // ✅ Campos essenciais que estavam faltando:
            locationName: location?['locationName'] as String?,
            formattedAddress: location?['formattedAddress'] as String?,
            placeId: location?['placeId'] as String?,
            photoReferences: photoReferences,
            scheduleDate: scheduleDate,
            privacyType: participantsData?['privacyType'] as String? ?? 'open',
            minAge: participantsData?['minAge'] as int?,
            maxAge: participantsData?['maxAge'] as int?,
            // ✅ Campos de distância e disponibilidade
            distanceKm: distanceKm,
            isAvailable: isAvailable,
            // creatorFullName será buscado no EventCardController se necessário
          );
        })
        .toList(growable: false);

    // Mantém o mesmo objeto se nada mudou (reduz rebuilds), mas sem criar
    // "zonas mortas" onde a UI fica visualmente errada e nunca é corrigida.
    final sameLength = mapped.length == _events.length;
    final sameIds = sameLength && _events.asMap().entries.every((entry) {
      final i = entry.key;
      return entry.value.id == mapped[i].id;
    });

  // Assinatura do snapshot (inclui contexto do viewport), para permitir notify
    // quando o "mesmo dataset" precisa re-renderizar (ex.: bounds mudou,
    // counts mudaram, ou uma corrida aplicou estado visual inválido).
    final countsSignature = _eventsInBoundsCountByCategory.entries
        .map((e) => '${e.key}:${e.value}')
        .toList(growable: false)
      ..sort();
  final nextSignature = '${mapped.length}|v$_boundsSnapshotVersion|${countsSignature.join(',')}';

    if (sameIds && nextSignature == _eventsSignature) {
      debugPrint('🟣 [MapVM] early-return: sameIds && sameSignature (events.length=${_events.length})');
      return;
    }

    debugPrint('🟣 [MapVM] updating _events: ${_events.length} -> ${mapped.length} (signature=$nextSignature)');
    _events = mapped;
    _eventsSignature = nextSignature;
  eventsVersion.value = (eventsVersion.value + 1).clamp(0, 1 << 30);
    notifyListeners();
  }

  @override
  void dispose() {
    cancelAllStreams(); // Cancela streams primeiro
    _googleMarkerService.clearCache();
    _instance = null; // Limpa referência global
    super.dispose();
  }
}
