# Trechos Relevantes: inFlight + emptyConfirmed

## 1. Código do inFlight (loadEventsInBounds)

```dart
// lib/features/home/presentation/viewmodels/parts/map_viewmodel_sync.part.dart
// Linhas 140-191

/// [zoom] - Nível de zoom atual (usado para calcular zoomBucket na chave de cache)
Future<void> loadEventsInBounds(
  MapBounds bounds, {
  bool prefetchNeighbors = false,
  double? zoom,
}) async {
  final loadKey = bounds.toQuadkey();
  final inFlight = _inFlightBoundsLoads[loadKey];
  if (inFlight != null) {
    debugPrint('🔵 [MapVM] loadEventsInBounds aguardando in-flight (loadKey=$loadKey)');
    await inFlight;
    return;
  }

  final future = () async {
    debugPrint('🔵 [MapVM] loadEventsInBounds start (events.length=${_events.length}, loadKey=$loadKey)');
    // Estratégia A (stale-while-revalidate): mantém eventos atuais durante o fetch.
    // A UI pode reagir ao loading (spinner), mas não apaga markers por um "vazio" transitório.
    _setLoading(true);
    try {
      // ✅ Cache imediato (sem debounce) para acelerar pan/cold start
      final usedCache = _mapDiscoveryService.tryLoadCachedEventsForBoundsWithPrefetch(
        bounds,
        prefetchNeighbors: prefetchNeighbors,
        zoom: zoom,
      );
      if (usedCache) {
        await _syncEventsFromBounds();
      }

      await _mapDiscoveryService.loadEventsInBounds(
        bounds,
        prefetchNeighbors: prefetchNeighbors,
        zoom: zoom,
      );
      debugPrint('🔵 [MapVM] loadEventsInBounds after service (nearbyEvents.value.length=${_mapDiscoveryService.nearbyEvents.value.length}, loadKey=$loadKey)');
      await _syncEventsFromBounds();
      debugPrint('🔵 [MapVM] loadEventsInBounds after sync (events.length=${_events.length}, loadKey=$loadKey)');
    } finally {
      _setLoading(false);
    }
  }();

  _inFlightBoundsLoads[loadKey] = future;
  try {
    await future;
  } finally {
    if (_inFlightBoundsLoads[loadKey] == future) {
      _inFlightBoundsLoads.remove(loadKey);
    }
  }
}
```

---

## 2. Código do emptyConfirmed (_syncEventsFromBounds)

```dart
// lib/features/home/presentation/viewmodels/parts/map_viewmodel_sync.part.dart
// Linhas 218-267

Future<void> _syncEventsFromBounds({bool forceEmpty = false}) async {
  debugPrint('🟣 [MapVM] _syncEventsFromBounds start (forceEmpty=$forceEmpty)');
  // Mesmo que a lista final não mude, houve uma tentativa de sync do viewport.
  // Atualizamos a versão para permitir notificar a UI quando necessário.
  _boundsSnapshotVersion = (_boundsSnapshotVersion + 1).clamp(0, 1 << 30);
  final boundsEvents = _mapDiscoveryService.nearbyEvents.value;
  debugPrint('🟣 [MapVM] boundsEvents.length=${boundsEvents.length} isLoading=${_mapDiscoveryService.isLoading}');
  if (boundsEvents.isEmpty) {
    // "Vazio" pode ser transitório por debounce / in-flight request.
    // ✅ FIX: Só confirma empty se a última query do activeKey foi realmente aplicada
    final appliedForActiveKey = _mapDiscoveryService.lastQueryWasAppliedForActiveKey;
    final emptyConfirmed = forceEmpty || (!_mapDiscoveryService.isLoading && appliedForActiveKey);
    debugPrint('🟣 [MapVM] boundsEvents.isEmpty => emptyConfirmed=$emptyConfirmed (appliedForActiveKey=$appliedForActiveKey, isLoading=${_mapDiscoveryService.isLoading})');

    if (emptyConfirmed) {
      final boundsKey = _buildVisibleBoundsKey();
      final now = DateTime.now();
      final withinWindow = _lastEmptyAt != null &&
          now.difference(_lastEmptyAt!) <= _strongEmptyWindow;

      if (boundsKey != null && boundsKey == _lastEmptyBoundsKey && withinWindow) {
        _consecutiveEmptyForBounds++;
      } else {
        _lastEmptyBoundsKey = boundsKey;
        _consecutiveEmptyForBounds = 1;
      }
      _lastEmptyAt = now;

      final strongEmpty = forceEmpty || _consecutiveEmptyForBounds >= 2;

      if (strongEmpty && _events.isNotEmpty) {
        final requestSeq = _mapDiscoveryService.lastAppliedRequestSeq;
        debugPrint(
          '🟣 [MapVM] clear markers (reason=empty_confirmed, requestSeq=$requestSeq, boundsKey=$boundsKey, eventsCount=${boundsEvents.length})',
        );
        debugPrint('🟣 [MapVM] clearing _events (was ${_events.length})');
        _events = const [];
        eventsVersion.value = (eventsVersion.value + 1).clamp(0, 1 << 30);
        notifyListeners();
      } else if (_events.isNotEmpty) {
        final requestSeq = _mapDiscoveryService.lastAppliedRequestSeq;
        debugPrint(
          '🟣 [MapVM] empty ignored (anti-vazio, requestSeq=$requestSeq, boundsKey=$boundsKey, eventsCount=${boundsEvents.length}, count=$_consecutiveEmptyForBounds)',
        );
      }
    }
    return;
  }

  _lastEmptyBoundsKey = null;
  _lastEmptyAt = null;
  _consecutiveEmptyForBounds = 0;
  
  // ... continua com processamento de eventos não vazios
}
```

---

## 3. Definição do _inFlightBoundsLoads

```dart
// lib/features/home/presentation/viewmodels/map_viewmodel.dart
// Linha 204

final Map<String, Future<void>> _inFlightBoundsLoads = {};
```

---

## 4. Getter lastQueryWasAppliedForActiveKey (Discovery)

```dart
// lib/features/home/data/services/map_discovery_service.dart
// Linhas 182-185

/// Verifica se a última query do boundsKey atual foi realmente aplicada.
/// 
/// Útil para o MapVM decidir se pode confirmar "empty" ou se ainda há query pendente.
bool get lastQueryWasAppliedForActiveKey => 
    _lastAppliedBoundsKey != null && 
    _lastAppliedBoundsKey == _activeBoundsKey;
```

---

## Problema Identificado

O `loadKey = bounds.toQuadkey()` é diferente de `boundsKey = bounds.toBoundsKey()`:

- **toQuadkey()**: Usa grid simplificado (centro + spanBucket)
- **toBoundsKey()**: Usa coordenadas exatas com 3 casas decimais

Isso significa que **diferentes bounds podem ter o mesmo loadKey**, fazendo com que o inFlight seja liberado pela request errada.

## Fix Já Aplicado

1. **Completer só completa se query foi APLICADA** (não stale)
2. **emptyConfirmed verifica `lastQueryWasAppliedForActiveKey`**
3. **Listener reativo no nearbyEvents** para sincronizar quando Discovery aplicar
