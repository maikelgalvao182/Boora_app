import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/services/analytics_service.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/core/services/cache/hive_initializer.dart';
import 'package:partiu/features/home/data/models/event_location.dart';
import 'package:partiu/features/home/data/models/event_location_cache.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:rxdart/rxdart.dart';

/// Serviço exclusivo para descoberta de eventos por bounding box
/// 
/// Implementa o padrão Airbnb de bounded queries:
/// - Query por região visível do mapa
/// - Cache em memória com TTL
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
    unawaited(_initializePersistentCache());
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _eventsMapCollection = 'events_map';
  static const String _eventsCollection = 'events';
  static const bool _allowEventsFallback = true;
  
  // ValueNotifier para eventos próximos (evita rebuilds desnecessários)
  final ValueNotifier<List<EventLocation>> nearbyEvents = ValueNotifier([]);
  
  // Stream para atualizar o drawer (mantido para compatibilidade)
  // BehaviorSubject mantém o último valor emitido, então novos listeners
  // recebem imediatamente os dados já disponíveis
  final _eventsController = BehaviorSubject<List<EventLocation>>.seeded(const []);
  Stream<List<EventLocation>> get eventsStream => _eventsController.stream;

  // Cache
  // Cache por "tiles" (cacheKey)
  //
  // Estratégia profissional:
  // - LRU com limite de 300 chaves
  // - TTL variável por zoomBucket (mundo muda menos que bairro)
  // - Versão do schema na chave para invalidação
  static const int _maxCachedQuadkeys = 300;

  // quadkey -> entry (cache em memória)
  final Map<String, _QuadkeyCacheEntry> _quadkeyCache = <String, _QuadkeyCacheEntry>{};
  // Ordem LRU (mais antigo no início)
  final List<String> _quadkeyLru = <String>[];

  // Configurações
  /// TTL do cache em memória por quadkey.
  /// 60–120s balanceia freshness vs economia real de reads.
  static const Duration memoryCacheTTL = Duration(seconds: 90);

  /// TTL do cache persistente (Hive) por zoomBucket.
  /// zoomBucket 0: 10 min (mundo muda pouco)
  /// zoomBucket 1/2: 5 min (cidades/bairros)
  /// zoomBucket 3: 2 min (individual, mais real-time)
  static Duration persistentCacheTTLForZoomBucket(int zoomBucket) {
    switch (zoomBucket) {
      case 0: return const Duration(minutes: 10);
      case 1:
      case 2: return const Duration(minutes: 5);
      case 3: return const Duration(minutes: 2);
      default: return const Duration(minutes: 5);
    }
  }

  /// TTL padrão para compatibilidade.
  static const Duration persistentCacheTTL = Duration(minutes: 5);

  /// Refresh em background quando o cache persistente estiver "velho".
  /// Varia por zoomBucket (metade do TTL).
  static Duration persistentSoftRefreshAgeForZoomBucket(int zoomBucket) {
    final ttl = persistentCacheTTLForZoomBucket(zoomBucket);
    return Duration(milliseconds: ttl.inMilliseconds ~/ 2);
  }
  
  static const Duration persistentSoftRefreshAge = Duration(minutes: 2);
  
  // Para mapa, 500ms costuma dar sensação de lag e aumenta a janela de corrida.
  // 600ms (Aumentado de 200ms) protege conta micro-ajustes/pans rápidos.
  static const Duration debounceTime = Duration(milliseconds: 600);
  static const int maxEventsPerQuery = 1500; // Aumentado para suportar zoom global (clusters)

  // Sequência monotônica de requests para descartar respostas antigas.
  // Isso evita a corrida: request A (lento) termina depois de request B (rápido)
  // e sobrescreve o estado com dados velhos.
  int _requestSeq = 0;
  int _lastAppliedRequestSeq = 0;
  int get lastAppliedRequestSeq => _lastAppliedRequestSeq;

  // Debounce
  Timer? _debounceTimer;
  MapBounds? _pendingBounds;
  bool _pendingPrefetchNeighbors = false;
  double? _pendingZoom;
  
  /// Calcula zoomBucket para chave de cache (mesma lógica do MapBoundsController)
  int _zoomBucket(double? zoom) {
    if (zoom == null) return 2; // default: transição
    if (zoom <= 8) return 0;   // muito afastado
    if (zoom <= 11) return 1;  // clusters médios
    if (zoom <= 14) return 2;  // transição
    return 3;                  // markers individuais
  }
  
  /// Completer que é completado quando a query (ou cache hit) efetivamente termina.
  /// Isso permite que callers de `loadEventsInBounds` aguardem o resultado real.
  Completer<void>? _activeQueryCompleter;

  // Tombstones: IDs de eventos deletados na sessão atual
  // Previne ressurreição de markers se o cache I/O for lento ou falhar
  final Set<String> _tombstones = <String>{};

  // Cache persistente (Hive)
  final HiveCacheService<List<EventLocationCache>> _persistentCache =
      HiveCacheService<List<EventLocationCache>>('events_map_tiles');
  bool _persistentCacheReady = false;

  // Estado
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Prefetch adjacente
  bool _isPrefetching = false;
  String? _lastPrefetchQuadkey;
  static const int _maxPrefetchNeighbors = 8;

  /// Carrega eventos dentro do bounding box
  /// 
  /// Aplica debounce automático para evitar queries excessivas
  /// durante o movimento do mapa.
  /// 
  /// [zoom] - Nível de zoom atual do mapa (usado para calcular zoomBucket na chave de cache)
  /// 
  /// **Importante**: este método aguarda a query completar (incluindo debounce)
  /// para que o caller possa consumir `nearbyEvents.value` logo após o await.
  Future<void> loadEventsInBounds(
    MapBounds bounds, {
    bool prefetchNeighbors = false,
    double? zoom,
  }) async {
    _pendingBounds = bounds;
    _pendingPrefetchNeighbors = prefetchNeighbors;
    _pendingZoom = zoom;

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
      final zoomToQuery = _pendingZoom;
      _pendingBounds = null;
      _pendingZoom = null;
      
      if (boundsToQuery != null) {
        final shouldPrefetch = _pendingPrefetchNeighbors;
        await _executeQuery(boundsToQuery, requestId, prefetchNeighbors: shouldPrefetch, zoom: zoomToQuery);
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
    double? zoom,
  }) async {
    final sw = Stopwatch()..start();
    String boundsKey(MapBounds b) {
      return '${b.minLat.toStringAsFixed(3)}_'
          '${b.minLng.toStringAsFixed(3)}_'
          '${b.maxLat.toStringAsFixed(3)}_'
          '${b.maxLng.toStringAsFixed(3)}';
    }

    // Calcular zoomBucket para chave de cache
    final zoomBucket = _zoomBucket(zoom);

    // Verificar cache por cacheKey (inclui zoomBucket e versão)
    final cacheKey = bounds.toCacheKey(zoomBucket: zoomBucket);
    final quadkey = bounds.toQuadkey(); // Para logs e prefetch
    final bKey = boundsKey(bounds);
    debugPrint('🔎 [MapDiscovery] queryStart(seq=$requestId, boundsKey=$bKey, cacheKey=$cacheKey, source=unknown)');

    // 1️⃣ Tenta cache em memória primeiro (mais rápido)
    // ⚠️ IMPORTANTE: usar cacheKey (inclui zoomBucket) para consistência com Hive
    // ✅ FIX: Validar cobertura do cache, não apenas cacheKey
    final memoryCached = _getFromMemoryCacheIfFresh(cacheKey, requestedBounds: bounds);
    if (memoryCached != null) {
      final entry = _quadkeyCache[cacheKey];
      final remaining = entry == null
          ? null
          : memoryCacheTTL - DateTime.now().difference(entry.fetchedAt);
      final remainingSec = remaining == null ? 'unknown' : remaining.inSeconds.toString();
      debugPrint(
        '📦 [MapDiscovery] Memory cache HIT (cacheKey=$cacheKey, ttlRemainingSec=$remainingSec, events=${memoryCached.length})',
      );

      // Se existe um request mais novo, não publica cache velho.
      if (requestId != _requestSeq) {
        return;
      }

      // Aplica Tombstones
      _lastAppliedRequestSeq = requestId;
      final filtered = memoryCached.where((e) => !_tombstones.contains(e.eventId)).toList();
      nearbyEvents.value = filtered;
      _eventsController.add(filtered);
      if (prefetchNeighbors) {
        unawaited(_prefetchAdjacentQuadkeys(bounds, quadkey));
      }
      debugPrint(
        '✅ [MapDiscovery] queryEnd(seq=$requestId, boundsKey=$bKey, count=${filtered.length}, wasEmpty=${filtered.isEmpty}, source=cache, latencyMs=${sw.elapsedMilliseconds})',
      );
      return;
    }

    // 2️⃣ Cache miss - busca do Firestore
    _isLoading = true;
    debugPrint('🔍 MapDiscoveryService: Buscando eventos em $bounds');

    try {
      final events = await _queryFirestore(bounds);

      // Descarta resposta velha (last-write-wins)
      if (requestId != _requestSeq) {
        return;
      }
      
      // 3️⃣ Salva no cache em memória (usa cacheKey - mesma chave do Hive)
      // ⚠️ Não cachear lista vazia (evita cache HIT errado após zoom)
      if (events.isNotEmpty) {
        _putInMemoryCache(cacheKey, events, bounds);
      }

      // 4️⃣ Salva no cache persistente Hive (usa cacheKey com zoomBucket e TTL variável)
      // ⚠️ Não cachear lista vazia agressivamente
      if (events.isNotEmpty) {
        await _putInPersistentCache(cacheKey, events, zoomBucket: zoomBucket);
      }
      
      debugPrint('✅ MapDiscoveryService: ${events.length} eventos encontrados');
      
      // Aplica Tombstones
      _lastAppliedRequestSeq = requestId;
      final filtered = events.where((e) => !_tombstones.contains(e.eventId)).toList();
      nearbyEvents.value = filtered;
      _eventsController.add(filtered);

      if (prefetchNeighbors) {
        unawaited(_prefetchAdjacentQuadkeys(bounds, quadkey));
      }
      debugPrint(
        '✅ [MapDiscovery] queryEnd(seq=$requestId, boundsKey=$bKey, count=${filtered.length}, wasEmpty=${filtered.isEmpty}, source=network, latencyMs=${sw.elapsedMilliseconds})',
      );
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
  bool tryLoadCachedEventsForBounds(MapBounds bounds, {double? zoom}) {
    return tryLoadCachedEventsForBoundsWithPrefetch(bounds, prefetchNeighbors: false, zoom: zoom);
  }

  bool tryLoadCachedEventsForBoundsWithPrefetch(
    MapBounds bounds, {
    bool prefetchNeighbors = false,
    double? zoom,
  }) {
    final quadkey = bounds.toQuadkey();
    final zoomBucket = _zoomBucket(zoom);
    final cacheKey = bounds.toCacheKey(zoomBucket: zoomBucket);
    final boundsKey = '${bounds.minLat.toStringAsFixed(3)}_'
        '${bounds.minLng.toStringAsFixed(3)}_'
        '${bounds.maxLat.toStringAsFixed(3)}_'
        '${bounds.maxLng.toStringAsFixed(3)}';

    // 1️⃣ Memory cache (usa cacheKey - mesma chave do Hive)
    // ✅ FIX: Validar cobertura do cache
    final memoryCached = _getFromMemoryCacheIfFresh(cacheKey, requestedBounds: bounds);
    if (memoryCached != null) {
      final filtered = memoryCached.where((e) => !_tombstones.contains(e.eventId)).toList();
      nearbyEvents.value = filtered;
      _eventsController.add(filtered);
      if (prefetchNeighbors) {
        unawaited(_prefetchAdjacentQuadkeys(bounds, quadkey));
      }
      return true;
    }

    // 2️⃣ Hive cache (persistente) - usa cacheKey para consistência
    final persistentEntries = _getPersistentCacheEntriesIfFresh(cacheKey);
    if (persistentEntries != null && persistentEntries.isNotEmpty) {
      final age = _getPersistentCacheAge(persistentEntries);
      final remaining = age == null ? null : persistentCacheTTL - age;
      final remainingSec = remaining == null ? 'unknown' : remaining.inSeconds.toString();
      debugPrint(
        '📦 [MapDiscovery] Hive cache HIT (cacheKey=$cacheKey, ttlRemainingSec=$remainingSec, events=${persistentEntries.length})',
      );
      final persistentCached = _convertPersistentCacheEntries(persistentEntries);
      _putInMemoryCache(cacheKey, persistentCached, bounds);

      final filtered =
          persistentCached.where((e) => !_tombstones.contains(e.eventId)).toList();
      nearbyEvents.value = filtered;
      _eventsController.add(filtered);
      if (prefetchNeighbors) {
        unawaited(_prefetchAdjacentQuadkeys(bounds, quadkey));
      }

      if (age != null && age >= persistentSoftRefreshAge) {
        unawaited(_revalidateInBackground(bounds, cacheKey));
      }

      debugPrint(
        '✅ [MapDiscovery] queryEnd(seq=${_requestSeq}, boundsKey=$boundsKey, count=${filtered.length}, wasEmpty=${filtered.isEmpty}, source=hive, latencyMs=0)',
      );
      return true;
    }

    return false;
  }

  /// Soft-apply de cache: só publica se houver novos eventos
  /// (evita setState desnecessário durante pan)
  bool applyCachedEventsIfNew(MapBounds bounds, {double? zoom}) {
    final zoomBucket = _zoomBucket(zoom);
    final cacheKey = bounds.toCacheKey(zoomBucket: zoomBucket);

    List<EventLocation>? cached;

    // Usa cacheKey (mesma chave do Hive) para consistência
    // ✅ FIX: Validar cobertura do cache
    final memoryCached = _getFromMemoryCacheIfFresh(cacheKey, requestedBounds: bounds);
    if (memoryCached != null) {
      cached = memoryCached;
    }

    if (cached == null) {
      final persistentEntries = _getPersistentCacheEntriesIfFresh(cacheKey);
      if (persistentEntries != null && persistentEntries.isNotEmpty) {
        cached = _convertPersistentCacheEntries(persistentEntries);
        _putInMemoryCache(cacheKey, cached, bounds);
      }
    }

    if (cached == null) return false;

    // Filter tombstones
    final filtered = cached.where((e) => !_tombstones.contains(e.eventId)).toList();
    if (filtered.isEmpty && cached.isNotEmpty) return false; // If all were tombstones, treated as empty

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

        // Usar cacheKey com zoomBucket default (2) para prefetch
        final neighborCacheKey = neighbor.toCacheKey(zoomBucket: 2);
        if (seen.contains(neighborCacheKey)) continue;
        seen.add(neighborCacheKey);

        // Se já existe cache em memória, pula
        if (_getFromMemoryCacheIfFresh(neighborCacheKey, requestedBounds: neighbor) != null) continue;

        // Fetch best-effort em background
        try {
          final events = await _queryFirestore(neighbor);
          if (events.isEmpty) continue; // Não cachear vazio
          _putInMemoryCache(neighborCacheKey, events, neighbor);
          await _putInPersistentCache(neighborCacheKey, events);
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
  Future<void> _revalidateInBackground(MapBounds bounds, String cacheKey) async {
    try {
      final freshEvents = await _queryFirestore(bounds);
      
      // Atualiza caches (só se não vazio)
      if (freshEvents.isNotEmpty) {
        _putInMemoryCache(cacheKey, freshEvents, bounds);
        await _putInPersistentCache(cacheKey, freshEvents);
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

  List<EventLocation>? _getFromMemoryCacheIfFresh(String quadkey, {MapBounds? requestedBounds}) {
    final entry = _quadkeyCache[quadkey];
    if (entry == null) return null;

    final elapsed = DateTime.now().difference(entry.fetchedAt);
    if (elapsed >= memoryCacheTTL) {
      // Expirou.
      _quadkeyCache.remove(quadkey);
      _quadkeyLru.remove(quadkey);
      return null;
    }
    
    // ✅ FIX: Validar cobertura do cache, não apenas cacheKey
    if (requestedBounds != null && !entry.covers(requestedBounds)) {
      debugPrint('⚠️ [MapDiscovery] Cache key HIT mas COBERTURA insuficiente - indo pra rede');
      return null;
    }

    // Toca no LRU.
    _quadkeyLru.remove(quadkey);
    _quadkeyLru.add(quadkey);

    return entry.events;
  }

  void _putInMemoryCache(String quadkey, List<EventLocation> events, MapBounds coverage) {
    _quadkeyCache[quadkey] = _QuadkeyCacheEntry(
      events: events,
      fetchedAt: DateTime.now(),
      coverage: coverage,
    );

    _quadkeyLru.remove(quadkey);
    _quadkeyLru.add(quadkey);

    // Evict LRU.
    while (_quadkeyLru.length > _maxCachedQuadkeys) {
      final evictKey = _quadkeyLru.removeAt(0);
      _quadkeyCache.remove(evictKey);
    }
  }

  Future<void> _initializePersistentCache() async {
    if (_persistentCacheReady) return;
    try {
      await HiveInitializer.initialize();
      await _persistentCache.initialize();
      _persistentCacheReady = true;
    } catch (e) {
      debugPrint('📦 [MapDiscovery] Hive init error: $e');
    }
  }

  /// Lê do cache persistente Hive.
  /// 
  /// [key] pode ser quadkey simples (legado) ou cacheKey com zoomBucket (novo).
  List<EventLocationCache>? _getPersistentCacheEntriesIfFresh(String key) {
    if (!_persistentCacheReady || !_persistentCache.isInitialized) return null;
    return _persistentCache.get(key);
  }

  List<EventLocation> _convertPersistentCacheEntries(
    List<EventLocationCache> entries,
  ) {
    return entries
        .map((e) => EventLocation(
              eventId: e.eventId,
              latitude: e.latitude,
              longitude: e.longitude,
              eventData: e.toMinimalEventData(),
            ))
        .toList();
  }

  Duration? _getPersistentCacheAge(List<EventLocationCache> entries) {
    if (entries.isEmpty) return null;
    final cachedAtMillis = entries.first.cachedAtMillis;
    final ageMillis =
        DateTime.now().millisecondsSinceEpoch - cachedAtMillis;
    return Duration(milliseconds: ageMillis);
  }

  Future<void> _putInPersistentCache(
    String cacheKey,
    List<EventLocation> events, {
    int zoomBucket = 2,
  }) async {
    if (!_persistentCacheReady || !_persistentCache.isInitialized) return;
    final cacheEntries = events
        .map((e) => EventLocationCache.fromEventLocation(
              e.eventId,
              e.latitude,
              e.longitude,
              e.eventData,
            ))
        .toList();

    final ttl = persistentCacheTTLForZoomBucket(zoomBucket);
    await _persistentCache.put(
      cacheKey,
      cacheEntries,
      ttl: ttl,
    );
  }

  /// Query no Firestore usando bounding box
  /// 
  /// Firestore suporta apenas 1 range query por vez,
  /// então fazemos a query por latitude e filtramos longitude em código.
  /// 
  /// ✅ NOTA: events_map DESATIVADO (estava vazio/desatualizado)
  /// Agora usa apenas a coleção `events` diretamente.
  Future<List<EventLocation>> _queryFirestore(MapBounds bounds) async {
    // ========================================
    // ✅ QUERY DIRETA NA COLEÇÃO `events`
    // events_map estava vazio, então vamos direto na fonte
    // ========================================
    debugPrint('🔍 [events] Query direta na coleção events...');
    
    final query = await _firestore
        .collection(_eventsCollection)
        .where('isActive', isEqualTo: true)
        .where('location.latitude', isGreaterThanOrEqualTo: bounds.minLat)
        .where('location.latitude', isLessThanOrEqualTo: bounds.maxLat)
        .limit(maxEventsPerQuery)
        .get();

    debugPrint('🧪 [events] fetched=${query.docs.length} '
      'lat=[${bounds.minLat.toStringAsFixed(3)}..${bounds.maxLat.toStringAsFixed(3)}] '
      'lng=[${bounds.minLng.toStringAsFixed(3)}..${bounds.maxLng.toStringAsFixed(3)}]');

    final events = <EventLocation>[];
    int docsFilteredByLongitude = 0;

    for (final doc in query.docs) {
      try {
        final data = doc.data();

        final isCanceled = data['isCanceled'] as bool? ?? false;
        if (isCanceled) continue;

        final status = data['status'] as String?;
        if (status != null && status != 'active') continue;

        final event = EventLocation.fromFirestore(doc.id, data);
        
        if (bounds.contains(event.latitude, event.longitude)) {
          events.add(event);
        } else {
          docsFilteredByLongitude++;
        }
      } catch (error) {
        debugPrint('⚠️ MapDiscoveryService: Erro ao processar evento ${doc.id}: $error');
      }
    }

    debugPrint('🧪 [events] kept=${events.length} (lngFiltered=$docsFilteredByLongitude)');

    // ✅ events_map DESATIVADO - não precisa mais de fallback
    // Agora vai direto na coleção `events`

    AnalyticsService.instance.logEvent('map_bounds_query', parameters: {
      'docs_returned': events.length,
      'docs_fetched_count': query.docs.length,
      'docs_kept_count': events.length,
      'waste_ratio': query.docs.isNotEmpty ? (1.0 - (events.length / query.docs.length)).toStringAsFixed(2) : '0.00',
      'bounds_min_lat': bounds.minLat,
      'bounds_max_lat': bounds.maxLat,
      'bounds_min_lng': bounds.minLng,
      'bounds_max_lng': bounds.maxLng,
    });

    return events;
  }

  /// Força atualização imediata (ignora cache e debounce)
  Future<void> forceRefresh(MapBounds bounds) async {
    _debounceTimer?.cancel();
    // Force refresh ignora TTL para o quadkey atual (ambos os caches).
    final quadkey = bounds.toQuadkey();
    _quadkeyCache.remove(quadkey);
    _quadkeyLru.remove(quadkey);
    final int requestId = ++_requestSeq;
    await _executeQuery(bounds, requestId);
  }

  /// Remove um evento específico do cache (usado após deleção)
  /// 
  /// Isso permite atualização instantânea do mapa sem esperar o TTL expirar.
  Future<void> removeEvent(String eventId) async {
    // 1. Adicionar ao Tombstone imediatamente (bloqueio síncrono lógico)
    _tombstones.add(eventId);
    
    var removedSomewhere = false;

    // Remove do cache em memória
    for (final key in _quadkeyCache.keys.toList(growable: false)) {
      final entry = _quadkeyCache[key];
      if (entry == null) continue;
      final before = entry.events.length;
      final next = entry.events.where((e) => e.eventId != eventId).toList(growable: false);
      if (next.length != before) {
        removedSomewhere = true;
        _quadkeyCache[key] = _QuadkeyCacheEntry(
          events: next, 
          fetchedAt: entry.fetchedAt,
          coverage: entry.coverage,
        );
      }
    }

    if (removedSomewhere || _tombstones.contains(eventId)) {
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
    debugPrint('🧹 MapDiscoveryService: Cache limpo (memória)');
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
  final MapBounds coverage; // ✅ Bounds que este cache realmente cobre

  const _QuadkeyCacheEntry({
    required this.events,
    required this.fetchedAt,
    required this.coverage,
  });
  
  /// Verifica se o cache cobre os bounds solicitados
  bool covers(MapBounds requested) {
    return coverage.minLat <= requested.minLat &&
           coverage.maxLat >= requested.maxLat &&
           coverage.minLng <= requested.minLng &&
           coverage.maxLng >= requested.maxLng;
  }
}