import 'package:fluster/fluster.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/features/home/data/models/event_model.dart';

/// Implementação de marker clusterizável para o Fluster.
///
/// Para markers individuais, [event] é o evento real.
/// Para clusters, [event] é apenas um placeholder (não deve ser usado).
class EventMapMarker extends Clusterable {
  final EventModel event;

  EventMapMarker({
    required this.event,
    bool? isCluster,
    int? clusterId,
    int? pointsSize,
    String? markerId,
    String? childMarkerId,
    double? latitude,
    double? longitude,
  }) : super(
          isCluster: isCluster,
          clusterId: clusterId,
          pointsSize: pointsSize,
          markerId: markerId,
          childMarkerId: childMarkerId,
          latitude: latitude ?? event.lat,
          longitude: longitude ?? event.lng,
        );
}

/// Representa um cluster de eventos no mapa.
///
/// Pode conter:
/// - 1 evento: renderiza marker individual
/// - N eventos: renderiza cluster com badge
class MarkerCluster {
  final List<EventModel> events;
  final LatLng center;
  final String id;
  final bool isCluster;

  MarkerCluster({
    required this.events,
    required this.center,
    required this.id,
    required this.isCluster,
  });

  bool get isSingleEvent => events.length == 1;
  EventModel get firstEvent => events.first;
  int get count => events.length;
  String get representativeEmoji => events.first.emoji;
  String get clusterId => id; // back-compat
}

/// Serviço responsável por agrupar markers em clusters usando Fluster.
///
/// Usa o algoritmo Supercluster (via Fluster) que é:
/// - Performático: O(n log n) para criação, O(log n) para queries
/// - Determinístico: mesmo zoom = mesmos clusters
/// - Configurável: radius, extent, nodeSize
///
/// **Importante**: Não recrie o Fluster a cada movimento do mapa.
/// Recrie apenas quando o dataset mudar (novos eventos do backend).
class MarkerClusterService {
  final Map<int, List<MarkerCluster>> _clusterCache = {};
  final Map<String, List<MarkerCluster>> _boundsCache = {};
  Fluster<EventMapMarker>? _fluster;
  int? _eventsHash;

  static const int _minZoom = 0;
  static const int _maxZoom = 20;
  static const int _radiusPx = 140; // ajuste fino: 120-180 geralmente
  static const int _extent = 2048;  // maior = mais precisão
  static const int _nodeSize = 64;

  // Se dois eventos têm a MESMA coordenada, o Fluster vai manter um cluster mesmo
  // em zoom máximo. Para permitir "desmontar" em markers individuais, aplicamos
  // um deslocamento mínimo (jitter) determinístico APENAS em pontos duplicados.
  //
  // 0.00005 deg ~ 5m (latitude). Aumentado para garantir separação visual.
  static const double _jitterBaseDeg = 0.00005;

  // A partir deste zoom, forçamos a separação de clusters pequenos em markers individuais.
  // Isso garante que o usuário sempre consiga acessar eventos sobrepostos.
  static const int _forceExpandZoom = 14;
  static const int _maxClusterSizeToExpand = 5;

  /// Calcula jitter determinístico para separar markers sobrepostos.
  /// Retorna: 0, +j, -j, +2j, -2j, ...
  static double jitterForIndex(int index) {
    if (index == 0) return 0.0;
    final k = (index + 1) ~/ 2;
    final sign = index.isOdd ? 1.0 : -1.0;
    return sign * k * _jitterBaseDeg;
  }

  /// Constrói o Fluster com um novo dataset de eventos.
  ///
  /// Chame este método apenas quando:
  /// - Novos eventos forem carregados do backend
  /// - Filtros mudarem a lista de eventos
  ///
  /// **NÃO** chame a cada movimento do mapa!
  void buildFluster(List<EventModel> events) {
    if (events.isEmpty) {
      _fluster = null;
      _eventsHash = null;
      _clusterCache.clear();
      return;
    }

    final ids = events.map((e) => e.id).toList()..sort();
    final newHash = Object.hashAll(ids);

    // Já está construído com o mesmo dataset
    if (_fluster != null && _eventsHash == newHash) return;

    _eventsHash = newHash;
    _clusterCache.clear();

    // Detectar coordenadas duplicadas (lat/lng). Só nesses casos aplicamos jitter.
    final Map<String, int> duplicateIndexByKey = {};

    String coordKey(double lat, double lng) {
      return '${lat.toStringAsFixed(7)}|${lng.toStringAsFixed(7)}';
    }

    final points = <EventMapMarker>[];
    for (final e in events) {
      final key = coordKey(e.lat, e.lng);
      final dupIndex = duplicateIndexByKey.update(key, (v) => v + 1, ifAbsent: () => 0);

      final jitter = jitterForIndex(dupIndex);
      points.add(
        EventMapMarker(
          event: e,
          markerId: e.id,
          latitude: e.lat + jitter,
          longitude: e.lng - jitter,
        ),
      );
    }

    final placeholderEvent = events.first;
    _fluster = Fluster<EventMapMarker>(
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      radius: _radiusPx,
      extent: _extent,
      nodeSize: _nodeSize,
      points: points,
      createCluster: (BaseCluster? cluster, double? lng, double? lat) {
        return EventMapMarker(
          event: placeholderEvent,
          isCluster: true,
          clusterId: cluster?.id,
          pointsSize: cluster?.pointsSize,
          latitude: lat,
          longitude: lng,
          childMarkerId: cluster?.childMarkerId,
          markerId: 'cluster_${cluster?.id ?? 0}',
        );
      },
    );

    debugPrint('🔄 [ClusterService] Fluster construído: ${events.length} eventos');
  }

  /// Cria ou reutiliza instância do Fluster (uso interno).
  Fluster<EventMapMarker> _getFluster(List<EventModel> events) {
    buildFluster(events);
    return _fluster!;
  }

  /// Agrupa eventos em clusters baseado no zoom atual.
  ///
  /// Retorna lista de [MarkerCluster] que podem ser:
  /// - Cluster com múltiplos eventos (isCluster = true)
  /// - Marker individual (isCluster = false)
  List<MarkerCluster> clusterEvents({
    required List<EventModel> events,
    required double zoom,
    bool useCache = true,
  }) {
    if (events.isEmpty) return const [];
    final zoomInt = zoom.floor().clamp(_minZoom, _maxZoom);

    final ids = events.map((e) => e.id).toList()..sort();
    final hashNow = Object.hashAll(ids);
    if (useCache && _clusterCache.containsKey(zoomInt) && _eventsHash == hashNow) {
      return _clusterCache[zoomInt]!;
    }

    final sw = Stopwatch()..start();
    final fluster = _getFluster(events);
    final items = fluster.clusters([-180, -85, 180, 85], zoomInt);

    final out = <MarkerCluster>[];
    for (final item in items) {
      final lat = item.latitude;
      final lng = item.longitude;
      if (lat == null || lng == null) continue;

      if ((item.isCluster ?? false) && item.clusterId != null) {
        final childEvents = _collectChildEvents(fluster, item.clusterId!);
        final safeEvents = childEvents.isEmpty ? <EventModel>[events.first] : childEvents;

        // ✅ Em zoom alto, forçar separação de clusters pequenos em markers individuais.
        final shouldExpandCluster = zoomInt >= _forceExpandZoom && 
            safeEvents.length <= _maxClusterSizeToExpand;

        if (shouldExpandCluster) {
          for (int i = 0; i < safeEvents.length; i++) {
            final e = safeEvents[i];
            final jitterLat = jitterForIndex(i);
            final jitterLng = -jitterForIndex(i);
            out.add(
              MarkerCluster(
                events: [e],
                center: LatLng(e.lat + jitterLat, e.lng + jitterLng),
                id: 'marker_${e.id}',
                isCluster: false,
              ),
            );
          }
        } else {
          out.add(
            MarkerCluster(
              events: safeEvents,
              center: LatLng(lat, lng),
              id: 'cluster_${item.clusterId}',
              isCluster: safeEvents.length > 1,
            ),
          );
        }
      } else {
        final e = (item as EventMapMarker).event;
        out.add(
          MarkerCluster(
            events: [e],
            center: LatLng(e.lat, e.lng),
            id: 'marker_${e.id}',
            isCluster: false,
          ),
        );
      }
    }

    _clusterCache[zoomInt] = out;

    sw.stop();
    debugPrint(
      '✅ [ClusterService] ${events.length} eventos → ${out.length} clusters (zoom: $zoomInt, radius: ${_radiusPx}px) - ${sw.elapsedMilliseconds}ms',
    );

    return out;
  }

  /// Coleta recursivamente todos os eventos filhos de um cluster.
  List<EventModel> _collectChildEvents(Fluster<EventMapMarker> fluster, int clusterId) {
    final out = <EventModel>[];
    final children = fluster.children(clusterId);
    if (children == null) return out;

    for (final child in children) {
      if ((child.isCluster ?? false) && child.clusterId != null) {
        out.addAll(_collectChildEvents(fluster, child.clusterId!));
      } else {
        out.add((child as EventMapMarker).event);
      }
    }

    return out;
  }

  /// Retorna clusters/markers visíveis dentro dos bounds da câmera.
  ///
  /// Este é o método otimizado para usar no `onCameraMove`:
  /// - Só processa a área visível (não o mundo todo)
  /// - Usa cache por zoom
  ///
  /// Exemplo de uso no ViewModel:
  /// ```dart
  /// void onCameraMove(CameraPosition position, LatLngBounds bounds) {
  ///   final clusters = _clusterService.clustersForView(
  ///     bounds: bounds,
  ///     zoom: position.zoom,
  ///   );
  ///   // Converte para Markers do Google Maps...
  /// }
  /// ```
  List<MarkerCluster> clustersForView({
    required LatLngBounds bounds,
    required double zoom,
  }) {
    if (_fluster == null) return const [];

    final zoomInt = zoom.floor().clamp(_minZoom, _maxZoom);

    // Cache key inclui bounds arredondados + zoom
    final boundsKey = '${bounds.southwest.latitude.toStringAsFixed(3)}_'
        '${bounds.southwest.longitude.toStringAsFixed(3)}_'
        '${bounds.northeast.latitude.toStringAsFixed(3)}_'
        '${bounds.northeast.longitude.toStringAsFixed(3)}';
    final cacheKey = '${zoomInt}_$boundsKey';

    // Verifica cache de bounds (separado do cache por zoom)
    if (_boundsCache.containsKey(cacheKey)) {
      return _boundsCache[cacheKey]!;
    }

    final sw = Stopwatch()..start();

    // Query Fluster apenas na área visível
    final items = _fluster!.clusters(
      [
        bounds.southwest.longitude,
        bounds.southwest.latitude,
        bounds.northeast.longitude,
        bounds.northeast.latitude,
      ],
      zoomInt,
    );

    final out = <MarkerCluster>[];
    for (final item in items) {
      final lat = item.latitude;
      final lng = item.longitude;
      if (lat == null || lng == null) continue;

      if ((item.isCluster ?? false) && item.clusterId != null) {
        final childEvents = _collectChildEvents(_fluster!, item.clusterId!);
        if (childEvents.isEmpty) continue;

        // ✅ Em zoom alto, forçar separação de clusters pequenos em markers individuais.
        // Isso garante que o usuário sempre consiga acessar eventos sobrepostos.
        final shouldExpandCluster = zoomInt >= _forceExpandZoom && 
            childEvents.length <= _maxClusterSizeToExpand;

        if (shouldExpandCluster) {
          // Expandir: cada evento vira um marker individual
          for (int i = 0; i < childEvents.length; i++) {
            final e = childEvents[i];
            // Aplicar jitter visual para separar markers sobrepostos
            final jitterLat = jitterForIndex(i);
            final jitterLng = -jitterForIndex(i); // Diagonal para melhor separação
            out.add(
              MarkerCluster(
                events: [e],
                center: LatLng(e.lat + jitterLat, e.lng + jitterLng),
                id: 'marker_${e.id}',
                isCluster: false,
              ),
            );
          }
        } else {
          out.add(
            MarkerCluster(
              events: childEvents,
              center: LatLng(lat, lng),
              id: 'cluster_${item.clusterId}',
              isCluster: childEvents.length > 1,
            ),
          );
        }
      } else {
        final e = (item as EventMapMarker).event;
        out.add(
          MarkerCluster(
            events: [e],
            center: LatLng(e.lat, e.lng),
            id: 'marker_${e.id}',
            isCluster: false,
          ),
        );
      }
    }

    // Cache com limite de tamanho
    if (_boundsCache.length > 20) {
      _boundsCache.remove(_boundsCache.keys.first);
    }
    _boundsCache[cacheKey] = out;

    sw.stop();
    debugPrint(
      '📍 [ClusterService] View: ${out.length} clusters (zoom: $zoomInt, bounds query) - ${sw.elapsedMilliseconds}ms',
    );

    return out;
  }

  /// Limpa todo o cache de clusters.
  void clearCache() {
    _clusterCache.clear();
    _boundsCache.clear();
    _fluster = null;
    _eventsHash = null;
  }

  /// Remove cache de um zoom específico.
  void clearCacheForZoom(double zoom) {
    _clusterCache.remove(zoom.floor());
    // Limpa bounds cache também
    _boundsCache.removeWhere((key, _) => key.startsWith('${zoom.floor()}_'));
  }
}
