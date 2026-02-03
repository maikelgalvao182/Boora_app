# Diagnóstico: Markers não carregam durante pan (só zoom 3.0)

**Data:** 2 de fevereiro de 2026  
**Status:** Em investigação  

---

## 1) Contexto do problema

**Plataforma onde acontece:**
- (x) iOS (testado com simulador iPhone)
- ( ) Android
- ( ) Ambos

> **Obs:** O problema foi identificado em iOS. Precisa validar em Android.

**Em qual plugin do Maps você está?**
- (x) google_maps_flutter
- **Versão do plugin:** `^2.10.0`

**O carregamento de markers vem de onde?**
- (x) Firestore
- ( ) API REST
- ( ) Banco local
- ( ) Lista em memória
- **Detalhes:** Query por geohash na coleção `events` com filtro `isActive == true`

**Você usa cluster?**
- (x) sim: **Fluster** (`^1.2.0`)
- **Serviço:** `MarkerClusterService` com `Fluster<EventMapMarker>`

---

## 2) Gatilhos de atualização do mapa

**Quais callbacks você usa no GoogleMap?**
- (x) onMapCreated
- (x) onCameraMoveStarted
- (x) onCameraMove
- (x) onCameraIdle

**O carregamento de markers é chamado em qual evento?**
- ( ) só no onMapCreated
- (x) só no onCameraIdle (com debounce adicional de ~200ms)
- ( ) no onCameraMove (com debounce)
- (x) em outro lugar: `triggerInitialEventSearch()` após `onMapCreated`

**Código relevante (`google_map_view.dart:231-254`):**
```dart
void _onCameraIdle() {
  _renderController?.setCameraMoving(false);
  
  _cameraIdleDebounce?.cancel();
  _cameraIdleDebounce = Timer(_cameraIdleDebounceDuration, () {
    if (!mounted) return;
    _handleCameraIdleDebounced();
  });
}
```

**Quando você faz pan e solta o dedo, o onCameraIdle dispara?**
- (x) sempre
- **Evidência nos logs:**
```
📷 MapBoundsController: cameraIdle(boundsKey=-20.057_-49.155_-17.329_-47.464, zoom=8.4, ...)
📍 MapBoundsController: Câmera parou (zoom: 8.4)
```

**Quando você muda apenas o zoom, o onCameraIdle dispara?**
- (x) sempre

---

## 3) Bounds / região visível

**Você pega bounds usando controller.getVisibleRegion()?**
- (x) sim

**Depois do pan, os bounds mudam de verdade?**
- (x) sim, mudam bastante
- **Evidência nos logs:** bounds passam de `-19.037_-48.324` para `-20.057_-49.155`

**Você valida se os bounds estão coerentes?**
- (x) sim, e estão ok
- **Código em `MapBounds.fromLatLngBounds()`**

**Seu carregamento depende de "tile/quadkey/geohash"?**
- (x) sim: **geohash** (precision 4-7 dependendo do zoomBucket)
- **Código:** `_geohashPrecisionForZoomBucket()` em `map_discovery_service.dart`

---

## 4) Cache e "early return"

**Existe cache para markers?**
- (x) sim, em memória (Map<cacheKey, _QuadkeyCacheEntry> com TTL 90s)
- (x) sim, persistente (Hive com TTL 2-10 min dependendo do zoomBucket)
- **Ambos os caches**

**Existe lógica de pular load (early return) por algum motivo?**
- (x) isLoading (`_isLoading` flag)
- (x) sameBounds / "bounds iguais" (`withinPrevious && tooSoon`)
- (x) sameQuadkey / "tile igual" (`canSkipBecausePrefetched`)
- (x) TTL "ainda fresco" (`prefetchIsFresh`)
- (x) debounce ativo (600ms em `map_discovery_service.dart`)
- (x) outra: `requestId != _requestSeq` (descarte de respostas "obsoletas") **← BUG IDENTIFICADO**

**No pan, você percebe que a função de load é chamada mas retorna cedo?**
- (x) sim
- **Evidência nos logs (ANTES da correção):**
```
⏭️ [MapDiscovery] Descartando resposta obsoleta (seq=4, currentSeq=6, events=5)
⏭️ [MapDiscovery] Descartando resposta obsoleta (seq=5, currentSeq=7, events=38)
⏭️ [MapDiscovery] Descartando resposta obsoleta (seq=6, currentSeq=7, events=27)
```

**No zoom 3.0 (visão geral), por que "funciona"?**
- (x) aumenta raio / muda query (bounds cobre mais área)
- (x) usa fallback por latitude (geohash não cobre bounds grandes)
- **Evidência:**
```
⚠️ [events] fallback por latitude (geohash incompleto)
🧪 [events] kept=370 (lngFiltered=0)
```

---

## 5) Concorrência / race condition

**Você usa debounce/throttle para evitar spam de requests?**
- (x) sim: **600ms** em `MapDiscoveryService.debounceTime`
- **Adicional:** ~200ms de debounce no `_onCameraIdle`

**Se o usuário move o mapa várias vezes rápido, você cancela requests antigos?**
- (x) não (Firestore queries não são canceláveis)
- **Problema:** Múltiplas queries em voo competindo

**Pode acontecer de uma resposta antiga sobrescrever a nova?**
- (x) sim (já vi "piscar" / sumir) **← BUG IDENTIFICADO**
- **Causa raiz:** `nearbyEvents.value = filtered` substituía em vez de mesclar

---

## 6) Atualização de UI

**Como você atualiza os markers na UI?**
- ( ) setState substituindo o Set<Marker> inteiro
- ( ) setState mutando o mesmo Set
- (x) Provider/Riverpod/ChangeNotifier
- **Detalhes:** `MapRenderController extends ChangeNotifier` com `notifyListeners()`

**Você garante MarkerId único?**
- (x) sim
- **Código:** `MarkerId('event_${event.id}')` e `MarkerId('event_avatar_${event.id}')`

**Quando "não carrega", o resultado da query vem vazio ou vem com dados?**
- (x) vem com dados mas não renderiza
- **Evidência:**
```
🧪 [events] kept=38 (lngFiltered=2, fetched=41)
⏭️ [MapDiscovery] Descartando resposta obsoleta (seq=5, currentSeq=7, events=38)
```

---

## 7) Logs relevantes

**Logs que mostram o problema (pan de zoom 12 → zoom 8):**

```
📷 MapBoundsController: cameraIdle(boundsKey=-20.057_-49.155_-17.329_-47.464, zoom=8.4, ...)
🌐 [DIAG] Disparando fetch de rede (reason=cache_miss)...
🔵 [MapVM] loadEventsInBounds start (events.length=1, loadKey=-38_-97_1)
🔎 [MapDiscovery] queryStart(seq=4, boundsKey=-22.786_-50.847_-14.600_-45.772, ...)
🔍 [events] Query geohash (cells=13, precision=5, perCellLimit=27)

# Enquanto isso, usuário continua pan...
📷 MapBoundsController: cameraIdle(boundsKey=-21.431_-48.745_-18.725_-47.053, zoom=8.4, ...)
🔎 [MapDiscovery] queryStart(seq=5, boundsKey=-24.136_-50.436_-16.020_-45.361, ...)

# Mais pan...
📷 MapBoundsController: cameraIdle(boundsKey=-21.804_-49.174_-17.840_-46.699, zoom=7.9, ...)
🔎 [MapDiscovery] queryStart(seq=6, boundsKey=-25.767_-51.648_-13.877_-44.224, ...)

# Queries terminam fora de ordem e são DESCARTADAS:
🧪 [events] kept=5 (lngFiltered=31, fetched=37)
⏭️ [MapDiscovery] Descartando resposta obsoleta (seq=4, currentSeq=6, events=5)

🧪 [events] kept=38 (lngFiltered=2, fetched=41)
⏭️ [MapDiscovery] Descartando resposta obsoleta (seq=5, currentSeq=7, events=38)

🧪 [events] kept=27 (lngFiltered=7, fetched=34)
⏭️ [MapDiscovery] Descartando resposta obsoleta (seq=6, currentSeq=7, events=27)

# Mapa fica com apenas 1 evento!
🔵 [MapVM] loadEventsInBounds after service (nearbyEvents.value.length=1, loadKey=-38_-97_1)
```

**Logs quando zoom 3.0 funciona:**

```
📷 MapBoundsController: cameraIdle(boundsKey=-57.528_-81.385_46.904_-8.612, zoom=3.0, ...)
🔎 [MapDiscovery] queryStart(seq=8, boundsKey=-90.000_-154.159_90.000_64.162, ...)
🔍 [events] Query geohash (cells=13, precision=4, perCellLimit=31)
⚠️ [events] fallback por latitude (geohash incompleto)
🧪 [events] kept=370 (lngFiltered=0)
✅ MapDiscoveryService: 370 eventos encontrados
✅ [MapDiscovery] queryEnd(seq=8, boundsKey=..., count=370, ...)

# 370 eventos carregados corretamente!
🔵 [MapVM] loadEventsInBounds after service (nearbyEvents.value.length=370, loadKey=0_-90_1)
🟣 [MapVM] updating _events: 1 -> 370 (signature=370|v9|z0|...)
🔄 [ClusterService] Fluster construído: 370 eventos
🧭 [MapRender] render done (..., clusters=24, markersProduced=24, ...)
```

---

## 8) Diagnóstico e Correções Aplicadas

### Causa raiz identificada:

1. **`_requestSeq` incrementado ANTES do debounce**
   - Cada chamada de `loadEventsInBounds()` incrementava o seq
   - Durante pan rápido: seq 1, 2, 3, 4, 5...
   - Debounce cancelava timers anteriores mas o seq já tinha mudado
   - Quando query terminava: `requestId != _requestSeq` → DESCARTADA

2. **Substituição em vez de merge**
   - `nearbyEvents.value = filtered` substituía todos os eventos
   - Query mais lenta com bounds menor sobrescrevia query com bounds maior
   - Resultado: mapa ficava com poucos eventos

### Correções implementadas em `map_discovery_service.dart`:

```dart
// ANTES (problemático):
Future<void> loadEventsInBounds(...) async {
  final int requestId = ++_requestSeq; // ❌ Incrementa antes do debounce
  _debounceTimer = Timer(debounceTime, () async {
    await _executeQuery(bounds, requestId, ...);
  });
}

// DEPOIS (corrigido):
Future<void> loadEventsInBounds(...) async {
  _debounceTimer = Timer(debounceTime, () async {
    final int requestId = ++_requestSeq; // ✅ Incrementa dentro do timer
    await _executeQuery(bounds, requestId, ...);
  });
}
```

```dart
// ANTES (problemático):
if (requestId != _requestSeq) {
  return; // ❌ Descarta resposta válida
}
nearbyEvents.value = filtered; // ❌ Substitui tudo

// DEPOIS (corrigido):
// ✅ Não descarta, apenas loga
if (requestId != _requestSeq) {
  debugPrint('⚠️ Resposta de query anterior - aplicando mesmo assim');
}

// ✅ Merge incremental
final currentEvents = nearbyEvents.value;
final newEvents = <EventLocation>[...filtered];
for (final prev in currentEvents) {
  if (!newEvents.any((e) => e.eventId == prev.eventId)) {
    newEvents.add(prev);
  }
}
nearbyEvents.value = newEvents;
```

### Índice Firestore criado:

```json
{
  "collectionGroup": "events",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "isActive", "order": "ASCENDING"},
    {"fieldPath": "geohash", "order": "ASCENDING"}
  ]
}
```

---

## 9) Interpretação rápida

| Sintoma | Diagnóstico | Status |
|---------|-------------|--------|
| onCameraIdle não dispara no pan | ❌ Não é o problema | OK |
| bounds não mudam ou vêm invertidos | ❌ Não é o problema | OK |
| Função chamada mas faz early return | ✅ **BUG:** `requestId != _requestSeq` | CORRIGIDO |
| Query retorna dados mas markers não aparecem | ✅ **BUG:** Substituição em vez de merge | CORRIGIDO |
| Oscila/some durante pan | ✅ **BUG:** Race condition | CORRIGIDO |

---

## 10) Próximos passos

1. ✅ Hot restart do app
2. ✅ Testar pan/zoom em diferentes níveis
3. ⏳ Verificar logs para `merged=` (eventos acumulando)
4. ⏳ Validar em Android
5. ⏳ Monitorar se há memory leak com merge infinito (pode precisar de TTL/LRU)

---

## Arquivos modificados

- `lib/features/home/data/services/map_discovery_service.dart`
  - Mover incremento de `_requestSeq` para dentro do Timer
  - Remover descarte de respostas "obsoletas"
  - Implementar merge incremental em vez de substituição
  
- `firestore.indexes.json`
  - Adicionar índice `events: isActive + geohash`
