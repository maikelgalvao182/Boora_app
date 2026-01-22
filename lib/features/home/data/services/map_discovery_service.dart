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
  // Para mapa, 500ms costuma dar sensação de lag e aumenta a janela de corrida.
  // 200ms mantém proteção contra spam sem prejudicar a UX.
  static const Duration debounceTime = Duration(milliseconds: 200);
  static const int maxEventsPerQuery = 100;

  // Sequência monotônica de requests para descartar respostas antigas.
  // Isso evita a corrida: request A (lento) termina depois de request B (rápido)
  // e sobrescreve o estado com dados velhos.
  int _requestSeq = 0;

  // Debounce
  Timer? _debounceTimer;
  MapBounds? _pendingBounds;
  
  /// Completer que é completado quando a query (ou cache hit) efetivamente termina.
  /// Isso permite que callers de `loadEventsInBounds` aguardem o resultado real.
  Completer<void>? _activeQueryCompleter;

  // Estado
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Carrega eventos dentro do bounding box
  /// 
  /// Aplica debounce automático para evitar queries excessivas
  /// durante o movimento do mapa.
  /// 
  /// **Importante**: este método aguarda a query completar (incluindo debounce)
  /// para que o caller possa consumir `nearbyEvents.value` logo após o await.
  Future<void> loadEventsInBounds(MapBounds bounds) async {
    _pendingBounds = bounds;

    // Marca que existe um request mais recente; se houver outro load antes do
    // debounce estourar, o seq muda e o anterior perde.
    final int requestId = ++_requestSeq;

    // Cancelar timer anterior (vai re-agendar com novo debounce)
    _debounceTimer?.cancel();

    // Se já existe um completer ativo (query em andamento ou agendada),
    // reutilizamos para que todos os callers aguardem o mesmo resultado.
    // Se não existe, criamos um novo.
    _activeQueryCompleter ??= Completer<void>();
    final completerToAwait = _activeQueryCompleter!;

    // Criar novo timer
    _debounceTimer = Timer(debounceTime, () async {
      final boundsToQuery = _pendingBounds;
      _pendingBounds = null;
      
      if (boundsToQuery != null) {
        await _executeQuery(boundsToQuery, requestId);
      }
      
      // Completa o completer (permite todos os callers prosseguirem)
      final c = _activeQueryCompleter;
      _activeQueryCompleter = null;
      if (c != null && !c.isCompleted) {
        c.complete();
      }
    });

    // Aguarda o completer: só retorna quando a query (ou cache hit) finalizar.
    await completerToAwait.future;
  }

  /// Executa a query no Firestore
  Future<void> _executeQuery(MapBounds bounds, int requestId) async {
    // Verificar cache por quadkey
    final quadkey = bounds.toQuadkey();
    
    if (_shouldUseCache(quadkey)) {
      debugPrint('📦 [MapDiscovery] Cache: ${_cachedEvents.length} eventos');

      // Se existe um request mais novo, não publica cache velho.
      if (requestId != _requestSeq) {
        return;
      }

      nearbyEvents.value = _cachedEvents;
      _eventsController.add(_cachedEvents);
      return;
    }

    _isLoading = true;
    debugPrint('🔍 MapDiscoveryService: Buscando eventos em $bounds');

    try {
      final events = await _queryFirestore(bounds);

      // Descarta resposta velha (last-write-wins)
      if (requestId != _requestSeq) {
        return;
      }
      
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
  final int requestId = ++_requestSeq;
  await _executeQuery(bounds, requestId);
  }

  /// Remove um evento específico do cache (usado após deleção)
  /// 
  /// Isso permite atualização instantânea do mapa sem esperar o TTL expirar.
  void removeEvent(String eventId) {
    final sizeBefore = _cachedEvents.length;
    _cachedEvents = _cachedEvents.where((e) => e.eventId != eventId).toList();
    
    if (_cachedEvents.length < sizeBefore) {
      debugPrint('🗑️ MapDiscoveryService: Evento $eventId removido do cache');
      // Atualizar os listeners
      nearbyEvents.value = _cachedEvents;
      _eventsController.add(_cachedEvents);
    } else {
      debugPrint('⚠️ MapDiscoveryService: Evento $eventId não encontrado no cache');
    }
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
