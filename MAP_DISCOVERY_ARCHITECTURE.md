# Arquitetura de Descoberta por Bounding Box

## 🎯 Visão Geral

Sistema de descoberta de eventos baseado em **bounded queries** (padrão Airbnb) que busca eventos dentro da região visível do mapa.

## 🏗️ Arquitetura

```
Usuário move o mapa
    ↓
GoogleMapView.onCameraIdle()
    ↓
Captura LatLngBounds visível
    ↓
MapBounds.fromLatLngBounds()
    ↓
MapDiscoveryService.loadEventsInBounds()
    ↓
[Debounce 500ms]
    ↓
Query Firestore com bounding box
    ↓
Filtra longitude em código
    ↓
Emite List<EventLocation> via Stream
    ↓
ListDrawer.StreamBuilder atualiza
    ↓
Drawer exibe eventos próximos
```

## 📁 Estrutura de Arquivos

### Modelos
- **`map_bounds.dart`** - Representa bounding box (minLat, maxLat, minLng, maxLng)
- **`event_location.dart`** - Evento simplificado com localização

### Serviços
- **`map_discovery_service.dart`** - Singleton que gerencia descoberta de eventos
  - Stream reativa (`eventsStream`)
  - Cache com TTL (10s)
  - Debounce automático (500ms)
  - Quadkey para cache inteligente

### UI
- **`google_map_view.dart`** - Adiciona callback `onCameraIdle`
- **`list_drawer.dart`** - StreamBuilder conectado ao serviço
- **`discover_screen.dart`** - Tela principal (já configurado)

## 🔥 MapDiscoveryService

### Características

✅ **Singleton** - Instância única em toda aplicação  
✅ **Stream reativa** - UI atualiza automaticamente  
✅ **Debounce** - Evita queries excessivas durante movimento  
✅ **Cache com TTL** - Reutiliza resultados recentes  
✅ **Quadkey** - Cache baseado em região geográfica  

### API

```dart
final service = MapDiscoveryService();

// Stream reativa
service.eventsStream.listen((events) {
  print('${events.length} eventos encontrados');
});

// Buscar eventos em região
await service.loadEventsInBounds(bounds);

// Forçar atualização (ignora cache)
await service.forceRefresh(bounds);

// Limpar cache
service.clearCache();
```

## 📍 MapBounds

### Criação

```dart
// Do Google Maps
final visibleRegion = await controller.getVisibleRegion();
final bounds = MapBounds.fromLatLngBounds(visibleRegion);

// Manual
final bounds = MapBounds(
  minLat: -23.6,
  maxLat: -23.5,
  minLng: -46.7,
  maxLng: -46.6,
);
```

### Utilidades

```dart
// Verificar se ponto está dentro
bounds.contains(-23.55, -46.65); // true

// Calcular área aproximada
bounds.areaKm2; // ~100.0

// Gerar quadkey para cache
bounds.toQuadkey(); // "-23_-46"
```

## 🔍 Query Firestore

### Limitação

Firestore permite apenas **1 range query** por vez. Por isso:

1. Query por **latitude** (range)
2. Filtra **longitude** em código

```dart
final query = await _firestore
    .collection('events')
    .where('location.latitude', isGreaterThanOrEqualTo: bounds.minLat)
    .where('location.latitude', isLessThanOrEqualTo: bounds.maxLat)
    .limit(100)
    .get();

// Filtrar longitude em código
for (final doc in query.docs) {
  if (bounds.contains(event.latitude, event.longitude)) {
    events.add(event);
  }
}
```

## ⚡ Performance

### Cache Inteligente

- **TTL**: 10 segundos
- **Quadkey**: Região geográfica (~1km de precisão)
- **Evita queries repetidas** na mesma área

### Debounce

- **500ms** de delay
- Aguarda usuário parar de mover o mapa
- Cancela queries pendentes

### Limites

- **100 eventos** por query
- Ideal para evitar sobrecarga
- Suficiente para maioria dos casos de uso

## 🎨 ListDrawer

### Seções

1. **Atividades próximas** (do mapa via stream)
2. **Suas atividades** (eventos criados pelo usuário)

### StreamBuilder

```dart
StreamBuilder<List<EventLocation>>(
  stream: _discoveryService.eventsStream,
  builder: (context, snapshot) {
    final events = snapshot.data ?? [];
    
    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (_, i) {
        return EventCard(eventId: events[i].eventId);
      },
    );
  },
)
```

## 🚀 Fluxo Completo

### 1. Inicialização

```dart
// DiscoverScreen monta
// → Callback onCenterUserRequested dispara
// → Câmera move para usuário
// → onCameraIdle dispara primeira busca
```

### 2. Movimento do Mapa

```dart
// Usuário arrasta mapa
// → onCameraIdle aguarda parada
// → Captura bounding box
// → MapDiscoveryService.loadEventsInBounds()
// → Debounce 500ms
// → Query Firestore
// → Stream emite eventos
// → ListDrawer atualiza
```

### 3. Cache Hit

```dart
// Mesma região dentro de 10s
// → Verifica quadkey
// → Retorna cache
// → Emite eventos instantaneamente
```

## 🔧 Configurações

```dart
// MapDiscoveryService
static const Duration cacheTTL = Duration(seconds: 10);
static const Duration debounceTime = Duration(milliseconds: 500);
static const int maxEventsPerQuery = 100;
```

## 🎯 Separação de Responsabilidades

| Componente | Responsabilidade |
|------------|------------------|
| **MapBounds** | Representar região geográfica |
| **EventLocation** | Dados simplificados do evento |
| **MapDiscoveryService** | Query, cache, stream |
| **GoogleMapView** | Capturar bounding box |
| **ListDrawer** | Exibir eventos |
| **DiscoverScreen** | Orquestrar tela |

## ⚠️ Importante

### Totalmente separado de:
- ❌ Filtros sociais
- ❌ Raio de busca
- ❌ EventMapRepository
- ❌ MapViewModel

### Foco exclusivo:
- ✅ Eventos na região **visível** do mapa
- ✅ Atualização **automática** ao mover
- ✅ Performance otimizada

## 🧪 Testando

```dart
// 1. Abra DiscoverScreen
// 2. Mapa carrega
// 3. Drawer mostra "Atividades próximas"
// 4. Mova o mapa
// 5. Drawer atualiza após 500ms
// 6. Move para mesma região dentro de 10s
// 7. Drawer atualiza instantaneamente (cache)
```

## 📈 Próximos Passos (Opcionais)

- [ ] Clustering de markers (Google Maps Clustering)
- [ ] Lazy loading (paginação)
- [ ] Cache persistente (Hive/SharedPreferences)
- [ ] Índices compostos no Firestore
- [ ] Analytics de queries
- [ ] Filtros avançados no drawer

---

**Status**: ✅ Implementação completa e funcional
