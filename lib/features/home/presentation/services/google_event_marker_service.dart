import 'dart:async';
import 'dart:collection';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:partiu/core/services/cache/cache_key_utils.dart';
import 'package:partiu/core/services/cache/image_cache_stats.dart';
import 'package:partiu/core/services/cache/image_caches.dart';
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
  // Tamanhos em pixels do bitmap (Google Maps usa pixels; escolhemos valores moderados)
  static const int _emojiPinSizePx = 230;
  static const int _clusterPinSizePx = 250;
  static const int _avatarPinSizePx = 120;

  /// Cache do DPR para garantir consistência entre chamadas.
  /// Uma vez calculado, não muda mais (evita cache miss por variação de DPR).
  static double? _cachedDevicePixelRatio;

  static double get _devicePixelRatio {
    if (_cachedDevicePixelRatio != null) return _cachedDevicePixelRatio!;
    
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view != null) {
      _cachedDevicePixelRatio = view.devicePixelRatio;
      return _cachedDevicePixelRatio!;
    }
    final views = WidgetsBinding.instance.platformDispatcher.views;
    _cachedDevicePixelRatio = views.isNotEmpty ? views.first.devicePixelRatio : 3.0;
    return _cachedDevicePixelRatio!;
  }

  static String get _dprKey => _devicePixelRatio.toStringAsFixed(2);

  static String _emojiCacheKey(String emoji, String eventId) {
    return '$emoji-$eventId-$_emojiPinSizePx@$_dprKey';
  }

  static String _avatarCacheKey(String userId) {
    return '$userId-$_avatarPinSizePx@$_dprKey';
  }

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

  /// Notifier para avisar quando novos bitmaps de avatar entram no cache.
  /// A UI pode debounciar e regenerar markers para trocar placeholder -> avatar real.
  final ValueNotifier<int> _avatarBitmapsVersion = ValueNotifier<int>(0);

  ValueListenable<int> get avatarBitmapsVersion => _avatarBitmapsVersion;

  static const int _maxAvatarPrefetchConcurrent = 8;
  final Queue<String> _avatarPrefetchQueue = Queue<String>();
  final Set<String> _avatarPrefetchScheduled = <String>{};
  int _avatarPrefetchActive = 0;

  /// Pré-carrega bitmaps padrão
  /// 
  /// Deve ser chamado antes de gerar markers
  Future<void> preloadDefaultPins() async {
    if (_defaultAvatarPin != null) return; // já carregado

    try {
      // AvatarService.defaultAvatarUrl é vazio por design (fallback local).
      // Gerar placeholder via canvas evita qualquer I/O e elimina o “pisca” do defaultMarker.
      _defaultAvatarPin = await MarkerBitmapGenerator.generateAvatarPinForGoogleMaps(
        '',
        size: _avatarPinSizePx,
      );
    } catch (e) {
      // Fallback será tratado no momento de usar
    }
  }

  void _scheduleAvatarPrefetch(String userId) {
    final avatarBitmapKey = _avatarCacheKey(userId);
    if (_avatarCache.containsKey(avatarBitmapKey)) return;
    if (_avatarPrefetchScheduled.contains(userId)) return;

    _avatarPrefetchScheduled.add(userId);
    _avatarPrefetchQueue.addLast(userId);
    _pumpAvatarPrefetchQueue();
  }

  void _pumpAvatarPrefetchQueue() {
    while (_avatarPrefetchActive < _maxAvatarPrefetchConcurrent && _avatarPrefetchQueue.isNotEmpty) {
      final userId = _avatarPrefetchQueue.removeFirst();
      _avatarPrefetchActive++;

      unawaited(() async {
        try {
          await _getAvatarPin(userId);
        } catch (_) {
          // Best-effort.
        } finally {
          _avatarPrefetchActive = (_avatarPrefetchActive - 1).clamp(0, 1 << 30);
          _avatarPrefetchScheduled.remove(userId);
          _pumpAvatarPrefetchQueue();
        }
      }());
    }
  }

  Future<BitmapDescriptor> _getAvatarPinBestEffort(String userId) async {
    final avatarBitmapKey = _avatarCacheKey(userId);
    final cached = _avatarCache[avatarBitmapKey];
    if (cached != null) return cached;

    // ✅ Evitar “pisca”: se já existe um avatar cacheado para esse userId
    // em outro DPR (ex.: aquecido no splash / primeiro frame), reutilize-o.
    // Isso mantém o avatar visível até o preload do DPR atual terminar.
    final anyCached = _findAnyCachedAvatarPinForUser(userId);
    if (anyCached != null) {
      // Ainda agenda o preload do DPR atual em background.
      _scheduleAvatarPrefetch(userId);
      return anyCached;
    }

    // Garantir que o placeholder é consistente (sem cair em BitmapDescriptor.defaultMarker).
    if (_defaultAvatarPin == null) {
      await preloadDefaultPins();
    }

    // Não bloquear o primeiro paint do mapa para baixar/decodificar o avatar real.
    _scheduleAvatarPrefetch(userId);

    return _defaultAvatarPin ?? BitmapDescriptor.defaultMarker;
  }

  BitmapDescriptor? _findAnyCachedAvatarPinForUser(String userId) {
    // Formato: '$userId-$_avatarPinSizePx@$_dprKey'
    final prefix = '$userId-$_avatarPinSizePx@';
    for (final entry in _avatarCache.entries) {
      if (entry.key.startsWith(prefix)) {
        return entry.value;
      }
    }
    return null;
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
        final emojiKey = _emojiCacheKey(event.emoji, event.id);
        if (!_emojiCache.containsKey(emojiKey)) {
          final bitmap = await MarkerBitmapGenerator.generateEmojiPinForGoogleMaps(
            event.emoji,
            eventId: event.id,
            size: _emojiPinSizePx,
          );
          _emojiCache[emojiKey] = bitmap;
          loaded++;
        }
        
        // Pré-carregar avatar (se não estiver no cache)
        final avatarKey = _avatarCacheKey(event.createdBy);
        if (!_avatarCache.containsKey(avatarKey)) {
          final avatarUrl = await _avatarService.getAvatarUrl(event.createdBy);
          final cacheKey = stableImageCacheKey(avatarUrl);
          ImageCacheStats.instance.record(
            category: ImageCacheCategory.avatar,
            url: avatarUrl,
            cacheKey: cacheKey,
          );
          final bitmap = await MarkerBitmapGenerator.generateAvatarPinForGoogleMaps(
            avatarUrl,
            size: _avatarPinSizePx,
            cacheManager: AvatarImageCache.instance,
            cacheKey: cacheKey,
          );
          _avatarCache[avatarKey] = bitmap;
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

  /// Pré-carrega SOMENTE bitmaps de AVATAR para os criadores dos eventos.
  ///
  /// Objetivo: aquecer rapidamente o viewport inicial do mapa para que os
  /// markers já nasçam com avatar (sem passar pelo empty state).
  ///
  /// - Deduplica por `createdBy`
  /// - Limita quantidade para evitar aquecer o “mapa inteiro”
  /// - Usa concorrência controlada
  Future<int> preloadAvatarPinsForEvents(
    List<EventModel> events, {
    int maxUsers = 30,
  }) async {
    if (events.isEmpty) return 0;

    if (_defaultAvatarPin == null) {
      await preloadDefaultPins();
    }

    final uniqueUserIds = <String>{};
    for (final event in events) {
      final userId = event.createdBy;
      if (userId.trim().isEmpty) continue;
      uniqueUserIds.add(userId);
      if (uniqueUserIds.length >= maxUsers) break;
    }

    final toLoad = uniqueUserIds
        .where((userId) => !_avatarCache.containsKey(_avatarCacheKey(userId)))
        .toList(growable: false);
    if (toLoad.isEmpty) return 0;

    int loaded = 0;
    final queue = Queue<String>.from(toLoad);
    final workers = <Future<void>>[];

    final concurrency = _maxAvatarPrefetchConcurrent;
    for (var i = 0; i < concurrency; i++) {
      workers.add(() async {
        while (queue.isNotEmpty) {
          final userId = queue.removeFirst();
          try {
            await _getAvatarPin(userId);
            loaded++;
          } catch (_) {
            // Best-effort.
          }
        }
      }());
    }

    await Future.wait(workers);
    return loaded;
  }

  /// Gera ou retorna bitmap de emoji do cache
  Future<BitmapDescriptor> _getEmojiPin(String emoji, String eventId) async {
    final cacheKey = _emojiCacheKey(emoji, eventId);
    if (_emojiCache.containsKey(cacheKey)) {
      return _emojiCache[cacheKey]!;
    }

    final bitmap = await MarkerBitmapGenerator.generateEmojiPinForGoogleMaps(
      emoji,
      eventId: eventId,
      size: _emojiPinSizePx,
    );
    _emojiCache[cacheKey] = bitmap;
    return bitmap;
  }

  /// Gera ou retorna bitmap de avatar do cache
  Future<BitmapDescriptor> _getAvatarPin(String userId) async {
    final avatarBitmapKey = _avatarCacheKey(userId);
    if (_avatarCache.containsKey(avatarBitmapKey)) {
      return _avatarCache[avatarBitmapKey]!;
    }

    // Buscar URL do avatar
    final avatarUrl = await _avatarService.getAvatarUrl(userId);

    final imageCacheKey = stableImageCacheKey(avatarUrl);
    ImageCacheStats.instance.record(
      category: ImageCacheCategory.avatar,
      url: avatarUrl,
      cacheKey: imageCacheKey,
    );

    // Gerar bitmap
    final bitmap = await MarkerBitmapGenerator.generateAvatarPinForGoogleMaps(
      avatarUrl,
      size: _avatarPinSizePx,
      cacheManager: AvatarImageCache.instance,
      cacheKey: imageCacheKey,
    );

    final existed = _avatarCache.containsKey(avatarBitmapKey);
    _avatarCache[avatarBitmapKey] = bitmap;
    if (!existed) {
      _avatarBitmapsVersion.value = _avatarBitmapsVersion.value + 1;
    }
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
    
    // Não bloquear a UI aguardando download/render de avatares.
    // O emoji pin é gerado na hora; avatar usa fallback e é pré-carregado em background.

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
            zIndexInt: baseZIndex, // Negativo - abaixo do pin do usuário
            onTap: onTap != null ? () {
              debugPrint('🟢 [MarkerService] Emoji marker tapped: ${event.id}');
              onTap(event.id);
              debugPrint('🟢 [MarkerService] Callback executed');
            } : null,
          ),
        );

        // 2. Avatar pin DEPOIS (renderiza em cima do seu emoji, mas abaixo do pin do usuário)
        final avatarPin = await _getAvatarPinBestEffort(event.createdBy);

        markers.add(
          Marker(
            markerId: MarkerId('event_avatar_${event.id}'),
            position: LatLng(event.lat, event.lng),
            icon: avatarPin,
            anchor: const Offset(0.5, 0.80), // 8px abaixo do centro (0.08 = 8/100) para subir visualmente
            zIndexInt: baseZIndex + 1, // Negativo - abaixo do pin do usuário
            onTap: onTap != null ? () {
              debugPrint('🔵 [MarkerService] Avatar marker tapped: ${event.id}');
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
    
    // Não bloquear aguardando avatar/emoji. O cache vai sendo preenchido conforme necessário.

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
              zIndexInt: baseZIndex, // Negativo - abaixo do pin do usuário
              onTap: onSingleTap != null
                  ? () {
                      debugPrint('🟢 [MarkerService] Single marker tapped: ${event.id}');
                      onSingleTap(event.id);
                    }
                  : null,
            ),
          );

          // 2. Avatar pin (camada de cima do par, mas abaixo do pin do usuário) - best-effort
          final avatarPin = await _getAvatarPinBestEffort(event.createdBy);
          markers.add(
            Marker(
              markerId: MarkerId('event_avatar_${event.id}'),
              position: position,
              icon: avatarPin,
              anchor: const Offset(0.5, 0.80),
              zIndexInt: baseZIndex + 1, // Negativo - abaixo do pin do usuário
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
            size: _clusterPinSizePx,
          );

          markers.add(
            Marker(
              markerId: MarkerId('cluster_${cluster.gridKey}'),
              position: cluster.center,
              icon: clusterPin,
              anchor: const Offset(0.5, 0.5),
              zIndexInt: clusterZIndex, // Negativo - abaixo do pin do usuário
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
  Future<void> removeCachedAvatar(String userId) async {
    _avatarCache.remove(_avatarCacheKey(userId));
    _avatarService.removeCachedAvatar(userId);

    try {
      final avatarUrl = await _avatarService.getAvatarUrl(userId, useCache: false);
      final cacheKey = stableImageCacheKey(avatarUrl);
      if (cacheKey.trim().isNotEmpty) {
        await AvatarImageCache.instance.removeFile(cacheKey);
      }
    } catch (_) {
      // Best-effort: se falhar, ao menos limpamos o cache em memória.
    }
  }
}
