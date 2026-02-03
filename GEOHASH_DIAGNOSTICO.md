# 🗺️ Diagnóstico Geohash Map Discovery

> Respostas ao questionário de diagnóstico do sistema de geohash do mapa.

---

## 1) Dados armazenados: geohash existe e é consistente?

### 1.1) No Firestore, em cada evento, qual campo você usa?

**✅ (X) `geohash` string** + **geo (GeoPoint) derivado**

O geohash é armazenado em **dois lugares**:
- `geohash` (raiz do documento) — usado nas queries
- `location.geohash` (dentro do objeto location) — redundância

### Exemplo de documento real (campos sensíveis omitidos):

```json
{
  "activityText": "Pedal no parque",
  "emoji": "🚴",
  "isActive": true,
  "status": "active",
  "geohash": "6gycfq7",              // ✅ 7 caracteres na raiz
  "location": {
    "latitude": -23.5505,
    "longitude": -46.6333,
    "geohash": "6gycfq7",            // Duplicado dentro de location
    "formattedAddress": "Av. Paulista, 1000"
  },
  "createdAt": "2026-01-15T10:30:00Z",
  "scheduleDate": "2026-02-10T14:00:00Z"
}
```

### 1.2) Você recalculou geohash para eventos antigos ou só pros novos?

**✅ (X) Migrei todos** (automaticamente via Cloud Function trigger)

A Cloud Function `onEventWriteUpdateGeohash` é um trigger `onWrite` que:
- Detecta qualquer escrita no documento
- Recalcula o geohash se `location.latitude/longitude` mudou
- Atualiza tanto `geohash` quanto `location.geohash`

**% sem geohash**: Estimado **0%** — todo evento com `location` válido recebe geohash automaticamente.

---

## 2) Geração do geohash: mesma biblioteca e mesma precisão?

### 2.1) Onde você gera o geohash?

**✅ (X) Backend (Cloud Function)**

Arquivo: `functions/src/events/eventGeohashSync.ts`

### 2.2) Qual lib exata você usa e qual função?

**Biblioteca**: Implementação própria em `functions/src/utils/geohash.ts`

```typescript
const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

export function encodeGeohash(
  latitude: number,
  longitude: number,
  precision = 7
): string {
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return "";
  }

  let minLat = -90.0;
  let maxLat = 90.0;
  let minLng = -180.0;
  let maxLng = 180.0;

  let bits = 0;
  let hashValue = 0;
  let isEven = true;
  let hash = "";

  while (hash.length < precision) {
    if (isEven) {
      const mid = (minLng + maxLng) / 2;
      if (longitude >= mid) {
        hashValue = (hashValue << 1) + 1;
        minLng = mid;
      } else {
        hashValue = (hashValue << 1);
        maxLng = mid;
      }
    } else {
      const mid = (minLat + maxLat) / 2;
      if (latitude >= mid) {
        hashValue = (hashValue << 1) + 1;
        minLat = mid;
      } else {
        hashValue = (hashValue << 1);
        maxLat = mid;
      }
    }

    isEven = !isEven;
    bits++;

    if (bits === 5) {
      hash += BASE32[hashValue];
      bits = 0;
      hashValue = 0;
    }
  }

  return hash;
}
```

**No app (Dart)** — mesma implementação em `lib/core/utils/geohash_helper.dart`:

```dart
class GeohashHelper {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  static String encode(double latitude, double longitude, {int precision = 9}) {
    // Mesmo algoritmo do backend
  }
}
```

### 2.3) Você usa ponto ou vírgula na string antes de gerar?

**✅ (X) Sempre double nativo**

Não há conversão para string em nenhum ponto antes de gerar o geohash.

### 2.4) Qual precisão você salva no documento?

**✅ (X) Salva truncado (7 caracteres)**

```typescript
const nextGeohash = encodeGeohash(lat, lng, 7);  // Precisão 7 = ~150m x 150m
```

---

## 3) Query geohash: qual estratégia e quais constraints do Firestore?

### 3.1) Seu algoritmo de "geohash query" está fazendo:

**✅ (X) `startAt/endAt` em `orderBy('geohash')` por intervalo**

### Método que monta as queries:

```dart
// lib/features/home/data/services/map_discovery_service.dart

Future<List<EventLocation>> _queryFirestore(
  MapBounds bounds, {
  int zoomBucket = 2,
}) async {
  final limit = maxEventsPerQueryForZoomBucket(zoomBucket);
  final precision = _geohashPrecisionForZoomBucket(zoomBucket);
  final geohashCells = _buildGeohashCellsForBounds(
    bounds,
    precision: precision,
    maxCells: _maxGeohashQueries,  // 12
  );

  final perCellLimit = (limit / geohashCells.length).ceil().clamp(20, limit);
  
  for (final cell in geohashCells) {
    final query = await _firestore
        .collection(_eventsCollection)
        .where('isActive', isEqualTo: true)  // ✅ Combinado com filtro de status
        .orderBy('geohash')
        .startAt([cell])                      // Início do prefixo
        .endAt(['$cell\uf8ff'])               // Fim do prefixo (uf8ff = último char unicode)
        .limit(perCellLimit)
        .get();
    // ...
  }
}
```

### 3.2) Você está combinando geohash com outros filtros?

**Sim**, combinado com:
- `where('isActive', isEqualTo: true)` — apenas eventos ativos

```dart
// Dentro do loop de processamento:
final isCanceled = data['isCanceled'] as bool? ?? false;
if (isCanceled) continue;

final status = data['status'] as String?;
if (status != null && status != 'active') continue;
```

### 3.3) Índices: você precisou criar algum índice composto?

**✅ (X) Sim**

Índice composto em `firestore.indexes.json`:

```json
{
  "collectionGroup": "events",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "isActive", "order": "ASCENDING" },
    { "fieldPath": "geohash", "order": "ASCENDING" }
  ]
}
```

---

## 4) Precision dinâmica: por que você está caindo pra 3 quando req=5/6?

### 4.1) Onde você calcula reqPrecision?

**Com base em zoomBucket** (derivado do zoom do mapa).

```dart
static int _geohashPrecisionForZoomBucket(int zoomBucket) {
  switch (zoomBucket) {
    case 0: return 4;  // zoom ≤ 8 (muito afastado) ~40km
    case 1: return 5;  // zoom 9-11 (clusters médios) ~5km
    case 2: return 6;  // zoom 12-14 (transição) ~1.2km
    case 3: return 7;  // zoom > 14 (markers individuais) ~150m
    default: return 6;
  }
}

int _zoomBucket(double? zoom) {
  if (zoom == null) return 2;
  if (zoom <= 8) return 0;
  if (zoom <= 11) return 1;
  if (zoom <= 14) return 2;
  return 3;
}
```

### 4.2) Em que condição você reduz precision?

**✅ (X) Limite máximo de células (queries)**

```dart
List<String> _buildGeohashCellsForBounds(
  MapBounds bounds, {
  required int precision,
  required int maxCells,
}) {
  var currentPrecision = precision;
  while (currentPrecision >= 3) {
    final cells = _sampleGeohashCells(
      bounds,
      precision: currentPrecision,
      maxCells: maxCells,
    );
    if (cells.length <= maxCells) return cells;  // ✅ Cabe no limite
    currentPrecision -= 1;                        // ❌ Não cabe, reduz precision
  }

  return _sampleGeohashCells(bounds, precision: 3, maxCells: maxCells);
}
```

### 4.3) Qual é o maxCells permitido antes de reduzir precision?

```dart
static const int _maxGeohashQueries = 12;
```

**maxCells = 12 queries paralelas**

---

## 5) Pós-filtro: você filtra por lat/lng depois de buscar?

### 5.1) Função de filtro:

```dart
// lib/features/home/data/models/map_bounds.dart

bool contains(double lat, double lng) {
  // Latitude sempre é simples
  if (lat < minLat || lat > maxLat) return false;
  
  // Longitude: caso normal (minLng <= maxLng)
  if (minLng <= maxLng) {
    return lng >= minLng && lng <= maxLng;
  }
  
  // ✅ Longitude: caso wrap/anti-meridiano (ex: minLng=170, maxLng=-170)
  // Neste caso, lng é válido se >= minLng OU <= maxLng
  return lng >= minLng || lng <= maxLng;
}
```

### 5.2) Você trata anti-meridiano (quando cruza -180/180)?

**✅ (X) Sim**

O método `contains` detecta quando `minLng > maxLng` (wrap) e ajusta a lógica.

### 5.3) Você normaliza longitude pra [-180, 180]?

**❌ (X) Não explicitamente**

Assume que os dados já estão normalizados (o que é garantido pelo Firestore/GeoPoint).

### 5.4) Você tem algum "fallback por latitude"?

**✅ (X) Sim** (mas está **desativado**)

```dart
static const bool _allowEventsFallback = false;  // ❌ DESATIVADO

Future<List<EventLocation>> _queryEventsFallback(
  MapBounds bounds, {
  required int limit,
}) async {
  debugPrint('⚠️ [events] fallback por latitude (geohash incompleto)');

  final query = await _firestore
      .collection(_eventsCollection)
      .where('isActive', isEqualTo: true)
      .where('location.latitude', isGreaterThanOrEqualTo: bounds.minLat)
      .where('location.latitude', isLessThanOrEqualTo: bounds.maxLat)
      .limit(limit)
      .get();
  // Filtra longitude no client...
}
```

---

## 6) Ordem e "aplicando mesmo assim": regra de concorrência

### 6.1) Hoje a regra pra aplicar resultado é baseada em:

**✅ (X) boundsKey (activeKey no momento da resposta)**

### 6.2) Regra desejada:

**✅ (X) Só aplica se boundsKey == activeKey**

### Bloco que decide "aplicar / descartar":

**No MapRenderController:**

```dart
// lib/features/home/presentation/widgets/map_controllers/map_render_controller.dart

Future<void> _rebuildMarkersUsingClusterService() async {
  // ...
  
  // ✅ REGRA DE OURO: Validar por BOUNDSKEY, não por seq sozinho
  // O render só acontece se os dados vieram do mesmo viewport que está ativo na tela
  if (querySnapshot != null && _activeViewportBoundsKey != null) {
     final snapBoundsKey = querySnapshot.boundsKey;
     if (snapBoundsKey != _activeViewportBoundsKey) {
       debugPrint('🛑 [MapRender] Descartando render: snapKey=$snapBoundsKey != activeKey=$_activeViewportBoundsKey');
       return;  // ❌ DESCARTA
     }
  }
  
  // ✅ Se chegou aqui, renderiza
  debugPrint('🧭 [MapRender] render OK: boundsKey=${querySnapshot.boundsKey}, zoom=..., events=...');
}
```

**No MapDiscoveryService:**

```dart
// lib/features/home/data/services/map_discovery_service.dart

// Detecta respostas stale mas NÃO descarta (apenas loga)
final isStale = requestId != _requestSeq;
if (isStale) {
  debugPrint('⚠️ [MapDiscovery] Resposta de query anterior (seq=$requestId, currentSeq=$_requestSeq) - aplicando mesmo assim');
}

// ✅ STORE POR BOUNDSKEY: armazena eventos indexados pelo viewport
_eventsByBoundsKey[bKey] = filtered;
_activeBoundsKey = bKey;

// ✅ UI sempre lê do boundsKey ativo (NUNCA merge global)
nearbyEvents.value = _eventsByBoundsKey[_activeBoundsKey] ?? [];
```

---

## 7) Cache/prefetch: o que entra no store e o que vai pra UI?

### 7.1) Onde você guarda por boundsKey?

**`Map<String, List<EventLocation>> _eventsByBoundsKey`**

```dart
// lib/features/home/data/services/map_discovery_service.dart

// ✅ STORE POR BOUNDSKEY: eventos indexados pelo viewport que os buscou
final Map<String, List<EventLocation>> _eventsByBoundsKey = <String, List<EventLocation>>{};
String? _activeBoundsKey;

/// Retorna eventos apenas do boundsKey ativo (NÃO merge global)
List<EventLocation> get eventsForActiveBounds => _eventsByBoundsKey[_activeBoundsKey] ?? [];
```

**Não há mais `mergedAll`** — a UI lê apenas do boundsKey ativo.

### 7.2) Prefetch:

**❌ DESATIVADO TEMPORARIAMENTE**

```dart
// ✅ DESATIVADO TEMPORARIAMENTE: prefetch gera muitas queries em áreas vazias
// if (prefetchNeighbors) {
//   unawaited(_prefetchAdjacentQuadkeys(bounds, quadkey, zoomBucket: zoomBucket));
// }
```

Se estivesse ativo, escreveria em `_quadkeyCache` (cache de tiles), **não diretamente em `_eventsByBoundsKey`**.

### 7.3) Quando o activeKey muda, você limpa algo?

**❌ (X) Não limpa** — mantém tudo em memória

O `_eventsByBoundsKey` mantém histórico de bounds anteriores (útil para voltar rápido).
O `_quadkeyCache` tem LRU com limite de 300 entries.

---

## 8) Limites por célula: perCellLimit está te escondendo eventos?

### 8.1) Esse limite é por:

**✅ (X) Query (por célula)**

```dart
final perCellLimit = (limit / geohashCells.length).ceil().clamp(20, limit);
```

Onde `limit` é o total por zoomBucket:

```dart
static int maxEventsPerQueryForZoomBucket(int zoomBucket) {
  switch (zoomBucket) {
    case 0: return 400;  // mundo
    case 1: return 350;  // cidades
    case 2: return 300;  // transição
    case 3: return 200;  // individual
    default: return 300;
  }
}
```

### 8.2) Você faz paginação por célula?

**❌ (X) Não**

Cada célula é limitada a `perCellLimit` docs. Se uma célula tiver mais eventos que o limite, os excedentes são **truncados**.

---

## 9) Sanity check (teste controlado)

### 9.1) Teste com 1 célula apenas

**Para executar:**

1. Pegue um evento real e seu geohash (ex: `6gycfq7`)
2. Faça query manual no Firestore:
   ```
   events.where('geohash', '>=', '6gycfq').where('geohash', '<=', '6gycfq\uf8ff')
   ```
3. Verifique se o evento retorna

### 9.2) Teste "sem pós-filtro"

**O log atual já mostra:**

```
🧪 [events] kept=X (lngFiltered=Y, fetched=Z)
```

- `fetched` = docs retornados pelo Firestore
- `lngFiltered` = docs removidos pelo filtro de bounds
- `kept` = docs que passaram no filtro

Se `lngFiltered` > 0, o log adicional mostra:

```
🔬 [events] Primeiro evento filtrado: lat=-23.550, lng=-46.633
🔬 [events] Bounds esperava: lat=[-23.600, -23.500], lng=[-46.700, -46.600]
```

---

## 📊 Resumo Executivo

| Item | Valor |
|------|-------|
| **Campo geohash** | `geohash` (raiz) + `location.geohash` |
| **Precisão armazenada** | 7 chars (~150m) |
| **Geração** | Backend (Cloud Function `onEventWriteUpdateGeohash`) |
| **Query method** | `startAt/endAt` com prefixo |
| **maxCells** | 12 queries paralelas |
| **Precision dinâmica** | 4-7 chars (reduz se cells > 12) |
| **Filtro pós-query** | `MapBounds.contains(lat, lng)` |
| **Anti-meridiano** | ✅ Tratado |
| **Descarta stale?** | ✅ Por boundsKey no render |
| **Cache memória TTL** | 90 segundos |
| **Cache Hive TTL** | 2-10 min (por zoomBucket) |
| **Prefetch** | ❌ Desativado |
| **Paginação por célula** | ❌ Não (trunca) |

---

## 🔑 5 Respostas Essenciais

### 1. Função que calcula requestedPrecision e reduz pra actualPrecision

```dart
// Calcula requested baseado no zoom
static int _geohashPrecisionForZoomBucket(int zoomBucket) {
  switch (zoomBucket) {
    case 0: return 4;  // zoom ≤ 8
    case 1: return 5;  // zoom 9-11
    case 2: return 6;  // zoom 12-14
    case 3: return 7;  // zoom > 14
    default: return 6;
  }
}

// Reduz se cells > maxCells
List<String> _buildGeohashCellsForBounds(MapBounds bounds, {required int precision, required int maxCells}) {
  var currentPrecision = precision;
  while (currentPrecision >= 3) {
    final cells = _sampleGeohashCells(bounds, precision: currentPrecision, maxCells: maxCells);
    if (cells.length <= maxCells) return cells;
    currentPrecision -= 1;  // Reduz precision
  }
  return _sampleGeohashCells(bounds, precision: 3, maxCells: maxCells);
}
```

### 2. Função de filtro lat/lng (onde gera lngFiltered)

```dart
// MapBounds.contains()
bool contains(double lat, double lng) {
  if (lat < minLat || lat > maxLat) return false;
  
  if (minLng <= maxLng) {
    return lng >= minLng && lng <= maxLng;
  }
  
  // Anti-meridiano
  return lng >= minLng || lng <= maxLng;
}

// Uso em _queryFirestore:
if (!bounds.contains(event.latitude, event.longitude)) {
  docsFilteredByLongitude++;
  continue;
}
```

### 3. Função que monta as queries por geohash

```dart
for (final cell in geohashCells) {
  final query = await _firestore
      .collection('events')
      .where('isActive', isEqualTo: true)
      .orderBy('geohash')
      .startAt([cell])
      .endAt(['$cell\uf8ff'])
      .limit(perCellLimit)
      .get();
}
```

### 4. Regra que decide "aplica mesmo assim" vs descarta

```dart
// No MapRenderController:
if (querySnapshot != null && _activeViewportBoundsKey != null) {
   final snapBoundsKey = querySnapshot.boundsKey;
   if (snapBoundsKey != _activeViewportBoundsKey) {
     debugPrint('🛑 [MapRender] Descartando render: snapKey=$snapBoundsKey != activeKey=$_activeViewportBoundsKey');
     return;  // DESCARTA
   }
}
// Se não descartou, renderiza
```

### 5. Exemplo de 1 documento de evento com geohash + lat/lng

```json
{
  "activityText": "Pedal no parque",
  "emoji": "🚴",
  "isActive": true,
  "status": "active",
  "isCanceled": false,
  "geohash": "6gycfq7",
  "location": {
    "latitude": -23.5505,
    "longitude": -46.6333,
    "geohash": "6gycfq7",
    "formattedAddress": "Av. Paulista, 1000, São Paulo"
  },
  "createdAt": { "_seconds": 1738000000 },
  "scheduleDate": { "_seconds": 1739000000 },
  "createdBy": "user_abc123"
}
```
