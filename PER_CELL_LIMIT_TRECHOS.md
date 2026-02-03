# Trecho solicitado — perCellLimit + isSaturated

Arquivo: lib/features/home/data/services/map_discovery_service.dart

```dart
final perCellLimit = (limit / geohashCells.length).ceil().clamp(20, limit);
final actualPrecision = geohashCells.first.length;
```

```dart
final returnedCount = query.docs.length;
final isSaturated = returnedCount >= perCellLimit;
```
