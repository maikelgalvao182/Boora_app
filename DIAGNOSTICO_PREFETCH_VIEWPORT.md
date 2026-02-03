# Diagnóstico: Prefetch vs Viewport — Respostas e Status

## 1) Prefetch pode alterar "active" no Discovery?

### 1.1) Quando prefetchNeighbors=true (ou prefetch de expanded bounds), o loadEventsInBounds() do Discovery:

| Comportamento | ANTES do fix | DEPOIS do fix |
|--------------|--------------|---------------|
| Atualiza `_activeBoundsKey` | ✅ SIM (BUG!) | ❌ NÃO |
| Atualiza `nearbyEvents.value` | ✅ SIM (BUG!) | ❌ NÃO |
| Marca `_lastAppliedBoundsKey` | ✅ SIM (BUG!) | ❌ NÃO |
| Apenas salva em cache e retorna | ❌ NÃO | ✅ SIM |

### ✅ Fix aplicado:
Criado método `prefetchEventsForBounds()` no Discovery que **só cacheia** sem alterar estado:

```dart
// lib/features/home/data/services/map_discovery_service.dart
Future<void> prefetchEventsForBounds(MapBounds bounds, {double? zoom}) async {
  // NÃO altera _activeBoundsKey
  // NÃO altera _lastAppliedBoundsKey
  // NÃO altera nearbyEvents.value
  // Apenas popula cache para uso futuro
  ...
}
```

---

## 2) Você tem dois conceitos diferentes: "viewport ativo" vs "prefetch alvo"?

### 2.1) Hoje você usa uma única variável `_activeBoundsKey` para:

| Antes | Depois |
|-------|--------|
| ❌ `_activeBoundsKey` usado para viewport E prefetch (bug!) | ✅ `_activeBoundsKey` usado APENAS para viewport |

### ✅ Fix aplicado:
- Prefetch agora usa método separado que **não toca** em `_activeBoundsKey`
- MapBoundsController chama `viewModel.prefetchEventsForBounds()` em vez de `loadEventsInBounds()`

```dart
// lib/features/home/presentation/widgets/map_controllers/map_bounds_controller.dart
Future<void> prefetchEventsForExpandedBounds(LatLngBounds expandedBounds) async {
  // ✅ FIX: Usa prefetchEventsForBounds que só cacheia sem alterar estado
  await viewModel.prefetchEventsForBounds(prefetchQuery);
  // NÃO chama loadEventsInBounds!
}
```

---

## 3) lastQueryWasAppliedForActiveKey está validando o "active" certo?

### 3.1) Quem define `_activeBoundsKey`?

| Componente | ANTES | DEPOIS |
|------------|-------|--------|
| MapVM (setExpandedBoundsKey) | ❌ Não existia | ✅ Define `_expandedBoundsKey` local |
| Discovery (quando começa query viewport) | ✅ Define | ✅ Define (apenas viewport) |
| Prefetch (quando dispara query) | ✅ Definia (BUG!) | ❌ NÃO define mais |
| MapRender | ❌ Não define | ❌ Não define |

### ✅ Status:
- `lastQueryWasAppliedForActiveKey` agora compara corretamente:
  ```dart
  bool get lastQueryWasAppliedForActiveKey => 
      _lastAppliedBoundsKey != null && 
      _lastAppliedBoundsKey == _activeBoundsKey;
  ```
- Como prefetch não altera `_activeBoundsKey`, o getter funciona corretamente

---

## 4) O requestSeq é global e mistura prefetch + viewport?

### 4.1) O `_requestSeq` do Discovery incrementa para:

| Tipo de query | ANTES | DEPOIS |
|---------------|-------|--------|
| Viewport | ✅ Incrementa | ✅ Incrementa |
| Prefetch via loadEventsInBounds | ✅ Incrementava (BUG!) | N/A (não usa mais) |
| Prefetch via prefetchEventsForBounds | N/A | ❌ NÃO incrementa |

### ✅ Fix aplicado:
- `prefetchEventsForBounds()` não usa `_requestSeq`
- Não cria novo completer
- Não interfere com o fluxo de debounce do viewport

---

## 5) A lógica de emptyConfirmed usa "activeKey do MapVM" ou "active do Discovery"?

### 5.1) Análise do bug original:

```
Log original (BUG):
- boundsKey usado pro clear: -90...60.579 (MapVM atual) 
- requestSeq do clear: 8 (prefetch!)
```

**Problema:** MapVM usava `_buildVisibleBoundsKey()` (bounds visível) mas comparava com `_activeBoundsKey` do Discovery (que foi alterado pelo prefetch).

### ✅ Fix aplicado:
1. MapVM agora usa `_buildExpandedBoundsKey()` que retorna `_expandedBoundsKey` (consistente com Discovery)
2. Prefetch não altera mais `_activeBoundsKey`, então não há contaminação

```dart
// lib/features/home/presentation/viewmodels/parts/map_viewmodel_sync.part.dart
if (emptyConfirmed) {
  // ✅ FIX: Usar expandedBoundsKey (deve bater com Discovery._activeBoundsKey)
  final boundsKey = _buildExpandedBoundsKey();
  ...
}
```

---

## 🧩 Detalhe suspeito no log original

```
[PREFETCH] loadKey=-90...49.182|zb=2|pref=false
```

**Por que `pref=false` num prefetch?**

### Resposta:
O prefetch estava usando `loadEventsInBounds()` normal (função do viewport), então a flag `prefetchNeighbors` era do parâmetro interno, não indicava que era prefetch.

### ✅ Fix:
Agora prefetch usa `prefetchEventsForBounds()` - método completamente separado.

---

## 📊 Resumo das Correções Aplicadas

| Arquivo | Mudança |
|---------|---------|
| `map_discovery_service.dart` | Novo método `prefetchEventsForBounds()` que só cacheia |
| `map_viewmodel_sync.part.dart` | Novo método `prefetchEventsForBounds()` no MapVM |
| `map_viewmodel_sync.part.dart` | Usa `_buildExpandedBoundsKey()` em vez de `_buildVisibleBoundsKey()` |
| `map_viewmodel.dart` | Novo campo `_expandedBoundsKey` e método `setExpandedBoundsKey()` |
| `map_bounds_controller.dart` | `prefetchEventsForExpandedBounds()` usa `prefetchEventsForBounds()` |
| `map_bounds_controller.dart` | Chama `viewModel.setExpandedBoundsKey(expandedKey)` no `onCameraIdle` |

---

## 🔄 Fluxo Corrigido

### Antes (BUG):
```
📷 cameraIdle(viewport zb=0, tem 3 eventos)
🚀 prefetch dispara loadEventsInBounds(zb=2)
📊 Discovery: _activeBoundsKey = prefetch_key (ERRADO!)
📊 APPLY(prefetch): nearbyEvents = [] (ERRADO!)
🟣 MapVM: appliedForActiveKey=true (baseado no prefetch!)
🟣 emptyConfirmed=true → clear markers ❌
```

### Depois (CORRETO):
```
📷 cameraIdle(viewport zb=0, tem 3 eventos)
   → setExpandedBoundsKey(viewport_key)
   → loadEventsInBounds(viewport_key)
📊 Discovery: _activeBoundsKey = viewport_key ✅
🚀 prefetch dispara prefetchEventsForBounds(zb=2)
📦 prefetch só cacheia, _activeBoundsKey INALTERADO ✅
📊 APPLY(viewport): nearbyEvents = [3 eventos] ✅
🟣 MapVM: appliedForActiveKey=true (viewport correto!)
🧭 MapRender: markers=3 ✅
```

---

## 🧪 Logs de Diagnóstico Adicionados

### A) No Discovery, no APPLY:
```dart
debugPrint('📊 [MapDiscovery] APPLY(cache): bKey=$bKey, active=$_activeBoundsKey, lastApplied=$_lastAppliedBoundsKey, count=${filtered.length}');
debugPrint('📊 [MapDiscovery] APPLY(network): bKey=$bKey, active=$_activeBoundsKey, lastApplied=$_lastAppliedBoundsKey, count=${filtered.length}');
```

### B) No MapRender, no CHECK:
```dart
debugPrint('🧭 [MapRender] CHECK: snapKey=$snapBoundsKey, activeKey=$_activeViewportBoundsKey, vmExpKey=$vmExpandedKey, events=${filteredEvents.length}');
```

### C) No Prefetch:
```dart
debugPrint('🚀 [PREFETCH] Iniciando prefetch ISOLADO para bounds expandido...');
debugPrint('✅ [PREFETCH] Concluído em ${elapsed}ms (cache-only, não alterou active)');
```

---

## ✅ Conclusão

**Todos os 5 pontos do diagnóstico foram corrigidos:**

1. ✅ Prefetch não altera mais `_activeBoundsKey`
2. ✅ Prefetch usa método separado `prefetchEventsForBounds()`
3. ✅ `lastQueryWasAppliedForActiveKey` compara com o active correto (viewport)
4. ✅ `_requestSeq` não é incrementado por prefetch
5. ✅ `emptyConfirmed` usa `_expandedBoundsKey` do MapVM (consistente com Discovery)

**O bug "52 eventos fixo" / "markers=0 após pan" deve estar resolvido.**
