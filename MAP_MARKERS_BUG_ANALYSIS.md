# Análise de Bug: Markers não carregam no Pan (apenas no Zoom 3.0)

**Data:** 2 de fevereiro de 2026  
**Status:** Em investigação  

---
a
## 1) Contexto do problema

**Plataforma onde acontece:**

- [ ] Android
- [ ] iOS
- [x] Ambos

> **Obs:** O problema está na lógica de cache/bounds, não na UI específica de plataforma.

**Em qual plugin do Maps você está?**

- [x] google_maps_flutter
- [ ] outro: _________

**Versão do plugin:** (verificar pubspec.yaml)

**O carregamento de markers vem de onde?**

- [x] Firestore (coleção `events_map` com fallback para `events`)
- [ ] API REST
- [ ] Banco local
- [ ] Lista em memória (já vem tudo e só filtra)
- [ ] outro: _________

**Você usa cluster?**

- [x] sim (qual lib?): **Fluster** (clustering local com latitude/longitude)
- [ ] não

---

## 2) Gatilhos de atualização do mapa (isso é o coração do bug)

**Quais callbacks você usa no GoogleMap?**

- [x] onMapCreated
- [x] onCameraMoveStarted
- [x] onCameraMove
- [x] onCameraIdle

**O carregamento de markers é chamado em qual evento?**

- [ ] só no onMapCreated
- [x] só no onCameraIdle (com debounce de 600ms)
- [ ] no onCameraMove (com debounce)
- [x] em outro lugar: `triggerInitialEventSearch()` após `onMapCreated`

**Quando você faz pan e solta o dedo, o onCameraIdle dispara?**

- [x] sempre (confirmado pelos logs: `📷 MapBoundsController: cameraIdle(...)`)
- [ ] às vezes
- [ ] nunca
- [ ] não sei (não tenho log)

**Quando você muda apenas o zoom, o onCameraIdle dispara?**

- [x] sempre
- [ ] às vezes
- [ ] nunca

---

## 3) Bounds / região visível (onde muita query morre)

**Você pega bounds usando controller.getVisibleRegion()?**

- [x] sim
- [ ] não, calculo na mão
- [ ] não uso bounds (uso só centro + raio)

**Depois do pan, os bounds mudam de verdade? (com log)**

- [x] sim, mudam bastante (logs mostram bounds diferentes)
- [ ] mudam pouco
- [ ] ficam iguais (estranho)
- [ ] ainda não loguei

**Você valida se os bounds estão coerentes?**
(SW.lat <= NE.lat e SW.lng <= NE.lng)

- [x] sim, e estão ok (validação no `isLatLngBoundsContained`)
- [ ] sim, e às vezes vêm invertidos
- [ ] não valido

**Seu carregamento depende de "tile/quadkey/geohash"?**

- [x] sim: **quadkey + zoomBucket + versão** (formato: `events:{lat}_{lng}_{precision}:zb{bucket}:v2`)
- [ ] não

---

## 4) Cache e "early return" (o bug que parece "não chamou update")

**Existe cache para markers?**

- [ ] sim, em memória
- [ ] sim, persistente (Hive/SQLite)
- [x] sim, ambos (memória com TTL 90s + Hive com TTL variável por zoomBucket)
- [ ] não

**Existe lógica de pular load (early return) por algum motivo?**

- [x] isLoading
- [x] sameBounds / "bounds iguais" (`isBoundsContained`)
- [x] sameQuadkey / "tile igual" (`withinPrefetched`)
- [x] TTL "ainda fresco" (`_minIntervalBetweenContainedBoundsQueries = 2s`)
- [x] debounce ativo (600ms)
- [x] outra: **`withinLastRequested`** - verifica se queryBounds está contido no último bounds requisitado
- [ ] não

**No pan, você percebe que a função de load é chamada mas retorna cedo?**

- [x] sim (log mostra: `📦 [DIAG] skipNetworkFetch: true, reason=inside_prefetch`)
- [ ] não chama mesmo
- [ ] não sei (sem log)

**No zoom 3.0 (visão geral), por que "funciona"?**

- [x] muda o quadkey/tile
- [ ] passa em outro fluxo (ex: "loadAllMarkers")
- [ ] aumenta raio / muda query
- [x] **zoomBucketChanged = true** força o fetch de rede

---

## 5) Concorrência / race condition (muito comum em pan)

**Você usa debounce/throttle para evitar spam de requests?**

- [x] sim: **600ms** (MapDiscoveryService) + **600ms** (cameraIdle debounce)
- [ ] não

**Se o usuário move o mapa várias vezes rápido, você cancela requests antigos?**

- [x] sim (usando `_requestSeq` monotônico - last-write-wins)
- [ ] não
- [ ] não sei

**Pode acontecer de uma resposta antiga sobrescrever a nova?**

- [ ] sim (já vi "piscar" / sumir)
- [x] não (protegido por `if (requestId != _requestSeq) return`)
- [ ] não sei

---

## 6) Atualização de UI (às vezes carrega, mas não aparece)

**Como você atualiza os markers na UI?**

- [ ] setState substituindo o Set<Marker> inteiro
- [ ] setState mutando o mesmo Set (add/remove)
- [x] **ListenableBuilder** com `MapRenderController` como Listenable
- [ ] outro: _________

**Você garante MarkerId único?**

- [x] sim (usando `eventId` ou `cluster_lat_lng`)
- [ ] não sei
- [ ] já vi duplicado

**Quando "não carrega", o resultado da query vem vazio ou vem com dados?**

- [ ] vem vazio
- [x] vem com dados mas não renderiza (query retorna 1 evento, mas deveria ter mais na região)
- [ ] não sei (sem log)

---

## 7) Logs que você já tem

**Você tem logs hoje que mostram:**

- [x] "entrei no callback" (`📷 MapBoundsController: cameraIdle(...)`)
- [x] bounds calculado (`boundsKey=...`, `visible=...`, `expanded=...`)
- [x] cache hit/miss (`📦 [MapDiscovery] Memory cache HIT`, `source=network`)
- [x] motivo de early return (`📦 [DIAG] skipNetworkFetch: true, reason=inside_prefetch`)
- [x] quantidade de markers retornados (`count=1`, `events=1`)
- [x] quantidade de markers aplicados na UI (`markersProduced=2`, `individualRendered=1`)

---

## Trecho de Log Real (Pan + Zoom)

### Pan no Zoom 12 (NÃO CARREGA):
```
flutter: 📷 MapBoundsController: cameraIdle(boundsKey=-19.037_-48.324_-18.808_-48.182, zoom=12.0, ...)
flutter: 📍 MapBoundsController: Câmera parou (zoom: 12.0)
flutter: 📦 [DIAG] appliedCache=false, eventsCount=1
flutter: 📦 [DIAG] skipNetworkFetch: true, reason=inside_prefetch, zoomBucketChanged=false
```
**→ O fetch de rede é PULADO porque `withinPrefetched=true` e `zoomBucketChanged=false`**

### Zoom para 8.6 (CARREGA):
```
flutter: 📷 MapBoundsController: cameraIdle(boundsKey=-20.090_-48.878_-17.596_-47.331, zoom=8.6, ...)
flutter: 📍 MapBoundsController: Câmera parou (zoom: 8.6)
flutter: 🔄 MapBoundsController: Zoom bucket mudou (2 → 1)
flutter: 📦 [DIAG] appliedCache=false, eventsCount=1
flutter: 🌐 [DIAG] Disparando fetch de rede em paralelo...
flutter: ✅ MapDiscoveryService: 16 eventos encontrados
```
**→ O fetch de rede ACONTECE porque `zoomBucketChanged=true`**

---

## 🔍 Diagnóstico

### Causa Raiz Identificada:

O problema está na lógica de `skipNetworkFetch` no `MapBoundsController.onCameraIdle()`:

```dart
final skipNetworkFetch = withinPrefetched && !isMapEmpty && !zoomBucketChanged;
```

**O que acontece:**

1. Na busca inicial (`triggerInitialEventSearch`), o código buscava apenas no `visibleRegion` (pequeno), mas setava `prefetchedExpandedBounds` com bounds EXPANDIDO via `unawaited` (sem esperar)

2. Isso criava inconsistência:
   - `_lastRequestedQueryBounds` = bounds PEQUENO (visível)
   - `prefetchedExpandedBounds` = bounds GRANDE (expandido 4x)

3. No pan, a verificação `withinPrefetched` retornava `true` porque o viewport estava dentro do bounds expandido

4. **MAS** o fetch real nunca aconteceu para a região expandida (só foi agendado, não completou)

5. Resultado: `skipNetworkFetch = true` → não carrega novos eventos

### Quando funciona (zoom 3.0):

O `zoomBucket` muda (2 → 1 → 0), então `zoomBucketChanged = true` força o fetch de rede.

---

## ✅ Correções Aplicadas (v2 - Robusta)

### Problema com a v1:
A primeira correção ainda tinha um problema: usava `prefetchedExpandedBounds` como sinal de "tenho dados", mas isso era apenas geometria - não garantia que o prefetch havia completado.

### Solução v2: Estado Robusto de Prefetch

Adicionadas flags de controle no `MapBoundsController`:

```dart
// Estado robusto de prefetch
bool _prefetchInFlight = false;           // Prefetch em andamento?
DateTime? _prefetchCompletedAt;           // Quando completou?
LatLngBounds? _prefetchCoverageBounds;    // Bounds efetivamente carregado
static const Duration _prefetchFreshTtl = Duration(seconds: 60);
```

### 1. `prefetchEventsForExpandedBounds` - Marca estado de início/fim:
```dart
Future<void> prefetchEventsForExpandedBounds(LatLngBounds visibleRegion) async {
  if (_prefetchInFlight) return; // Evita duplicado
  
  _prefetchInFlight = true;
  try {
    await viewModel.loadEventsInBounds(prefetchQuery);
    
    // ✅ Sucesso: marca como completado
    _prefetchCoverageBounds = expanded;
    _prefetchCompletedAt = DateTime.now();
  } finally {
    _prefetchInFlight = false;
  }
}
```

### 2. `triggerInitialEventSearch` - Marca prefetch na busca inicial:
```dart
_prefetchInFlight = true;
try {
  await viewModel.forceRefreshBounds(expandedQueryBounds);
  
  // ✅ Marcar prefetch como completado com sucesso
  _prefetchCoverageBounds = pfExpandedBounds;
  _prefetchCompletedAt = DateTime.now();
} finally {
  _prefetchInFlight = false;
}
```

### 3. `onCameraIdle` - Verificação robusta:
```dart
// Verificar se está dentro do bounds EFETIVAMENTE carregado
final withinPrefetchCoverage = _prefetchCoverageBounds != null &&
    isLatLngBoundsContained(visibleRegion, _prefetchCoverageBounds!);

// Verificar se o prefetch está "fresco" (TTL de 60s)
final prefetchIsFresh = _prefetchCompletedAt != null &&
    now.difference(_prefetchCompletedAt!) < _prefetchFreshTtl;

// Só pode usar prefetch se: completou E está fresco E cobre a região E não está em andamento
final canSkipBecausePrefetched = withinPrefetchCoverage && prefetchIsFresh && !_prefetchInFlight;

// Condição final
final skipNetworkFetch = canSkipBecausePrefetched && !isMapEmpty && !zoomBucketChanged;
```

### 4. Logs detalhados para diagnóstico:
```
📦 [DIAG] withinPrefetchCoverage=true prefetchIsFresh=false inFlight=true completedAt=null
📦 [DIAG] skipNetworkFetch=false reason=prefetch_in_flight
```

---

## 🧪 Testes de Validação

### Teste 1 — Abrir app e dar pan imediato (zoom 12)
**Esperado:**
- `onCameraIdle` dispara
- `skipNetworkFetch` = **false** (prefetch ainda não completou ou não está fresh)
- Rede deve rodar pelo menos 1x

**Log esperado:**
```
📦 [DIAG] withinPrefetchCoverage=false prefetchIsFresh=false inFlight=false completedAt=null
🌐 [DIAG] Disparando fetch de rede (reason=outside_prefetch_coverage)...
```

### Teste 2 — Abrir app, esperar prefetch concluir, dar pan DENTRO da área expandida
**Esperado:**
- `withinPrefetchCoverage` = true
- `prefetchIsFresh` = true
- `skipNetworkFetch` = true
- Markers aparecem do cache

**Log esperado:**
```
📦 [DIAG] withinPrefetchCoverage=true prefetchIsFresh=true inFlight=false completedAt=2026-02-02T...
📦 [DIAG] skipNetworkFetch: true, reason=prefetch_valid
```

### Teste 3 — Pan para FORA do expanded bounds (a "borda")
**Esperado:**
- `withinPrefetchCoverage` = false
- `skipNetworkFetch` = false
- Dispara rede

**Log esperado:**
```
📦 [DIAG] withinPrefetchCoverage=false prefetchIsFresh=true inFlight=false completedAt=2026-02-02T...
🌐 [DIAG] Disparando fetch de rede (reason=outside_prefetch_coverage)...

---

## Interpretação Rápida

| Sintoma | Causa |
|---------|-------|
| ✅ `onCameraIdle` dispara no pan | Gatilho OK |
| ✅ Bounds mudam | Cálculo OK |
| ⚠️ Função é chamada mas faz early return | **BUG de cache/condição de saída** |
| ✅ Query retorna dados quando executa | Firestore OK |
| ✅ Não oscila/some | Race condition OK |

**Conclusão:** O problema era a condição de `skipNetworkFetch` que assumia erroneamente que o prefetch havia sido completado quando na verdade só foi agendado.
