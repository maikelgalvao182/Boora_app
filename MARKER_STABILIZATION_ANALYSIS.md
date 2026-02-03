# 🎯 Análise: Estabilização de Markers no Mapa

## Status Anterior (RESOLVIDO ✅)
- Snapshot nunca era populado → Adicionado `_captureAndApplySnapshot()`
- Render bloqueava se snapshot=null → Fallback para bounds globais
- `queryComplete` sempre false → Agora true após fetch/cache

---

## Próximo Bug: Markers Inflando / Renders Concorrentes

### 📍 Onde o `Set<Marker>` é mantido

```dart
// map_render_controller.dart (linhas 21-24)
Set<Marker> _markers = {};
Set<Marker> _avatarOverlayMarkers = {};
final Map<MarkerId, Marker> _staleMarkers = {};
final Map<MarkerId, DateTime> _staleMarkersExpiry = {};
```

### 📍 Getter `allMarkers` (linha 29)

```dart
Set<Marker> get allMarkers {
  final merged = <MarkerId, Marker>{};
  // 1. Primeiro: stale markers (ficam no fundo)
  for (final entry in _staleMarkers.entries) {
    merged[entry.key] = entry.value;
  }
  // 2. Depois: markers principais (sobrescrevem stale)
  for (final marker in _markers) {
    merged[marker.markerId] = marker;
  }
  // 3. Por fim: avatar overlays
  for (final marker in _avatarOverlayMarkers) {
    merged[marker.markerId] = marker;
  }
  return merged.values.toSet();
}
```

**Problema potencial:** Se um marker não existe em `_markers` mas ainda está em `_staleMarkers` após o TTL, ele permanece visível.

---

### 📍 Método `_addStaleMarkers` (linhas 574-596)

```dart
void _addStaleMarkers({
  required Set<Marker> previousMarkers,
  required Set<Marker> nextMarkers,
}) {
  final nextIds = nextMarkers.map((m) => m.markerId).toSet();
  final now = DateTime.now();

  for (final marker in previousMarkers) {
    if (nextIds.contains(marker.markerId)) continue;
    // Adiciona ao stale com alpha=0, zIndex=-10000, sem onTap
    _staleMarkers[marker.markerId] = marker.copyWith(
      alphaParam: 0.0,
      onTapParam: null,
      zIndexParam: -10000,
      infoWindowParam: InfoWindow.noText,
    );
    _staleMarkersExpiry[marker.markerId] = now.add(_staleMarkersTtl);
  }

  _pruneStaleMarkers(now);

  _staleMarkersTimer?.cancel();
  _staleMarkersTimer = Timer(_staleMarkersTtl, () {
    if (_isDisposed) return;
    _pruneStaleMarkers(DateTime.now());
    notifyListeners();
  });
}
```

**Problema identificado:** Se dois renders acontecem em sequência rápida:
1. Render A: `_addStaleMarkers(prev=markers1, next=markers2)` → adiciona diff ao stale
2. Render B: `_addStaleMarkers(prev=markers2, next=markers3)` → adiciona diff ao stale
3. **Acúmulo:** Stale nunca limpa markers de Render A se Render B também não os tinha

---

### 📍 Onde markers são aplicados (linhas 408-418)

```dart
_addStaleMarkers(
  previousMarkers: {..._markers, ..._avatarOverlayMarkers},
  nextMarkers: {...nextMarkers, ...nextAvatarOverlays},
);

_avatarOverlayMarkers = nextAvatarOverlays;
_markers = nextMarkers;
```

---

## 🐛 Problemas Identificados

### 1. Acúmulo de Stale Markers
- **Causa:** Cada render adiciona markers ausentes ao stale, mas `_pruneStaleMarkers` só remove expirados
- **Efeito:** `_staleMarkers.length` cresce continuamente
- **Log evidência:** `stale=${_staleMarkers.length}` nos logs

### 2. Renders Concorrentes Fora de Ordem
- **Causa:** Método `_rebuildMarkersUsingClusterService` é `async`
- **Cenário:**
  1. Camera move para posição A → inicia render A
  2. Camera move para posição B → inicia render B
  3. Render B termina primeiro → aplica markers B
  4. Render A termina depois → sobrescreve com markers A (ANTIGOS!)

- **Proteção existente:** `boundsKey` validation no início do método
```dart
if (_activeViewportBoundsKey != null && 
    querySnapshot != null && 
    querySnapshot.boundsKey != _activeViewportBoundsKey) {
  debugPrint('🧭 [MapRender] ❌ Descartando render: snapshot.boundsKey != activeViewportBoundsKey');
  return;
}
```
- **Gap:** Validação acontece no INÍCIO, mas o render é async. Quando termina, o `_activeViewportBoundsKey` pode ter mudado.

---

## ✅ Soluções Propostas

### Fix 1: Validação de boundsKey ANTES de aplicar markers

```dart
// ANTES de _addStaleMarkers e _markers = nextMarkers
final currentActiveBoundsKey = _activeViewportBoundsKey;
if (currentActiveBoundsKey != null && 
    renderBoundsKey != currentActiveBoundsKey) {
  debugPrint('🧭 [MapRender] ❌ Render descartado: boundsKey mudou durante render');
  return;
}
```

### Fix 2: Limpar stale markers obsoletos

```dart
void _addStaleMarkers({...}) {
  // ... código existente ...

  // 🆕 Limitar tamanho máximo do stale
  const maxStaleMarkers = 200;
  if (_staleMarkers.length > maxStaleMarkers) {
    final sortedByExpiry = _staleMarkersExpiry.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final toRemove = sortedByExpiry.take(_staleMarkers.length - maxStaleMarkers);
    for (final entry in toRemove) {
      _staleMarkers.remove(entry.key);
      _staleMarkersExpiry.remove(entry.key);
    }
  }
}
```

### Fix 3: Sequence number para renders

```dart
int _renderSequence = 0;

Future<void> _rebuildMarkersUsingClusterService(...) async {
  final mySequence = ++_renderSequence;
  
  // ... código do render ...
  
  // Antes de aplicar:
  if (mySequence != _renderSequence) {
    debugPrint('🧭 [MapRender] ❌ Render obsoleto (seq=$mySequence, atual=$_renderSequence)');
    return;
  }
  
  _addStaleMarkers(...);
  _markers = nextMarkers;
}
```

---

## 📊 Métricas para Validar Fix

Após implementar, verificar nos logs:
1. `stale=${_staleMarkers.length}` deve estabilizar (não crescer infinitamente)
2. Não deve aparecer "markers antigos" após pan rápido
3. `boundsKey` no log de render deve sempre corresponder ao viewport atual

---

## 📁 Arquivos Relevantes

| Arquivo | Linhas | Responsabilidade |
|---------|--------|------------------|
| `map_render_controller.dart` | 21-24 | Storage de markers |
| `map_render_controller.dart` | 29-41 | `allMarkers` getter |
| `map_render_controller.dart` | 574-596 | `_addStaleMarkers` |
| `map_render_controller.dart` | 600-612 | `_pruneStaleMarkers` |
| `map_render_controller.dart` | 408-418 | Aplicação final de markers |

---

## 🎯 Próximos Passos

1. ~~**Implementar Fix 3** (sequence number) - mais seguro~~ ✅ IMPLEMENTADO como Fix A
2. **Implementar Fix 2** (cap no stale) - previne memory leak
3. **Testar** com pan rápido e zoom in/out frequente
4. **Verificar** logs de `stale=` não crescendo

---

## ✅ Fix A Implementado (2025-02-03)

**Render Token + Validação Dupla**

```dart
// Linha 75: variável de instância
int _renderToken = 0;

// Linha 228-229: captura no início do método
final myToken = ++_renderToken;
final renderBoundsKey = _activeViewportBoundsKey;

// Linhas 420-429: validação ANTES de aplicar markers
if (myToken != _renderToken) {
  debugPrint('🧭 [MapRender] ❌ Render obsoleto descartado (token=$myToken, atual=$_renderToken)');
  return;
}
final currentActiveKey = _activeViewportBoundsKey;
if (currentActiveKey != null && renderBoundsKey != currentActiveKey) {
  debugPrint('🧭 [MapRender] ❌ Bounds mudou durante render (render=$renderBoundsKey, atual=$currentActiveKey)');
  return;
}
```

**Resultado esperado:** Renders velhos não aplicam mais, eliminando ~90% da inflação de markers.
