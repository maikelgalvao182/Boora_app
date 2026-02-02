# Análise do CacheKey - MapBounds

**Data:** 2 de fevereiro de 2026  
**Status:** ✅ CORRIGIDO

---

## 🐛 Problemas Identificados

### Problema 1: `round()` em coordenadas negativas
Com `round()`, coordenadas negativas podem "grudar" de forma imprevisível:
- `-46.49 * 2 = -92.98 → round = -93`
- `-46.01 * 2 = -92.02 → round = -92`

**Solução:** Usar `floor()` com `gridSize` para tiles consistentes.

### Problema 2: Precision muito grosseiro
Com `precision = 2` (grid 0.5° ~55km), pans de até 50km geram a **mesma cacheKey**.

**Solução:** Precision dinâmico por zoomBucket.

---

## ✅ Correções Aplicadas

### 1. CacheKey com floor() e precision dinâmico

```dart
// Arquivo: lib/features/home/data/models/map_bounds.dart

String toQuadkey({int precision = 2}) {
  final centerLat = (minLat + maxLat) / 2.0;
  final centerLng = (minLng + maxLng) / 2.0;
  
  // ✅ FIX: Usar floor() com gridSize para tiles consistentes
  final gridSize = 1.0 / precision;
  final latKey = (centerLat / gridSize).floor();
  final lngKey = (centerLng / gridSize).floor();

  final latSpan = (maxLat - minLat).abs();
  final lngSpan = (maxLng - minLng).abs();
  final spanBucket = _spanBucket(latSpan, lngSpan);

  return '${latKey}_${lngKey}_$spanBucket';
}

// ✅ Schema version bumped para invalidar cache antigo
static const int _cacheSchemaVersion = 3;

String toCacheKey({required int zoomBucket, int? precision}) {
  final effectivePrecision = precision ?? _precisionForZoomBucket(zoomBucket);
  final quadkey = toQuadkey(precision: effectivePrecision);
  return 'events:$quadkey:zb$zoomBucket:v$_cacheSchemaVersion';
}

static int _precisionForZoomBucket(int zoomBucket) {
  switch (zoomBucket) {
    case 0: return 1;  // grid 1.0° (~111km tiles)
    case 1: return 4;  // grid 0.25° (~28km tiles)
    case 2: return 10; // grid 0.10° (~11km tiles)
    case 3: return 20; // grid 0.05° (~5.5km tiles)
    default: return 10;
  }
}
```

### 2. Logs detalhados na query Firestore

```dart
// Arquivo: lib/features/home/data/services/map_discovery_service.dart

// Agora mostra:
// 🔥 [Firestore] Query events_map:
//    📍 lat: -23.5000 to -22.5000
//    📍 lng: -47.0000 to -46.0000 (filtrado em código)
//    📍 latSpan: 1.00° (~111km)
//    🔍 isActive=true, limit=1500
// 🔥 [Firestore] Resposta: 50 docs retornados
// 📊 [Firestore] Breakdown:
//    📥 fetched: 50
//    ✅ kept: 12
//    ❌ canceled: 0
//    ❌ status!=active: 3
//    ❌ longitude fora: 35
//    ❌ erro parse: 0
```

---

## 📊 Tabela de Precision por ZoomBucket

| ZoomBucket | Zoom Map | Grid Size | Distância | Uso |
|------------|----------|-----------|-----------|-----|
| 0 | ≤8 | 1.0° | ~111km | Global/continental |
| 1 | 8-11 | 0.25° | ~28km | Regional |
| 2 | 11-14 | 0.10° | ~11km | Cidade |
| 3 | >14 | 0.05° | ~5.5km | Local/bairro |

---

## 🧪 Validação

Depois do hot restart, verificar nos logs:

### Teste 1: Pan pequeno (10km) no zoom 12
```
cacheKey ANTES: events:-235_-466_6:zb2:v3
cacheKey DEPOIS: events:-234_-466_6:zb2:v3  ← DEVE MUDAR
```

### Teste 2: Pan grande (50km) no zoom 12
```
cacheKey DEVE MUDAR (vários tiles de diferença)
```

### Teste 3: Zoom out para 8
```
cacheKey DEVE MUDAR (zoomBucket 2 → 1, precision 10 → 4)
```

### Teste 4: Query Firestore
```
🔥 [Firestore] Resposta: X docs retornados
📊 [Firestore] Breakdown:
   📥 fetched: X
   ✅ kept: Y
   ❌ longitude fora: Z
```

Se `fetched=1` → problema é no Firestore (poucos eventos na coleção)
Se `fetched=1500, kept=1` → problema é filtro de longitude (bounds muito estreito)

---

## ⚠️ Próximo Passo: Investigar "1 evento"

Se os logs mostrarem:
```
🔥 [Firestore] Resposta: 1 docs retornados
```

Significa que a coleção `events_map` realmente tem poucos eventos naquela região.

**Possíveis causas:**
1. Coleção `events_map` não está sincronizada com `events`
2. Muitos eventos com `isActive=false`
3. Índice do Firestore não configurado corretamente

**Ação:** Verificar no Firebase Console quantos documentos existem em `events_map` com `isActive=true`.
