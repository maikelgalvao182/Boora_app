import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/services/avatar_service.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_bitmap_generator.dart';

/// Serviço responsável por gerar e gerenciar markers de eventos no Google Maps
/// 
/// Responsabilidades:
/// - Gerar pins de emoji
/// - Gerar pins de avatar
/// - Criar markers para o mapa
/// - Gerenciar cache de bitmaps
class GoogleEventMarkerService {
  final AvatarService _avatarService;

  /// Cache de bitmaps de emojis
  final Map<String, BitmapDescriptor> _emojiCache = {};

  /// Cache de bitmaps de avatares
  final Map<String, BitmapDescriptor> _avatarCache = {};

  /// Bitmap padrão para avatares
  BitmapDescriptor? _defaultAvatarPin;

  GoogleEventMarkerService({AvatarService? avatarService})
      : _avatarService = avatarService ?? AvatarService();

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
  /// Cada evento gera 2 markers:
  /// 1. Emoji pin (grande, embaixo - z-index 0)
  /// 2. Avatar pin (pequeno, acima - z-index 1)
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

    for (final event in events) {
      try {
        // 1. Emoji pin PRIMEIRO (renderiza embaixo)
        final emojiPin = await _getEmojiPin(event.emoji, event.id);

        markers.add(
          Marker(
            markerId: MarkerId('event_emoji_${event.id}'),
            position: LatLng(event.lat, event.lng),
            icon: emojiPin,
            anchor: const Offset(0.5, 1.0), // Ancorado no fundo
            zIndex: 0, // Camada de baixo
            onTap: onTap != null ? () {
              debugPrint('🟢 [MarkerService] Emoji marker tapped: ${event.id}');
              debugPrint('🟢 [MarkerService] Callback exists: ${onTap != null}');
              onTap(event.id);
              debugPrint('🟢 [MarkerService] Callback executed');
            } : null,
          ),
        );

        // 2. Avatar pin DEPOIS (renderiza em cima)
        final avatarPin = await _getAvatarPin(event.createdBy);

        markers.add(
          Marker(
            markerId: MarkerId('event_avatar_${event.id}'),
            position: LatLng(event.lat, event.lng),
            icon: avatarPin,
            anchor: const Offset(0.5, 0.80), // 8px abaixo do centro (0.08 = 8/100) para subir visualmente
            zIndex: 1, // Camada de cima
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

  /// Limpa todos os caches de bitmaps
  void clearCache() {
    _emojiCache.clear();
    _avatarCache.clear();
    _defaultAvatarPin = null;
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
