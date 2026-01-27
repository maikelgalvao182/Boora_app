import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/event_location.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:partiu/features/home/data/repositories/event_cache_repository.dart';
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
    // Inicializa cache persistente em background (não bloqueia)
    unawaited(ensurePersistentCacheReady());
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Cache persistente (Hive)
  final EventCacheRepository _persistentCache = EventCacheRepository();
  bool _persistentCacheReady = false;
  Completer<void>? _persistentInitCompleter;

  // ValueNotifier para eventos próximos (evita rebuilds desnecessários)
  final ValueNotifier<List<EventLocation>> nearbyEvents = ValueNotifier([]);
  
  // Stream para atualizar o drawer (mantido para compatibilidade)
  // BehaviorSubject mantém o último valor emitido, então novos listeners
  // recebem imediatamente os dados já disponíveis
  final _eventsController = BehaviorSubject<List<EventLocation>>.seeded(const []);
  Stream<List<EventLocation>> get eventsStream => _eventsController.stream;

  // Cache
  // Cache por "tiles" (quadkey)
  //
  // Antes: cache de 1 quadkey + TTL.
  // Agora: cache LRU simples por quadkey (mantém várias áreas recentes).
  // Isso reduz refetch em pans pequenos (vai e volta) e melhora a velocidade
  // de borda, mantendo a lógica atual de bounded queries.
  static const int _maxCachedQuadkeys = 12;

  // quadkey -> entry
  final Map<String, _QuadkeyCacheEntry> _quadkeyCache = <String, _QuadkeyCacheEntry>{};
  // Ordem LRU (mais antigo no início)
  final List<String> _quadkeyLru = <String>[];

  // Configurações
  /// TTL do cache em memória por quadkey. 30s balanceia freshness vs economia de reads.
  /// Em uso casual, usuário pode pan/zoom e voltar pro mesmo lugar.
  static const Duration memoryCacheTTL = Duration(seconds: 30);
  
  /// TTL do cache persistente (Hive). 20min porque eventos não mudam de lugar.
  /// Mapa vazio no cold start é MUITO pior que marker desatualizado.
  static const Duration persistentCacheTTL = Duration(minutes: 20);
  
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
  bool _pendingPrefetchNeighbors = false;
  
  /// Completer que é completado quando a query (ou cache hit) efetivamente termina.
  /// Isso permite que callers de `loadEventsInBounds` aguardem o resultado real.
  Completer<void>? _activeQueryCompleter;

  // Estado
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Prefetch adjacente
  bool _isPrefetching = false;
  String? _lastPrefetchQuadkey;
  static const int _maxPrefetchNeighbors = 8;

  /// Inicializa cache persistente em background
  Future<void> ensurePersistentCacheReady() async {
    if (_persistentCacheReady) return;

    final existing = _persistentInitCompleter;
    if (existing != null) {
      await existing.future;
      return;
    }

    final completer = Completer<void>();
    _persistentInitCompleter = completer;

    try {
      await _persistentCache.initialize();
      _persistentCacheReady = true;
      debugPrint('📦 MapDiscoveryService: Cache persistente pronto');
    } catch (e) {
      debugPrint('📦 MapDiscoveryService: Cache persistente indisponível: $e');
      // Não é crítico - funciona sem cache persistente
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      if (identical(_persistentInitCompleter, completer)) {
        _persistentInitCompleter = null;
      }
    }
  }

  /// Carrega eventos dentro do bounding box
  /// 
  /// Aplica debounce automático para evitar queries excessivas
  /// durante o movimento do mapa.
  /// 
  /// **Importante**: este método aguarda a query completar (incluindo debounce)
  /// para que o caller possa consumir `nearbyEvents.value` logo após o await.
  Future<void> loadEventsInBounds(
    MapBounds bounds, {
    bool prefetchNeighbors = false,
  }) async {
    _pendingBounds = bounds;
    _pendingPrefetchNeighbors = prefetchNeighbors;

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
        final shouldPrefetch = _pendingPrefetchNeighbors;
        await _executeQuery(boundsToQuery, requestId, prefetchNeighbors: shouldPrefetch);
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
  /// 
  /// Estratégia: Stale-While-Revalidate
  /// 1. Tenta cache em memória (mais rápido, TTL curto)
  /// 2. Tenta cache persistente Hive (cold start, TTL longo)
  /// 3. Se ambos miss, busca do Firestore
  /// 4. Salva em ambos os caches
  Future<void> _executeQuery(
    MapBounds bounds,
    int requestId, {
    bool prefetchNeighbors = false,
  }) async {
    // Verificar cache por quadkey
    final quadkey = bounds.toQuadkey();

    // 1️⃣ Tenta cache em memória primeiro (mais rápido)
    final memoryCached = _getFromMemoryCacheIfFresh(quadkey);
    if (memoryCached != null) {
      debugPrint('📦 [MapDiscovery] Memory cache HIT (quadkey=$quadkey): ${memoryCached.length} eventos');

      // Se existe um request mais novo, não publica cache velho.
      if (requestId != _requestSeq) {
        return;
      }

      nearbyEvents.value = memoryCached;
      _eventsController.add(memoryCached);
      if (prefetchNeighbors) {
        unawaited(_prefetchAdjacentQuadkeys(bounds, quadkey));
      }
      return;
    }

    // 2️⃣ Tenta cache persistente (Hive) - útil no cold start
    if (_persistentCacheReady) {
      final persistentCached = _persistentCache.getEvents(quadkey);
      if (persistentCached != null) {
        debugPrint('📦 [MapDiscovery] Persistent cache HIT (quadkey=$quadkey): ${persistentCached.length} eventos');

        if (requestId != _requestSeq) {
          return;
        }

        // Publica imediatamente (UI rápida)
        nearbyEvents.value = persistentCached;
        _eventsController.add(persistentCached);
        
        // Também salva no cache em memória para próximas consultas
        _putInMemoryCache(quadkey, persistentCached);
        
        // 🔄 Stale-While-Revalidate: atualiza em background
        unawaited(_revalidateInBackground(bounds, quadkey));
        if (prefetchNeighbors) {
          unawaited(_prefetchAdjacentQuadkeys(bounds, quadkey));
        }
        return;
      }
    }

    // 3️⃣ Cache miss - busca do Firestore
    _isLoading = true;
    debugPrint('🔍 MapDiscoveryService: Buscando eventos em $bounds');

    try {
      final events = await _queryFirestore(bounds);

      // Descarta resposta velha (last-write-wins)
      if (requestId != _requestSeq) {
        return;
      }
      
      // 4️⃣ Salva em ambos os caches
      _putInMemoryCache(quadkey, events);
      if (_persistentCacheReady) {
        unawaited(_persistentCache.saveEvents(quadkey, events, ttl: persistentCacheTTL));
      }
      
      debugPrint('✅ MapDiscoveryService: ${events.length} eventos encontrados');
      nearbyEvents.value = events;
      _eventsController.add(events);
      if (prefetchNeighbors) {
        unawaited(_prefetchAdjacentQuadkeys(bounds, quadkey));
      }
    } catch (error) {
      debugPrint('❌ MapDiscoveryService: Erro na query: $error');
      _eventsController.addError(error);
    } finally {
      _isLoading = false;
    }
  }

  /// Tenta carregar cache imediatamente (sem debounce) para o bounds atual.
  ///
  /// Útil para cold start e pan rápido: mostra dados de cache antes do fetch.
  bool tryLoadCachedEventsForBounds(MapBounds bounds) {
    return tryLoadCachedEventsForBoundsWithPrefetch(bounds, prefetchNeighbors: false);
  }

  bool tryLoadCachedEventsForBoundsWithPrefetch(
    MapBounds bounds, {
    bool prefetchNeighbors = false,
  }) {
    final quadkey = bounds.toQuadkey();

    // 1️⃣ Memory cache
    final memoryCached = _getFromMemoryCacheIfFresh(quadkey);
    if (memoryCached != null) {
      nearbyEvents.value = memoryCached;
      _eventsController.add(memoryCached);
      if (prefetchNeighbors) {
        unawaited(_prefetchAdjacentQuadkeys(bounds, quadkey));
      }
      return true;
    }

    // 2️⃣ Persistent cache
    if (_persistentCacheReady) {
      final persistentCached = _persistentCache.getEvents(quadkey);
      if (persistentCached != null) {
        nearbyEvents.value = persistentCached;
        _eventsController.add(persistentCached);
        _putInMemoryCache(quadkey, persistentCached);
        if (prefetchNeighbors) {
          unawaited(_prefetchAdjacentQuadkeys(bounds, quadkey));
        }
        return true;
      }
    }

    return false;
  }

  /// Soft-apply de cache: só publica se houver novos eventos
  /// (evita setState desnecessário durante pan)
  bool applyCachedEventsIfNew(MapBounds bounds) {
    final quadkey = bounds.toQuadkey();

    List<EventLocation>? cached;

    final memoryCached = _getFromMemoryCacheIfFresh(quadkey);
    if (memoryCached != null) {
      cached = memoryCached;
    } else if (_persistentCacheReady) {
      final persisted = _persistentCache.getEvents(quadkey);
      if (persisted != null) {
        cached = persisted;
        _putInMemoryCache(quadkey, persisted);
      }
    }

    if (cached == null) return false;

    final current = nearbyEvents.value;
    if (current.isEmpty) {
      nearbyEvents.value = cached;
      _eventsController.add(cached);
      return true;
    }

    final currentIds = current.map((e) => e.eventId).toSet();
    final cachedIds = cached.map((e) => e.eventId).toSet();

    final hasNew = !currentIds.containsAll(cachedIds);
    final lengthChanged = current.length != cached.length;

    if (hasNew || lengthChanged) {
      nearbyEvents.value = cached;
      _eventsController.add(cached);
      return true;
    }

    return false;
  }

  Future<void> _prefetchAdjacentQuadkeys(MapBounds bounds, String centerQuadkey) async {
    if (_isPrefetching) return;
    if (_lastPrefetchQuadkey == centerQuadkey) return;
    _isPrefetching = true;
    _lastPrefetchQuadkey = centerQuadkey;

    try {
      final neighbors = _buildNeighborBounds(bounds, ring: 1);
      final seen = <String>{centerQuadkey};
      var fetched = 0;

      for (final neighbor in neighbors) {
        if (fetched >= _maxPrefetchNeighbors) break;

        final quadkey = neighbor.toQuadkey();
        if (seen.contains(quadkey)) continue;
        seen.add(quadkey);

        // Se já existe cache em memória, pula
        if (_getFromMemoryCacheIfFresh(quadkey) != null) continue;

        // Se existe no cache persistente, só aquece memória
        if (_persistentCacheReady) {
          final persisted = _persistentCache.getEvents(quadkey);
          if (persisted != null) {
            _putInMemoryCache(quadkey, persisted);
            continue;
          }
        }

        // Fetch best-effort em background
        try {
          final events = await _queryFirestore(neighbor);
          if (events.isEmpty) continue;
          _putInMemoryCache(quadkey, events);
          if (_persistentCacheReady) {
            unawaited(_persistentCache.saveEvents(quadkey, events, ttl: persistentCacheTTL));
          }
          fetched++;
        } catch (_) {
          // Ignorar falhas de prefetch
        }
      }
    } finally {
      _isPrefetching = false;
    }
  }

  List<MapBounds> _buildNeighborBounds(MapBounds bounds, {int ring = 1}) {
    final latSpan = bounds.maxLat - bounds.minLat;
    final lngSpan = bounds.maxLng - bounds.minLng;

    if (latSpan == 0 || lngSpan == 0) return const [];

    final centerLat = (bounds.minLat + bounds.maxLat) / 2.0;
    final centerLng = (bounds.minLng + bounds.maxLng) / 2.0;

    double clampLat(double v) => v.clamp(-90.0, 90.0);
    double clampLng(double v) => v.clamp(-180.0, 180.0);

    final neighbors = <MapBounds>[];
    for (var y = -ring; y <= ring; y++) {
      for (var x = -ring; x <= ring; x++) {
        if (x == 0 && y == 0) continue;

        final newCenterLat = clampLat(centerLat + (y * latSpan));
        final newCenterLng = clampLng(centerLng + (x * lngSpan));

        final halfLat = latSpan / 2.0;
        final halfLng = lngSpan / 2.0;

        neighbors.add(MapBounds(
          minLat: clampLat(newCenterLat - halfLat),
          maxLat: clampLat(newCenterLat + halfLat),
          minLng: clampLng(newCenterLng - halfLng),
          maxLng: clampLng(newCenterLng + halfLng),
        ));
      }
    }
    return neighbors;
  }

  /// Revalida cache em background (Stale-While-Revalidate)
  /// 
  /// Busca dados frescos do Firestore e atualiza UI se houver diferença
  Future<void> _revalidateInBackground(MapBounds bounds, String quadkey) async {
    try {
      final freshEvents = await _queryFirestore(bounds);
      
      // Atualiza caches
      _putInMemoryCache(quadkey, freshEvents);
      if (_persistentCacheReady) {
        unawaited(_persistentCache.saveEvents(quadkey, freshEvents, ttl: persistentCacheTTL));
      }
      
      // Só atualiza UI se o quadkey ainda for relevante (usuário não moveu o mapa)
      final currentEvents = nearbyEvents.value;
      if (_hasSignificantChanges(currentEvents, freshEvents)) {
        debugPrint('🔄 [MapDiscovery] Background revalidation: ${freshEvents.length} eventos (atualizado)');
        nearbyEvents.value = freshEvents;
        _eventsController.add(freshEvents);
      }
    } catch (e) {
      // Silencioso - já temos dados do cache
      debugPrint('⚠️ [MapDiscovery] Background revalidation failed: $e');
    }
  }

  /// Verifica se há diferenças significativas entre listas de eventos
  bool _hasSignificantChanges(List<EventLocation> old, List<EventLocation> fresh) {
    if (old.length != fresh.length) return true;
    
    final oldIds = old.map((e) => e.eventId).toSet();
    final freshIds = fresh.map((e) => e.eventId).toSet();
    
    return !oldIds.containsAll(freshIds) || !freshIds.containsAll(oldIds);
  }

  List<EventLocation>? _getFromMemoryCacheIfFresh(String quadkey) {
    final entry = _quadkeyCache[quadkey];
    if (entry == null) return null;

    final elapsed = DateTime.now().difference(entry.fetchedAt);
    if (elapsed >= memoryCacheTTL) {
      // Expirou.
      _quadkeyCache.remove(quadkey);
      _quadkeyLru.remove(quadkey);
      return null;
    }

    // Toca no LRU.
    _quadkeyLru.remove(quadkey);
    _quadkeyLru.add(quadkey);

    return entry.events;
  }

  void _putInMemoryCache(String quadkey, List<EventLocation> events) {
    _quadkeyCache[quadkey] = _QuadkeyCacheEntry(
      events: events,
      fetchedAt: DateTime.now(),
    );

    _quadkeyLru.remove(quadkey);
    _quadkeyLru.add(quadkey);

    // Evict LRU.
    while (_quadkeyLru.length > _maxCachedQuadkeys) {
      final evictKey = _quadkeyLru.removeAt(0);
      _quadkeyCache.remove(evictKey);
    }
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
    // Force refresh ignora TTL para o quadkey atual (ambos os caches).
    final quadkey = bounds.toQuadkey();
    _quadkeyCache.remove(quadkey);
    _quadkeyLru.remove(quadkey);
    if (_persistentCacheReady) {
      unawaited(_persistentCache.invalidate(quadkey));
    }
    final int requestId = ++_requestSeq;
    await _executeQuery(bounds, requestId);
  }

  /// Remove um evento específico do cache (usado após deleção)
  /// 
  /// Isso permite atualização instantânea do mapa sem esperar o TTL expirar.
  void removeEvent(String eventId) {
    var removedSomewhere = false;

    // Remove do cache em memória
    for (final key in _quadkeyCache.keys.toList(growable: false)) {
      final entry = _quadkeyCache[key];
      if (entry == null) continue;
      final before = entry.events.length;
      final next = entry.events.where((e) => e.eventId != eventId).toList(growable: false);
      if (next.length != before) {
        removedSomewhere = true;
        _quadkeyCache[key] = _QuadkeyCacheEntry(events: next, fetchedAt: entry.fetchedAt);
      }
    }

    // Remove do cache persistente também
    if (_persistentCacheReady) {
      unawaited(_persistentCache.removeEvent(eventId));
    }

    if (removedSomewhere) {
      debugPrint('🗑️ MapDiscoveryService: Evento $eventId removido do cache (multi-tiles)');
      // Se o evento removido estava no snapshot atual, publica a lista atualizada
      // para manter o mapa consistente.
      final current = nearbyEvents.value;
      if (current.any((e) => e.eventId == eventId)) {
        final next = current.where((e) => e.eventId != eventId).toList(growable: false);
        nearbyEvents.value = next;
        _eventsController.add(next);
      }
    }
  }

  /// Limpa o cache (memória + persistente)
  void clearCache() {
    _quadkeyCache.clear();
    _quadkeyLru.clear();
    if (_persistentCacheReady) {
      unawaited(_persistentCache.clear());
    }
    debugPrint('🧹 MapDiscoveryService: Cache limpo (memória + persistente)');
  }

  /// Dispose
  void dispose() {
    _debounceTimer?.cancel();
    _eventsController.close();
  }
}

class _QuadkeyCacheEntry {
  final List<EventLocation> events;
  final DateTime fetchedAt;

  const _QuadkeyCacheEntry({
    required this.events,
    required this.fetchedAt,
  });
}