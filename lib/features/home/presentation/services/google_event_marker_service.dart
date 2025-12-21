import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/services/avatar_service.dart';
import 'package:partiu/features/home/presentation/services/marker_cluster_service.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_bitmap_generator.dart';

/// Serviço responsável por gerar e gerenciar markers de eventos no Google Maps
/// 
/// SINGLETON: Compartilha cache de bitmaps entre todas as instâncias
/// Isso permite que os bitmaps pré-carregados no AppInitializerService
/// sejam reutilizados pelo GoogleMapView
/// 
/// Responsabilidades:
/// - Gerar pins de emoji
/// - Gerar pins de avatar
/// - Gerar pins de cluster (com badge de contagem)
/// - Criar markers para o mapa
/// - Gerenciar cache de bitmaps (compartilhado via singleton)
/// - Clusterizar eventos baseado no zoom
class GoogleEventMarkerService {
  /// Instância singleton
  static final GoogleEventMarkerService _instance = GoogleEventMarkerService._internal();
  
  /// Factory constructor que retorna a instância singleton
  factory GoogleEventMarkerService() => _instance;
  
  /// Constructor interno
  GoogleEventMarkerService._internal()
      : _avatarService = AvatarService(),
        _clusterService = MarkerClusterService();
  
  final AvatarService _avatarService;
  final MarkerClusterService _clusterService;

  /// Cache de bitmaps de emojis (compartilhado)
  final Map<String, BitmapDescriptor> _emojiCache = {};

  /// Cache de bitmaps de avatares (compartilhado)
  final Map<String, BitmapDescriptor> _avatarCache = {};

  /// Bitmap padrão para avatares
  BitmapDescriptor? _defaultAvatarPin;

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

  /// Pré-carrega bitmaps de emojis e avatares para uma lista de eventos
  /// 
  /// Este método deve ser chamado durante a inicialização do app
  /// para popular o cache de bitmaps. Assim quando os markers forem
  /// gerados com callbacks, os bitmaps já estarão prontos.
  /// 
  /// Retorna o número de bitmaps pré-carregados
  Future<int> preloadBitmapsForEvents(List<EventModel> events) async {
    if (events.isEmpty) return 0;
    
    final stopwatch = Stopwatch()..start();
    int loaded = 0;
    
    // Pré-carregar em paralelo para máxima velocidade
    await Future.wait(events.map((event) async {
      try {
        // Pré-carregar emoji (se não estiver no cache)
        final emojiKey = '${event.emoji}-${event.id}';
        if (!_emojiCache.containsKey(emojiKey)) {
          final bitmap = await MarkerBitmapGenerator.generateEmojiPinForGoogleMaps(
            event.emoji,
            eventId: event.id,
          );
          _emojiCache[emojiKey] = bitmap;
          loaded++;
        }
        
        // Pré-carregar avatar (se não estiver no cache)
        if (!_avatarCache.containsKey(event.createdBy)) {
          final avatarUrl = await _avatarService.getAvatarUrl(event.createdBy);
          final bitmap = await MarkerBitmapGenerator.generateAvatarPinForGoogleMaps(avatarUrl);
          _avatarCache[event.createdBy] = bitmap;
          loaded++;
        }
      } catch (e) {
        // Ignorar erros individuais, continuar com os próximos
        debugPrint('⚠️ [MarkerService] Erro ao pré-carregar bitmap: $e');
      }
    }));
    
    stopwatch.stop();
    debugPrint('⚡ [MarkerService] $loaded bitmaps pré-carregados em ${stopwatch.elapsedMilliseconds}ms');
    
    return loaded;
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
    final stopwatch = Stopwatch()..start();
    final Set<Marker> markers = {};
    
    if (events.isEmpty) return markers;
    
    // ⚡ OTIMIZAÇÃO: Pré-carregar todos os bitmaps em PARALELO primeiro
    // Isso é muito mais rápido que carregar sequencialmente
    await Future.wait(events.map((event) async {
      await _getEmojiPin(event.emoji, event.id);
      await _getAvatarPin(event.createdBy);
    }));
    
    debugPrint('⚡ [MarkerService] Bitmaps pré-carregados em ${stopwatch.elapsedMilliseconds}ms');

    // Contador para z-index único por evento
    // Usando valores NEGATIVOS para ficar ABAIXO do pin do usuário do Google
    // O pin azul do usuário tem z-index ~0, então usamos negativos
    int eventIndex = 0;

    for (final event in events) {
      try {
        // Z-index negativo para ficar ABAIXO do pin do usuário
        // Emoji usa índice base negativo, avatar usa base - 1
        final baseZIndex = -1000 + (eventIndex * 2);
        eventIndex++;
        
        // 1. Emoji pin PRIMEIRO (renderiza embaixo) - já está em cache
        final emojiPin = await _getEmojiPin(event.emoji, event.id);

        markers.add(
          Marker(
            markerId: MarkerId('event_emoji_${event.id}'),
            position: LatLng(event.lat, event.lng),
            icon: emojiPin,
            anchor: const Offset(0.5, 1.0), // Ancorado no fundo
            zIndex: baseZIndex.toDouble(), // Negativo - abaixo do pin do usuário
            onTap: onTap != null ? () {
              debugPrint('🟢 [MarkerService] Emoji marker tapped: ${event.id}');
              debugPrint('🟢 [MarkerService] Callback exists: ${onTap != null}');
              onTap(event.id);
              debugPrint('🟢 [MarkerService] Callback executed');
            } : null,
          ),
        );

        // 2. Avatar pin DEPOIS (renderiza em cima do seu emoji, mas abaixo do pin do usuário)
        final avatarPin = await _getAvatarPin(event.createdBy);

        markers.add(
          Marker(
            markerId: MarkerId('event_avatar_${event.id}'),
            position: LatLng(event.lat, event.lng),
            icon: avatarPin,
            anchor: const Offset(0.5, 0.80), // 8px abaixo do centro (0.08 = 8/100) para subir visualmente
            zIndex: (baseZIndex + 1).toDouble(), // Negativo - abaixo do pin do usuário
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
    
    stopwatch.stop();
    debugPrint('✅ [MarkerService] ${markers.length} markers gerados em ${stopwatch.elapsedMilliseconds}ms');

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
    
    if (events.isEmpty) return markers;

    // Clusterizar eventos
    final clusters = _clusterService.clusterEvents(
      events: events,
      zoom: zoom,
    );

    debugPrint('🔲 [MarkerService] Gerando markers para ${clusters.length} clusters (zoom: ${zoom.toStringAsFixed(1)})');
    
    // ⚡ OTIMIZAÇÃO: Pré-carregar todos os bitmaps em PARALELO primeiro
    // Isso usa o cache singleton - se já foi carregado no AppInitializer, será instantâneo
    final singleEvents = clusters.where((c) => c.isSingleEvent).map((c) => c.firstEvent).toList();
    if (singleEvents.isNotEmpty) {
      await Future.wait(singleEvents.map((event) async {
        await _getEmojiPin(event.emoji, event.id);
        await _getAvatarPin(event.createdBy);
      }));
    }
    
    debugPrint('⚡ [MarkerService] Bitmaps verificados/carregados em ${stopwatch.elapsedMilliseconds}ms');

    // Contador para z-index único por evento
    // Usando valores NEGATIVOS para ficar ABAIXO do pin do usuário do Google
    // O pin azul do usuário tem z-index ~0, então usamos negativos
    // Cada evento usa 2 níveis: um para emoji e um para avatar
    int eventIndex = 0;

    for (final cluster in clusters) {
      try {
        if (cluster.isSingleEvent) {
          // Marker individual: emoji + avatar
          final event = cluster.firstEvent;
          
          // Obter posição (com offset se houver sobreposição)
          final position = _clusterService.getPositionForEvent(event, events, zoom);
          
          // Z-index negativo para ficar ABAIXO do pin do usuário
          // Emoji usa índice base negativo, avatar usa base + 1
          final baseZIndex = -1000 + (eventIndex * 2);
          eventIndex++;
          
          // 1. Emoji pin (camada de baixo do par) - já está em cache
          final emojiPin = await _getEmojiPin(event.emoji, event.id);
          markers.add(
            Marker(
              markerId: MarkerId('event_emoji_${event.id}'),
              position: position,
              icon: emojiPin,
              anchor: const Offset(0.5, 1.0),
              zIndex: baseZIndex.toDouble(), // Negativo - abaixo do pin do usuário
              onTap: onSingleTap != null
                  ? () {
                      debugPrint('🟢 [MarkerService] Single marker tapped: ${event.id}');
                      onSingleTap(event.id);
                    }
                  : null,
            ),
          );

          // 2. Avatar pin (camada de cima do par, mas abaixo do pin do usuário) - já está em cache
          final avatarPin = await _getAvatarPin(event.createdBy);
          markers.add(
            Marker(
              markerId: MarkerId('event_avatar_${event.id}'),
              position: position,
              icon: avatarPin,
              anchor: const Offset(0.5, 0.80),
              zIndex: (baseZIndex + 1).toDouble(), // Negativo - abaixo do pin do usuário
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
          // Clusters usam z-index negativo mas mais alto que markers individuais
          // para ficar visíveis, porém ainda abaixo do pin do usuário
          final clusterZIndex = -500 + eventIndex;
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
              zIndex: clusterZIndex.toDouble(), // Negativo - abaixo do pin do usuário
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
