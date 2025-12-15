import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/services/avatar_service.dart';
import 'package:partiu/features/home/presentation/services/marker_cluster_service.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_bitmap_generator.dart';

/// Serviço responsável por gerar e gerenciar markers de eventos no Google Maps
/// 
/// Responsabilidades:
/// - Gerar pins de emoji
/// - Gerar pins de avatar
/// - Gerar pins de cluster (com badge de contagem)
/// - Criar markers para o mapa
/// - Gerenciar cache de bitmaps
/// - Clusterizar eventos baseado no zoom
class GoogleEventMarkerService {
  final AvatarService _avatarService;
  final MarkerClusterService _clusterService;

  /// Cache de bitmaps de emojis
  final Map<String, BitmapDescriptor> _emojiCache = {};

  /// Cache de bitmaps de avatares
  final Map<String, BitmapDescriptor> _avatarCache = {};

  /// Bitmap padrão para avatares
  BitmapDescriptor? _defaultAvatarPin;

  GoogleEventMarkerService({
    AvatarService? avatarService,
    MarkerClusterService? clusterService,
  }) : _avatarService = avatarService ?? AvatarService(),
       _clusterService = clusterService ?? MarkerClusterService();

  /// Pré-carrega bitmaps padrão
  /// 
  /// Deve ser chamado antes de gerar markers
  Future<void> preloadDefaultPins() async {
    if (_defaultAvatarPin != null) return; // já carregado

    try {
      _defaultAvatarPin = await MarkerBitmapGenerator.generateAvatarPinForGoogleMaps(
        AvatarService.defaultAvatarUrl,
      );
    } catch (e) {
      // Fallback será tratado no momento de usar
    }
  }

  /// Gera ou retorna bitmap de emoji do cache
  Future<BitmapDescriptor> _getEmojiPin(String emoji, String eventId) async {
    final cacheKey = '$emoji-$eventId';
    if (_emojiCache.containsKey(cacheKey)) {
      return _emojiCache[cacheKey]!;
    }

    final bitmap = await MarkerBitmapGenerator.generateEmojiPinForGoogleMaps(
      emoji,
      eventId: eventId,
    );
    _emojiCache[cacheKey] = bitmap;
    return bitmap;
  }

  /// Gera ou retorna bitmap de avatar do cache
  Future<BitmapDescriptor> _getAvatarPin(String userId) async {
    if (_avatarCache.containsKey(userId)) {
      return _avatarCache[userId]!;
    }

    // Buscar URL do avatar
    final avatarUrl = await _avatarService.getAvatarUrl(userId);

    // Gerar bitmap
    final bitmap = await MarkerBitmapGenerator.generateAvatarPinForGoogleMaps(avatarUrl);
    _avatarCache[userId] = bitmap;
    return bitmap;
  }

  /// Constrói todos os markers para uma lista de eventos
  /// 
  /// Cada evento gera 2 markers com z-index único:
  /// 1. Emoji pin (grande, embaixo - z-index base)
  /// 2. Avatar pin (pequeno, acima - z-index base + 1)
  /// 
  /// Parâmetros:
  /// - [events]: Lista de eventos já enriquecidos com distância e disponibilidade
  /// - [onTap]: Callback quando marker é tocado (recebe eventId)
  /// 
  /// Retorna:
  /// - Set de Markers prontos para o mapa
  Future<Set<Marker>> buildEventMarkers(
    List<EventModel> events, {
    Function(String eventId)? onTap,
  }) async {
    final Set<Marker> markers = {};

    // Contador para z-index único por evento
    int eventIndex = 0;

    for (final event in events) {
      try {
        // Z-index único para este evento
        final baseZIndex = eventIndex * 2;
        eventIndex++;
        
        // 1. Emoji pin PRIMEIRO (renderiza embaixo)
        final emojiPin = await _getEmojiPin(event.emoji, event.id);

        markers.add(
          Marker(
            markerId: MarkerId('event_emoji_${event.id}'),
            position: LatLng(event.lat, event.lng),
            icon: emojiPin,
            anchor: const Offset(0.5, 1.0), // Ancorado no fundo
            zIndex: baseZIndex.toDouble(),
            onTap: onTap != null ? () {
              debugPrint('🟢 [MarkerService] Emoji marker tapped: ${event.id}');
              debugPrint('🟢 [MarkerService] Callback exists: ${onTap != null}');
              onTap(event.id);
              debugPrint('🟢 [MarkerService] Callback executed');
            } : null,
          ),
        );

        // 2. Avatar pin DEPOIS (renderiza em cima do seu emoji, mas abaixo do próximo evento)
        final avatarPin = await _getAvatarPin(event.createdBy);

        markers.add(
          Marker(
            markerId: MarkerId('event_avatar_${event.id}'),
            position: LatLng(event.lat, event.lng),
            icon: avatarPin,
            anchor: const Offset(0.5, 0.80), // 8px abaixo do centro (0.08 = 8/100) para subir visualmente
            zIndex: (baseZIndex + 1).toDouble(),
            onTap: onTap != null ? () {
              debugPrint('🔵 [MarkerService] Avatar marker tapped: ${event.id}');
              debugPrint('🔵 [MarkerService] Callback exists: ${onTap != null}');
              onTap(event.id);
              debugPrint('🔵 [MarkerService] Callback executed');
            } : null,
          ),
        );
      } catch (e) {
        // Se falhar para um evento, continuar com os próximos
        continue;
      }
    }

    return markers;
  }

  /// Constrói markers com clustering baseado no zoom atual
  /// 
  /// Parâmetros:
  /// - [events]: Lista de eventos já enriquecidos
  /// - [zoom]: Nível de zoom atual do mapa
  /// - [onSingleTap]: Callback quando marker individual é tocado (recebe eventId)
  /// - [onClusterTap]: Callback quando cluster é tocado (recebe lista de eventIds)
  /// 
  /// Comportamento:
  /// - Zoom alto (>= 16): Praticamente sem clustering, markers individuais
  /// - Zoom médio (12-15): Clustering moderado
  /// - Zoom baixo (< 12): Clustering agressivo
  /// - Eventos sobrepostos são separados em zoom alto (>= 15)
  /// 
  /// Retorna:
  /// - Set de Markers (individuais ou clusters) prontos para o mapa
  Future<Set<Marker>> buildClusteredMarkers(
    List<EventModel> events, {
    required double zoom,
    Function(String eventId)? onSingleTap,
    Function(List<EventModel> events)? onClusterTap,
  }) async {
    final stopwatch = Stopwatch()..start();
    final Set<Marker> markers = {};

    // Clusterizar eventos
    final clusters = _clusterService.clusterEvents(
      events: events,
      zoom: zoom,
    );

    debugPrint('🔲 [MarkerService] Gerando markers para ${clusters.length} clusters (zoom: ${zoom.toStringAsFixed(1)})');

    // Contador para z-index único por evento
    // Cada evento usa 2 níveis: um para emoji (par) e um para avatar (ímpar)
    // Isso garante que emoji+avatar de um evento fiquem juntos
    // e não interfiram com outros eventos
    int eventIndex = 0;

    for (final cluster in clusters) {
      try {
        if (cluster.isSingleEvent) {
          // Marker individual: emoji + avatar
          final event = cluster.firstEvent;
          
          // Obter posição (com offset se houver sobreposição)
          final position = _clusterService.getPositionForEvent(event, events, zoom);
          
          // Z-index único para este evento
          // Emoji usa índice base, avatar usa índice base + 1
          // Próximo evento começa no índice base + 2
          final baseZIndex = eventIndex * 2;
          eventIndex++;
          
          // 1. Emoji pin (camada de baixo do par)
          final emojiPin = await _getEmojiPin(event.emoji, event.id);
          markers.add(
            Marker(
              markerId: MarkerId('event_emoji_${event.id}'),
              position: position,
              icon: emojiPin,
              anchor: const Offset(0.5, 1.0),
              zIndex: baseZIndex.toDouble(),
              onTap: onSingleTap != null
                  ? () {
                      debugPrint('🟢 [MarkerService] Single marker tapped: ${event.id}');
                      onSingleTap(event.id);
                    }
                  : null,
            ),
          );

          // 2. Avatar pin (camada de cima do par, mas abaixo do próximo evento)
          final avatarPin = await _getAvatarPin(event.createdBy);
          markers.add(
            Marker(
              markerId: MarkerId('event_avatar_${event.id}'),
              position: position,
              icon: avatarPin,
              anchor: const Offset(0.5, 0.80),
              zIndex: (baseZIndex + 1).toDouble(),
              onTap: onSingleTap != null
                  ? () {
                      debugPrint('🔵 [MarkerService] Single avatar tapped: ${event.id}');
                      onSingleTap(event.id);
                    }
                  : null,
            ),
          );
        } else {
          // Marker de cluster: emoji + badge
          // Clusters usam z-index alto para ficar sempre visíveis
          final clusterZIndex = 10000 + eventIndex;
          eventIndex++;
          
          final clusterPin = await MarkerBitmapGenerator.generateClusterPinForGoogleMaps(
            cluster.representativeEmoji,
            cluster.count,
          );

          markers.add(
            Marker(
              markerId: MarkerId('cluster_${cluster.gridKey}'),
              position: cluster.center,
              icon: clusterPin,
              anchor: const Offset(0.5, 0.5),
              zIndex: clusterZIndex.toDouble(),
              onTap: onClusterTap != null
                  ? () {
                      debugPrint('🔴 [MarkerService] Cluster tapped: ${cluster.count} eventos');
                      onClusterTap(cluster.events);
                    }
                  : null,
            ),
          );
        }
      } catch (e) {
        debugPrint('⚠️ [MarkerService] Erro ao gerar marker: $e');
        continue;
      }
    }

    stopwatch.stop();
    debugPrint('✅ [MarkerService] ${markers.length} markers gerados em ${stopwatch.elapsedMilliseconds}ms');

    return markers;
  }

  /// Limpa todos os caches de bitmaps
  void clearCache() {
    _emojiCache.clear();
    _avatarCache.clear();
    _clusterService.clearCache();
    _defaultAvatarPin = null;
    MarkerBitmapGenerator.clearClusterCache();
  }

  /// Limpa cache de clusters para recalcular
  void clearClusterCache() {
    _clusterService.clearCache();
  }

  /// Remove um emoji específico do cache
  void removeCachedEmoji(String emoji) {
    _emojiCache.remove(emoji);
  }

  /// Remove um avatar específico do cache
  void removeCachedAvatar(String userId) {
    _avatarCache.remove(userId);
  }
}
