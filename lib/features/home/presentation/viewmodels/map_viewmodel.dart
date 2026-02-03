import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart' as firebase_firestore;
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/geo_distance_helper.dart';
import 'package:partiu/core/utils/geohash_helper.dart';
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
import 'package:partiu/features/location/data/repositories/location_repository.dart';
import 'package:partiu/features/location/domain/repositories/location_repository_interface.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get_it/get_it.dart';

part 'parts/map_viewmodel_location.part.dart';
part 'parts/map_viewmodel_sync.part.dart';
part 'parts/map_viewmodel_realtime.part.dart';
part 'parts/map_viewmodel_markers.part.dart';

/// ViewModel responsável por gerenciurus a estado e lógica do mapa Google Maps
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

  // Mecanismo de Pinning para evitar que eventos sejam removidos da memória durante Push Navigation
  // Isso evita o cenário de race condition onde o evento é injetado, o bounds sync roda e limpa tudo.
  String? _pinnedEventId;
  DateTime? _pinnedUntil;

  /// Pina um evento na memória por alguns segundos para garantir que não seja limpo pelo sync.
  void pinEvent(String eventId) {
    debugPrint('📌 [MapVM] Pinning event: $eventId (preservando por 5s)');
    _pinnedEventId = eventId;
    _pinnedUntil = DateTime.now().add(const Duration(seconds: 5));
  }

  /// Verifica se o pin expirou
  bool _isPinned(String eventId) {
    if (_pinnedEventId == eventId && _pinnedUntil != null) {
      if (DateTime.now().isBefore(_pinnedUntil!)) {
        return true;
      }
      // Expirou
      _pinnedEventId = null;
      _pinnedUntil = null;
    }
    return false;
  }

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

  /// Último bounds VISÍVEL (frame atual do mapa) conhecido pelo app.
  ///
  /// Importante: isso é o *frame* (LatLngBounds do GoogleMapView) e NÃO o bounds
  /// expandido usado para reduzir churn de render.
  LatLngBounds? _visibleBounds;
  LatLngBounds? get visibleBounds => _visibleBounds;

  /// Nível de zoom atual do mapa
  double _currentZoom = 12.0;
  double get currentZoom => _currentZoom;

  /// Atualiza o snapshot do bounds visível.
  /// Chamado pelo GoogleMapView sempre que o viewport muda.
  void setVisibleBounds(LatLngBounds bounds, {double? zoom}) {
    _visibleBounds = bounds;
    if (zoom != null && (zoom - _currentZoom).abs() > 0.01) {
      _currentZoom = zoom;
    }
    notifyListeners();
  }

  String? _buildVisibleBoundsKey() {
    final bounds = _visibleBounds;
    if (bounds == null) return null;
    return '${bounds.southwest.latitude.toStringAsFixed(3)}_'
        '${bounds.southwest.longitude.toStringAsFixed(3)}_'
        '${bounds.northeast.latitude.toStringAsFixed(3)}_'
        '${bounds.northeast.longitude.toStringAsFixed(3)}';
  }

  /// Versão monotônica do dataset de eventos exposto ao mapa.
  ///
  /// Motivo: evitar o gap "ids iguais -> não notifica" + permitir que a UI
  /// detecte mudanças de dataset e force um render no idle.
  final ValueNotifier<int> eventsVersion = ValueNotifier<int>(0);
  
  // 💀 Lápides: Eventos deletados nesta sessão.
  // Impede que caches antigos "ressuscitem" o evento no mapa.
  final Set<String> _tombstones = {};

  // Stream para notificar remoção de eventos unitários (para update otimista da UI)
  final StreamController<String> _eventRemovalController = StreamController<String>.broadcast();
  Stream<String> get onEventRemoved => _eventRemovalController.stream;

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

  // Anti-vazio: evita limpar markers em vazio transitório.
  final Duration _strongEmptyWindow = const Duration(seconds: 6);
  String? _lastEmptyBoundsKey;
  DateTime? _lastEmptyAt;
  int _consecutiveEmptyForBounds = 0;

  // Single-flight para loads por bounds
  final Map<String, Future<void>> _inFlightBoundsLoads = {};

  // Cache de nomes de criadores (evita fetch duplicado)
  static const Duration _creatorNameCacheTtl = Duration(days: 1);
  final Map<String, _CreatorNameCacheEntry> _creatorNameCache = {};
  final Set<String> _creatorNameInFlight = {};

  /// Filtro de categoria selecionado para o mapa
  /// - null: mostrar todas
  /// - String: mostrar apenas eventos daquela categoria
  String? _selectedCategory;
  String? get selectedCategory => _selectedCategory;
  
  /// Filtro de data selecionado para o mapa
  /// - null: mostrar todos os dias
  /// - DateTime: mostrar apenas eventos daquele dia
  DateTime? _selectedDate;
  DateTime? get selectedDate => _selectedDate;

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
  
  /// Define o filtro de data para o mapa
  void setDateFilter(DateTime? date) {
    // Normalizar: comparar apenas dia/mês/ano
    final normalizedNew = date != null 
        ? DateTime(date.year, date.month, date.day)
        : null;
    final normalizedOld = _selectedDate != null 
        ? DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day)
        : null;
    
    if (normalizedOld == normalizedNew) return;
    _selectedDate = normalizedNew;
    _recomputeCountsInBounds();
    notifyListeners();
  }
  
  /// Verifica se um evento passa nos filtros ativos (categoria + data)
  bool _eventPassesFilters(EventModel event) {
    // Filtro de categoria
    final selectedCat = _selectedCategory;
    if (selectedCat != null && selectedCat.trim().isNotEmpty) {
      final eventCategory = event.category?.trim();
      if (eventCategory != selectedCat) return false;
    }
    
    // Filtro de data
    if (_selectedDate != null) {
      final eventDate = event.scheduleDate;
      if (eventDate == null) return false;
      
      // Comparar apenas dia/mês/ano
      if (eventDate.year != _selectedDate!.year ||
          eventDate.month != _selectedDate!.month ||
          eventDate.day != _selectedDate!.day) {
        return false;
      }
    }
    
    return true;
  }
  
  /// Verifica se um EventLocation passa nos filtros ativos (categoria + data)
  /// Usado no _recomputeCountsInBounds onde temos EventLocation, não EventModel
  bool _eventLocationPassesFilters(String? category, DateTime? scheduleDate) {
    // Filtro de categoria
    final selectedCat = _selectedCategory;
    if (selectedCat != null && selectedCat.trim().isNotEmpty) {
      final eventCategory = category?.trim();
      if (eventCategory != selectedCat) return false;
    }
    
    // Filtro de data
    if (_selectedDate != null) {
      if (scheduleDate == null) return false;
      
      // Comparar apenas dia/mês/ano
      if (scheduleDate.year != _selectedDate!.year ||
          scheduleDate.month != _selectedDate!.month ||
          scheduleDate.day != _selectedDate!.day) {
        return false;
      }
    }
    
    return true;
  }

  void _recomputeCountsInBounds() {
    final boundsEvents = _mapDiscoveryService.nearbyEvents.value;

    final countsByCategory = <String, int>{};
    int totalFiltered = 0;
    
    for (final event in boundsEvents) {
      final category = event.category;
      if (category != null && category.trim().isNotEmpty) {
        final normalized = category.trim();
        countsByCategory[normalized] = (countsByCategory[normalized] ?? 0) + 1;
      }
      
      // Contar eventos que passam nos filtros (categoria + data)
      if (_eventLocationPassesFilters(event.category, event.scheduleDate)) {
        totalFiltered++;
      }
    }

    _eventsInBoundsCount = boundsEvents.length;
    _eventsInBoundsCountByCategory = Map<String, int>.unmodifiable(countsByCategory);

    // Matching agora considera AMBOS filtros (categoria E data)
    _matchingEventsInBoundsCount = totalFiltered;
  }

  void _handleBoundsEventsChanged() {
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

  /// Callback quando um marker é tocado (recebe EventModel completo)
  Function(EventModel event)? onMarkerTap;

  /// Subscription para mudanças de raio
  StreamSubscription<double>? _radiusSubscription;
  
  /// Subscription para mudanças de filtros/reload
  StreamSubscription<void>? _reloadSubscription;

  /// Subscription para localização do usuário (Reverse Geocoding em tempo real)
  StreamSubscription<Position>? _positionSubscription;

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

  /// Injeta um evento manualmente na lista (usado após criação)
  Future<void> injectEvent(EventModel event) async {
    // Criar uma nova lista mutável a partir da lista atual
    // (necessário porque _events pode ser uma lista imutável como const [])
    final mutableEvents = List<EventModel>.from(_events);
    
    // Verificar se já existe
    final index = mutableEvents.indexWhere((e) => e.id == event.id);
    if (index >= 0) {
      mutableEvents[index] = event;
    } else {
      mutableEvents.insert(0, event);
    }
    
    // Atribuir a nova lista
    _events = mutableEvents;
    
    // Enriquecer este evento específico
    await _enrichEvents(); // Idealmente enriquecer só este, mas por segurança re-enriquecemos tudo
    
    // Regenerar markers
    await _generateGoogleMarkers();
    
    notifyListeners();
  }

  /// Remove um evento da lista e do cache (usado após deleção)
  /// 
  /// Isso permite atualização instantânea do mapa sem esperar reload.
  void removeEvent(String eventId) {
    debugPrint('🗑️ [MapViewModel] Removendo evento: $eventId');
    
    // 1. Remover do cache do MapDiscoveryService
    _mapDiscoveryService.removeEvent(eventId);
    
    // 2. Remover da lista local
    final sizeBefore = _events.length;
    _events = _events.where((e) => e.id != eventId).toList();
    
    if (_events.length < sizeBefore) {
      debugPrint('✅ [MapViewModel] Evento $eventId removido da lista local');
      
      // 3. Incrementar versão para forçar rebuild dos markers
      eventsVersion.value = (eventsVersion.value + 1).clamp(0, 1 << 30);
      
      // 4. Limpar cache de clusters (importante!)
      _googleMarkerService.clearClusterCache();
      
      // 5. Notificar via stream específico para remoção instantânea visual
      _eventRemovalController.add(eventId);
      
      notifyListeners();
    } else {
      debugPrint('⚠️ [MapViewModel] Evento $eventId não encontrado na lista local');
    }
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

  @override
  void dispose() {
    cancelAllStreams(); // Cancela streams primeiro
    _googleMarkerService.clearCache();
    _instance = null; // Limpa referência global
    super.dispose();
  }

  String? _getCachedCreatorName(String creatorId) {
    final entry = _creatorNameCache[creatorId];
    if (entry == null) return null;
    final age = DateTime.now().difference(entry.fetchedAt);
    if (age >= _creatorNameCacheTtl) {
      _creatorNameCache.remove(creatorId);
      return null;
    }
    return entry.name;
  }

  void _cacheCreatorNames(Map<String, String> names) {
    final now = DateTime.now();
    for (final entry in names.entries) {
      _creatorNameCache[entry.key] = _CreatorNameCacheEntry(
        name: entry.value,
        fetchedAt: now,
      );
    }
  }

  Future<void> _enrichCreatorNamesInBackground(List<EventModel> events) async {
    final ids = events
        .where((e) => e.creatorFullName == null)
        .map((e) => e.createdBy)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    final idsToFetch = <String>[];
    for (final id in ids) {
      if (_creatorNameInFlight.contains(id)) continue;
      if (_getCachedCreatorName(id) != null) continue;
      _creatorNameInFlight.add(id);
      idsToFetch.add(id);
    }

    if (idsToFetch.isEmpty) return;

    try {
      final usersData = await _userRepository.getUsersBasicInfo(idsToFetch);
      final creatorNames = <String, String>{};
      for (final userData in usersData) {
        final id = userData['userId'] as String?;
        final name = userData['fullName'] as String?;
        if (id != null && name != null) {
          creatorNames[id] = name;
        }
      }

      if (creatorNames.isNotEmpty) {
        _cacheCreatorNames(creatorNames);

        var changed = false;
        final updated = _events.map((event) {
          final cachedName = creatorNames[event.createdBy];
          if (cachedName != null && event.creatorFullName != cachedName) {
            changed = true;
            return event.copyWith(creatorFullName: cachedName);
          }
          return event;
        }).toList(growable: false);

        if (changed) {
          _events = updated;
          eventsVersion.value = (eventsVersion.value + 1).clamp(0, 1 << 30);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('⚠️ [MapVM] Erro ao buscar nomes de criadores (bg): $e');
    } finally {
      for (final id in idsToFetch) {
        _creatorNameInFlight.remove(id);
      }
    }
  }
}

class _CreatorNameCacheEntry {
  final String name;
  final DateTime fetchedAt;

  const _CreatorNameCacheEntry({
    required this.name,
    required this.fetchedAt,
  });
}
