import 'dart:async';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/services/avatar_service.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_bitmap_generator.dart';

class MapMarkerAssets {
  // Cache de ícones de cluster (estilo antigo) por contagem.
  final Map<int, BitmapDescriptor> _clusterPinCache = {};
  
  // Cache de ícones de cluster com emoji
  final Map<String, BitmapDescriptor> _clusterPinWithEmojiCache = {};
  
  // Cache de ícones de avatar
  final Map<String, BitmapDescriptor> _avatarPinCache = {};
  
  final AvatarService _avatarService = AvatarService();
  
  bool isAvatarWarmupRunning = false;
  static const int _avatarPinSizePx = 120;

  void clearCache() {
    _clusterPinCache.clear();
    _clusterPinWithEmojiCache.clear();
    _avatarPinCache.clear();
  }

  Future<BitmapDescriptor> getClusterPinForCount(int count) async {
    final cached = _clusterPinCache[count];
    if (cached != null) return cached;

    // Estilo antigo: emoji + badge com contagem.
    const String fallbackEmoji = '🎉';
    final pin = await MarkerBitmapGenerator.generateClusterPinForGoogleMaps(
      fallbackEmoji,
      count,
      size: 230,
    );
    _clusterPinCache[count] = pin;
    return pin;
  }

  Future<BitmapDescriptor> getClusterPinWithEmoji(int count, String emoji) async {
    final key = '$count|$emoji';
    if (_clusterPinWithEmojiCache.containsKey(key)) {
      return _clusterPinWithEmojiCache[key]!;
    }
    final pin = await MarkerBitmapGenerator.generateClusterPinForGoogleMaps(
      emoji,
      count,
    );
    _clusterPinWithEmojiCache[key] = pin;
    return pin;
  }

  Future<BitmapDescriptor> getAvatarPinBestEffort(EventModel event) async {
    final userId = event.createdBy;
    final cached = _avatarPinCache[userId];
    if (cached != null) return cached;

    try {
      // 🚀 N+1 Optimization: Use denormalized URL from event doc if available
      String avatarUrl = event.creatorAvatarUrl ?? '';
      
      // Fallback: fetch from User collection (legacy / missing data)
      if (avatarUrl.isEmpty) {
         avatarUrl = await _avatarService.getAvatarUrl(userId);
      }

      final pin = await MarkerBitmapGenerator.generateAvatarPinForGoogleMaps(
        avatarUrl,
        size: _avatarPinSizePx,
      );
      _avatarPinCache[userId] = pin;
      return pin;
    } catch (_) {
      return BitmapDescriptor.defaultMarker;
    }
  }

  Future<void> warmupAvatarsForEvents(List<EventModel> events) async {
    if (isAvatarWarmupRunning) return;
    isAvatarWarmupRunning = true;
    try {
      // Best-effort warmup em paralelo, mas sem explodir trabalho.
      final uniqueCreators = <String>{};
      final limited = <EventModel>[];
      for (final e in events) {
        if (uniqueCreators.add(e.createdBy)) {
          limited.add(e);
        }
        if (limited.length >= 40) break;
      }

      await Future.wait(limited.map(getAvatarPinBestEffort));
    } finally {
      isAvatarWarmupRunning = false;
    }
  }

  String pickClusterEmoji(LatLng position, Map<String, EventModel> eventById) {
    if (eventById.isEmpty) return '🎉';

    EventModel? nearest;
    var bestDistance = double.infinity;

    for (final event in eventById.values) {
      final dLat = event.lat - position.latitude;
      final dLng = event.lng - position.longitude;
      final distance = (dLat * dLat) + (dLng * dLng);
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = event;
      }
    }

    return nearest?.emoji ?? '🎉';
  }
}
