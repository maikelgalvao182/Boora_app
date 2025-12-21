import 'dart:math' as math;
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/features/home/data/models/event_model.dart';

/// Representa um cluster de eventos no mapa
/// 
/// Pode conter:
/// - 1 evento: renderiza marker individual
/// - N eventos: renderiza cluster com badge
class MarkerCluster {
  /// Eventos agrupados neste cluster
  final List<EventModel> events;
  
  /// Posição central do cluster (média das coordenadas)
  final LatLng center;
  
  /// Chave do grid (ex: "123:456")
  final String gridKey;

  MarkerCluster({
    required this.events,
    required this.center,
    required this.gridKey,
  });

  /// Retorna true se cluster tem apenas 1 evento
  bool get isSingleEvent => events.length == 1;
  
  /// Retorna o primeiro evento (usado para clusters únicos)
  EventModel get firstEvent => events.first;
  
  /// Quantidade de eventos no cluster
  int get count => events.length;
  
  /// Emoji representativo do cluster (do primeiro evento)
  String get representativeEmoji => events.first.emoji;
}

/// Serviço responsável por agrupar markers em clusters baseados em grid
/// 
/// Implementa clustering grid-based dependente de zoom:
/// - Converte lat/lng → coordenadas de tela (Web Mercator)
/// - Divide a tela em células (grid)
/// - Agrupa eventos que caem na mesma célula
/// - Separa eventos com coordenadas idênticas em zoom alto
/// - Retorna clusters para renderização
/// 
/// PERFORMANCE:
/// - Executa apenas em onCameraIdle (NUNCA em onCameraMove)
/// - Grid simples O(n) - performa bem até milhares de pontos
/// - Não usa quadtree para manter simplicidade
class MarkerClusterService {
  /// Cache de clusters por chave de zoom
  final Map<String, List<MarkerCluster>> _clusterCache = {};
  
  /// Offset base em graus para separar markers sobrepostos
  /// Aproximadamente 10 metros no equador
  static const double _baseOffsetDegrees = 0.0001;

  /// Zoom máximo para ativar clustering
  /// Acima deste zoom (visão mais próxima), mostra apenas markers individuais
  /// Abaixo ou igual (visão ampla), ativa o clustering
  static const double _maxClusterZoom = 11.0;

  /// Retorna tamanho do grid baseado no zoom atual
  /// 
  /// Quanto maior o zoom, menor o grid (menos clustering)
  /// Quanto menor o zoom, maior o grid (mais clustering)
  double _gridSizeForZoom(double zoom) {
    if (zoom >= 17) return 30;   // Quase sem cluster
    if (zoom >= 16) return 50;   // Mínimo clustering
    if (zoom >= 15) return 70;   // Pouco clustering
    if (zoom >= 14) return 100;  // Clustering médio-baixo
    if (zoom >= 13) return 140;  // Clustering médio
    if (zoom >= 12) return 180;  // Clustering médio-alto
    if (zoom >= 10) return 250;  // Clustering alto
    return 350;                   // Clusters grandes (visão continental)
  }
  
  /// Zoom a partir do qual eventos sobrepostos devem ser separados
  static const double _separationZoomThreshold = 15.0;

  /// Converte LatLng para ponto de tela usando projeção Web Mercator (EPSG:3857)
  /// 
  /// Esta é a mesma projeção usada pelo Google Maps internamente.
  /// Permite calcular posição de pixels consistente com o zoom.
  Point<double> _latLngToPoint(LatLng latLng, double zoom) {
    final scale = 256 * math.pow(2, zoom);
    
    // Longitude → X (linear)
    final x = (latLng.longitude + 180) / 360 * scale;
    
    // Latitude → Y (Mercator)
    final siny = math.sin(latLng.latitude * math.pi / 180);
    // Clamp para evitar infinito nos polos
    final clampedSiny = siny.clamp(-0.9999, 0.9999);
    final y = (0.5 - math.log((1 + clampedSiny) / (1 - clampedSiny)) / (4 * math.pi)) * scale;
    
    return Point(x.toDouble(), y.toDouble());
  }

  /// Converte ponto de tela de volta para LatLng
  /// 
  /// Útil para calcular o centro de um cluster a partir de coordenadas de pixel.
  LatLng _pointToLatLng(Point<double> point, double zoom) {
    final scale = 256 * math.pow(2, zoom);
    
    // X → Longitude
    final longitude = (point.x / scale) * 360 - 180;
    
    // Y → Latitude (inverso da projeção Mercator)
    final n = math.pi - 2 * math.pi * point.y / scale;
    final latitude = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    
    return LatLng(latitude, longitude);
  }

  /// Separa eventos com coordenadas idênticas aplicando offset em espiral
  /// 
  /// Quando zoom está alto e eventos estão exatamente sobrepostos,
  /// aplica um pequeno offset para que fiquem visíveis separadamente.
  /// 
  /// Parâmetros:
  /// - [events]: Lista de eventos a processar
  /// - [zoom]: Nível de zoom atual
  /// 
  /// Retorna:
  /// - Mapa de eventId → LatLng (com ou sem offset)
  Map<String, LatLng> _separateOverlappingEvents(List<EventModel> events, double zoom) {
    final Map<String, LatLng> positions = {};
    
    // Se zoom baixo, não separar (deixar clustering agrupar)
    if (zoom < _separationZoomThreshold) {
      for (final event in events) {
        positions[event.id] = LatLng(event.lat, event.lng);
      }
      return positions;
    }
    
    // Agrupar eventos por coordenadas exatas
    final Map<String, List<EventModel>> byCoordinate = {};
    
    for (final event in events) {
      // Chave com precisão de 6 casas decimais (~10cm)
      final coordKey = '${event.lat.toStringAsFixed(6)}_${event.lng.toStringAsFixed(6)}';
      byCoordinate.putIfAbsent(coordKey, () => []).add(event);
    }
    
    // Aplicar offset para eventos sobrepostos
    for (final entry in byCoordinate.entries) {
      final eventsAtCoord = entry.value;
      
      if (eventsAtCoord.length == 1) {
        // Único evento nesta coordenada - sem offset
        final event = eventsAtCoord.first;
        positions[event.id] = LatLng(event.lat, event.lng);
      } else {
        // Múltiplos eventos - aplicar offset em espiral
        debugPrint('🔄 [ClusterService] Separando ${eventsAtCoord.length} eventos sobrepostos');
        
        for (int i = 0; i < eventsAtCoord.length; i++) {
          final event = eventsAtCoord[i];
          
          if (i == 0) {
            // Primeiro evento fica no centro
            positions[event.id] = LatLng(event.lat, event.lng);
          } else {
            // Demais eventos em espiral ao redor
            // Ângulo baseado no índice (distribui uniformemente)
            final angle = (2 * math.pi * i) / (eventsAtCoord.length - 1);
            
            // Distância aumenta com o zoom (mais zoom = mais separação visual)
            final distance = _baseOffsetDegrees * (1 + (zoom - _separationZoomThreshold) * 0.3);
            
            final offsetLat = event.lat + distance * math.cos(angle);
            final offsetLng = event.lng + distance * math.sin(angle);
            
            positions[event.id] = LatLng(offsetLat, offsetLng);
          }
        }
      }
    }
    
    return positions;
  }

  /// Agrupa eventos em clusters baseados no zoom atual
  /// 
  /// Parâmetros:
  /// - [events]: Lista de eventos a serem agrupados
  /// - [zoom]: Nível de zoom atual do mapa
  /// - [useCache]: Se true, retorna cache se disponível (default: true)
  /// 
  /// Retorna:
  /// - Lista de MarkerCluster (eventos agrupados ou individuais)
  List<MarkerCluster> clusterEvents({
    required List<EventModel> events,
    required double zoom,
    bool useCache = true,
  }) {
    if (events.isEmpty) return [];

    // ⭐ Se zoom > 10, não fazer clustering (apenas markers individuais em visão próxima)
    if (zoom > _maxClusterZoom) {
      debugPrint('📍 [ClusterService] Zoom ${zoom.toStringAsFixed(1)} > $_maxClusterZoom - Sem clustering (${events.length} markers individuais)');
      
      return events.map((event) {
        return MarkerCluster(
          center: LatLng(event.lat, event.lng),
          events: [event],
          gridKey: 'single_${event.id}',
        );
      }).toList();
    }

    // 🔲 Zoom <= 10: Ativar clustering (visão ampla do mapa)
    debugPrint('🔲 [ClusterService] Zoom ${zoom.toStringAsFixed(1)} <= $_maxClusterZoom - Clustering ativado');

    // Gerar chave de cache baseada no zoom (arredondado)
    final cacheKey = 'z${zoom.round()}_${events.length}';
    
    // Verificar cache
    if (useCache && _clusterCache.containsKey(cacheKey)) {
      debugPrint('⚡ [ClusterService] Cache hit: $cacheKey');
      return _clusterCache[cacheKey]!;
    }

    final stopwatch = Stopwatch()..start();
    final gridSize = _gridSizeForZoom(zoom);
    
    debugPrint('🔲 [ClusterService] Clustering ${events.length} eventos (zoom: ${zoom.toStringAsFixed(1)}, grid: ${gridSize.toInt()}px)');

    // Separar eventos sobrepostos (aplica offset em zoom alto)
    final separatedPositions = _separateOverlappingEvents(events, zoom);

    // Mapa de grid → eventos
    final Map<String, List<EventModel>> gridMap = {};

    // Agrupar eventos por célula do grid (usando posições separadas)
    for (final event in events) {
      final position = separatedPositions[event.id] ?? LatLng(event.lat, event.lng);
      final point = _latLngToPoint(position, zoom);
      
      // Calcular índices do grid
      final gridX = (point.x / gridSize).floor();
      final gridY = (point.y / gridSize).floor();
      final gridKey = '$gridX:$gridY';

      gridMap.putIfAbsent(gridKey, () => []).add(event);
    }

    // Converter mapa de grid em lista de clusters
    final clusters = gridMap.entries.map((entry) {
      final eventsInCell = entry.value;
      
      // Calcular centro do cluster (usando posições separadas)
      double avgLat = 0;
      double avgLng = 0;
      
      for (final event in eventsInCell) {
        final position = separatedPositions[event.id] ?? LatLng(event.lat, event.lng);
        avgLat += position.latitude;
        avgLng += position.longitude;
      }
      
      avgLat /= eventsInCell.length;
      avgLng /= eventsInCell.length;

      return MarkerCluster(
        events: eventsInCell,
        center: LatLng(avgLat, avgLng),
        gridKey: entry.key,
      );
    }).toList();

    // Cachear resultado
    _clusterCache[cacheKey] = clusters;

    stopwatch.stop();
    
    // Estatísticas de clustering
    final singleCount = clusters.where((c) => c.isSingleEvent).length;
    final groupedCount = clusters.length - singleCount;
    
    debugPrint('✅ [ClusterService] ${clusters.length} clusters criados ($singleCount individuais, $groupedCount agrupados) em ${stopwatch.elapsedMilliseconds}ms');

    return clusters;
  }
  
  /// Retorna a posição (com offset se necessário) para um evento específico
  /// 
  /// Usado pelo GoogleEventMarkerService para posicionar markers individuais
  /// quando eventos sobrepostos são separados.
  LatLng getPositionForEvent(EventModel event, List<EventModel> allEvents, double zoom) {
    final positions = _separateOverlappingEvents(allEvents, zoom);
    return positions[event.id] ?? LatLng(event.lat, event.lng);
  }

  /// Limpa cache de clusters
  /// 
  /// Deve ser chamado quando:
  /// - Eventos são adicionados/removidos
  /// - Filtros mudam
  void clearCache() {
    _clusterCache.clear();
    debugPrint('🗑️ [ClusterService] Cache limpo');
  }

  /// Remove cache de um zoom específico
  void clearCacheForZoom(double zoom) {
    final keysToRemove = _clusterCache.keys
        .where((key) => key.startsWith('z${zoom.round()}_'))
        .toList();
    
    for (final key in keysToRemove) {
      _clusterCache.remove(key);
    }
  }
}
