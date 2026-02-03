# Trechos solicitados — Sampling + Complete/Empty

## 1) Sampling aplicado (total -> N)

Arquivo: lib/features/home/data/services/map_discovery_service.dart

```dart
final entries = cells.entries.toList();
if (entries.length <= maxCells) {
  return entries.map((e) => e.key).toList(growable: false);
}

// ✅ Sampling por distância ao centro (determinístico e relevante)
entries.sort((a, b) => a.value.compareTo(b.value));
final sampled = entries.take(maxCells).map((e) => e.key).toList(growable: false);
debugPrint('⚠️ [geohash] Sampling aplicado: total=${entries.length} -> ${sampled.length} (maxCells=$maxCells, precision=$precision)');
return sampled;
```

## 2) Complete=true/false

Arquivo: lib/features/home/data/services/map_discovery_service.dart

```dart
// ✅ Reset completeness flags for this query
_lastQueryWasComplete = true;

...

if (isSaturated) {
  if (cellPrecision < precision) {
    if (remainingRefineBudget <= 0) {
      _lastQueryWasComplete = false;
      debugPrint('⚠️ [geohash] Refinement budget esgotado (cell=$cell, precision=$cellPrecision)');
      return;
    }
    // Refina célula saturada...
  } else {
    _lastQueryWasComplete = false;
    debugPrint('⚠️ [geohash] Saturated at target precision (cell=$cell, perCellLimit=$perCellLimit)');
  }
}

...

if (docsFetched == 0) {
  _lastQueryWasComplete = false;
}
```

## 3) EmptyConfirmed

Arquivo: lib/features/home/presentation/viewmodels/parts/map_viewmodel_sync.part.dart

```dart
final appliedForActiveKey = _mapDiscoveryService.lastQueryWasAppliedForActiveKey;
final queryComplete = _mapDiscoveryService.lastQueryWasComplete;
final bounds = _visibleBounds;
final isLargeViewport = bounds != null
    ? (bounds.northeast.latitude - bounds.southwest.latitude) > 10.0 ||
        (bounds.northeast.longitude - bounds.southwest.longitude) > 10.0
    : false;
final lastBoundsAt = _visibleBoundsUpdatedAt;
final isStable = lastBoundsAt != null
    ? DateTime.now().difference(lastBoundsAt) > const Duration(milliseconds: 600)
    : false;
final isReliableEmpty = !_mapDiscoveryService.isLoading &&
    appliedForActiveKey &&
    queryComplete &&
    !isLargeViewport &&
    isStable;
final emptyConfirmed = isReliableEmpty;
```
