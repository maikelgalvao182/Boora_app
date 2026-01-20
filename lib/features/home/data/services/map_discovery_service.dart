import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/event_location.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:rxdart/rxdart.dart';

/// Serviço exclusivo para descoberta de eventos por bounding box
/// 
/// Implementa o padrão Airbnb de bounded queries:
/// - Query por região visível do mapa
/// - Cache com TTL
/// - Debounce automático
/// - Stream reativa para atualizar o drawer
/// 
/// Totalmente separado de filtros sociais e raio.
class MapDiscoveryService {
  // Singleton
  static final MapDiscoveryService _instance = MapDiscoveryService._internal();
  factory MapDiscoveryService() => _instance;
  
  MapDiscoveryService._internal() {
    debugPrint('🎉 MapDiscoveryService: Singleton criado (primeira vez)');
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ValueNotifier para eventos próximos (evita rebuilds desnecessários)
  final ValueNotifier<List<EventLocation>> nearbyEvents = ValueNotifier([]);
  
  // Stream para atualizar o drawer (mantido para compatibilidade)
  // BehaviorSubject mantém o último valor emitido, então novos listeners
  // recebem imediatamente os dados já disponíveis
  final _eventsController = BehaviorSubject<List<EventLocation>>.seeded(const []);
  Stream<List<EventLocation>> get eventsStream => _eventsController.stream;

  // Cache
  List<EventLocation> _cachedEvents = [];
  DateTime _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastQuadkey;

  // Configurações
  /// TTL do cache por quadkey. 30s balanceia freshness vs economia de reads.
  /// Em uso casual, usuário pode pan/zoom e voltar pro mesmo lugar.
  static const Duration cacheTTL = Duration(seconds: 30);
  static const Duration debounceTime = Duration(milliseconds: 500);
  static const int maxEventsPerQuery = 100;

  // Debounce
  Timer? _debounceTimer;
  MapBounds? _pendingBounds;

  // Estado
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Carrega eventos dentro do bounding box
  /// 
  /// Aplica debounce automático para evitar queries excessivas
  /// durante o movimento do mapa.
  Future<void> loadEventsInBounds(MapBounds bounds) async {
    _pendingBounds = bounds;

    // Cancelar timer anterior
    _debounceTimer?.cancel();

    // Criar novo timer
    _debounceTimer = Timer(debounceTime, () {
      if (_pendingBounds != null) {
        _executeQuery(_pendingBounds!);
        _pendingBounds = null;
      }
    });
  }

  /// Executa a query no Firestore
  Future<void> _executeQuery(MapBounds bounds) async {
    // Verificar cache por quadkey
    final quadkey = bounds.toQuadkey();
    
    if (_shouldUseCache(quadkey)) {
      debugPrint('📦 [MapDiscovery] Cache: ${_cachedEvents.length} eventos');
      nearbyEvents.value = _cachedEvents;
      _eventsController.add(_cachedEvents);
      return;
    }

    _isLoading = true;
    debugPrint('🔍 MapDiscoveryService: Buscando eventos em $bounds');

    try {
      final events = await _queryFirestore(bounds);
      
      _cachedEvents = events;
      _lastFetchTime = DateTime.now();
      _lastQuadkey = quadkey;
      
      debugPrint('✅ MapDiscoveryService: ${events.length} eventos encontrados');
      nearbyEvents.value = events;
      _eventsController.add(events);
    } catch (error) {
      debugPrint('❌ MapDiscoveryService: Erro na query: $error');
      _eventsController.addError(error);
    } finally {
      _isLoading = false;
    }
  }

  /// Verifica se deve usar o cache
  bool _shouldUseCache(String quadkey) {
    if (_lastQuadkey != quadkey) return false;
    
    final elapsed = DateTime.now().difference(_lastFetchTime);
    return elapsed < cacheTTL;
  }

  /// Query no Firestore usando bounding box
  /// 
  /// Firestore suporta apenas 1 range query por vez,
  /// então fazemos a query por latitude e filtramos longitude em código.
  /// 
  /// Filtra eventos com isActive = false (desativados pela Cloud Function)
  Future<List<EventLocation>> _queryFirestore(MapBounds bounds) async {
    final query = await _firestore
        .collection('events')
        .where('isActive', isEqualTo: true) // ⭐ Filtrar apenas eventos ativos
        .where('location.latitude', isGreaterThanOrEqualTo: bounds.minLat)
        .where('location.latitude', isLessThanOrEqualTo: bounds.maxLat)
        .limit(maxEventsPerQuery)
        .get();

    final events = <EventLocation>[];

    for (final doc in query.docs) {
      try {
        final data = doc.data();

        // Filtros defensivos (evita cards vazios no drawer)
        // - Cancelados
        // - Status != active (quando presente)
        final isCanceled = data['isCanceled'] as bool? ?? false;
        if (isCanceled) {
          continue;
        }

        final status = data['status'] as String?;
        if (status != null && status != 'active') {
          continue;
        }

        final event = EventLocation.fromFirestore(doc.id, doc.data());
        
        // Filtrar por longitude (Firestore não permite 2 ranges)
        if (bounds.contains(event.latitude, event.longitude)) {
          events.add(event);
        }
      } catch (error) {
        debugPrint('⚠️ MapDiscoveryService: Erro ao processar evento ${doc.id}: $error');
      }
    }

    return events;
  }

  /// Força atualização imediata (ignora cache e debounce)
  Future<void> forceRefresh(MapBounds bounds) async {
    _debounceTimer?.cancel();
    _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(0);
    await _executeQuery(bounds);
  }

  /// Limpa o cache
  void clearCache() {
    _cachedEvents = [];
    _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(0);
    _lastQuadkey = null;
    debugPrint('🧹 MapDiscoveryService: Cache limpo');
  }

  /// Dispose
  void dispose() {
    _debounceTimer?.cancel();
    _eventsController.close();
  }
}
