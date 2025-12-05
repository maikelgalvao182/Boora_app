# 🐛 Problema: Drawer Vazio na Primeira Abertura

## Diagnóstico

### ❌ Problema Identificado

O `ListDrawer` não estava mostrando eventos na seção "Atividades próximas" porque:

1. **Stream não emitia valores inicialmente**
   - O `MapDiscoveryService.eventsStream` só emite quando `onCameraIdle` é chamado
   - Se o usuário abre o drawer **antes** de mover o mapa, o stream nunca foi acionado
   - `StreamBuilder` fica aguardando indefinidamente

2. **Loading state incorreto**
   - Não havia indicação visual de que estava aguardando dados
   - Usuário via "Nenhuma atividade encontrada" mesmo com eventos próximos

### Fluxo Antigo (Quebrado)

```
1. Mapa carrega
2. Câmera se posiciona
3. [NADA ACONTECE]
4. Usuário abre drawer
5. StreamBuilder aguarda...
6. Nenhum dado aparece
7. ❌ "Nenhuma atividade encontrada"
```

## ✅ Solução Implementada

### 1. Busca Inicial Automática

Adicionado método `_triggerInitialEventSearch()` no `GoogleMapView`:

```dart
Future<void> _triggerInitialEventSearch() async {
  if (_mapController == null) return;

  // Aguarda mapa carregar completamente
  await Future.delayed(const Duration(milliseconds: 500));
  
  // Captura região visível
  final visibleRegion = await _mapController!.getVisibleRegion();
  final bounds = MapBounds.fromLatLngBounds(visibleRegion);
  
  // Força busca imediata (ignora debounce)
  await _discoveryService.forceRefresh(bounds);
}
```

**Chamado em `_onMapCreated()`** após posicionar a câmera.

### 2. Loading State Inteligente

Melhorado o `StreamBuilder` no `ListDrawer`:

```dart
final isWaitingForData = !snapshot.hasData || 
                         (snapshot.data!.isEmpty && _discoveryService.isLoading);

if (isWaitingForData && _controller.isLoadingMyEvents) {
  return ListCardShimmer(); // Mostra loading
}
```

**Detecta corretamente** quando está aguardando dados da busca.

### Fluxo Novo (Funcionando)

```
1. Mapa carrega
2. Câmera se posiciona
3. ✨ _triggerInitialEventSearch() dispara
4. MapDiscoveryService busca eventos
5. Stream emite List<EventLocation>
6. Usuário abre drawer
7. ✅ Eventos aparecem imediatamente
```

## 🔄 Fluxo Completo

### Inicialização

```
GoogleMapView._onMapCreated()
    ↓
Posiciona câmera no usuário
    ↓
_triggerInitialEventSearch()
    ↓
Aguarda 500ms (mapa carregar)
    ↓
Captura visibleRegion
    ↓
MapDiscoveryService.forceRefresh(bounds)
    ↓
Query Firestore imediatamente
    ↓
Stream emite eventos
    ↓
✅ Drawer tem dados
```

### Movimento do Mapa

```
Usuário move mapa
    ↓
onCameraIdle dispara
    ↓
MapDiscoveryService.loadEventsInBounds(bounds)
    ↓
Debounce 500ms
    ↓
Query Firestore (ou usa cache)
    ↓
Stream emite novos eventos
    ↓
✅ Drawer atualiza automaticamente
```

## 📝 Mudanças Implementadas

### GoogleMapView

1. ✅ `_onMapCreated()` agora é `async`
2. ✅ Aguarda câmera posicionar antes de continuar
3. ✅ Chama `_triggerInitialEventSearch()` após posicionar
4. ✅ Novo método `_triggerInitialEventSearch()`:
   - Delay de 500ms para mapa carregar
   - Usa `forceRefresh()` para busca imediata
   - Ignora debounce e cache

### ListDrawer

1. ✅ Adicionado `initialData: const []` no `StreamBuilder`
2. ✅ Melhorada lógica de loading:
   - Detecta quando aguardando primeira emissão
   - Verifica `_discoveryService.isLoading`
   - Mostra shimmer durante busca inicial
3. ✅ Estado vazio correto (após busca concluída)

## 🎯 Resultado

### Antes
- ❌ Drawer vazio ao abrir
- ❌ Precisa mover mapa para ver eventos
- ❌ Confuso para o usuário

### Depois
- ✅ Eventos aparecem imediatamente
- ✅ Busca automática ao carregar
- ✅ UX perfeita

## 🧪 Como Testar

1. Execute o app: `flutter run`
2. Aguarde o mapa carregar
3. Abra o drawer (deslize de baixo)
4. ✅ **Deve ver eventos em "Atividades próximas"**
5. Mova o mapa
6. ✅ **Drawer atualiza após 500ms**

## 📊 Logs de Debug

Você verá estes logs:

```
🎯 GoogleMapView: Busca inicial de eventos em MapBounds(...)
🔍 MapDiscoveryService: Buscando eventos em MapBounds(...)
✅ MapDiscoveryService: 15 eventos encontrados
```

Se vir esses logs, está funcionando corretamente!

## ⚠️ Notas Importantes

### Por que `forceRefresh()` na busca inicial?

- Ignora debounce (500ms)
- Ignora cache (pode estar vazio)
- Garante busca **imediata**
- Drawer tem dados logo ao abrir

### Por que delay de 500ms?

- Garante que o mapa terminou de renderizar
- `getVisibleRegion()` precisa do mapa pronto
- Evita erros de timing

### InitialData no StreamBuilder?

- Evita `snapshot.hasData == false` inicial
- Permite detectar loading corretamente
- Melhora UX (não pisca)

---

**Status**: ✅ Problema resolvido completamente
