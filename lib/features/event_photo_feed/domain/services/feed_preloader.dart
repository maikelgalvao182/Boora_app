import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_feed_scope.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/data/repositories/event_photo_repository.dart';
import 'package:partiu/features/event_photo_feed/domain/services/event_photo_cache_service.dart';
import 'package:partiu/features/feed/data/models/activity_feed_item_model.dart';
import 'package:partiu/features/feed/data/repositories/activity_feed_repository.dart';

/// Cache entry para uma aba específica do feed
class _FeedCacheEntry {
  _FeedCacheEntry({
    required this.photos,
    required this.activities,
    required this.fetchTime,
  });

  final List<EventPhotoModel> photos;
  final List<ActivityFeedItemModel> activities;
  final DateTime fetchTime;

  bool isValid(Duration ttl) {
    return DateTime.now().difference(fetchTime) < ttl;
  }
}

/// Serviço para pré-carregar o feed em background
/// 
/// Faz preload silencioso dos primeiros posts das 3 abas assim que o app 
/// entra na Home, evitando o delay de 3-4s ao abrir o Feed pela primeira vez.
/// 
/// Estratégia:
/// - Preload de 6 posts por aba (Global, Following, User)
/// - Cache em memória com TTL de 10 minutos
/// - Prefetch das thumbnails das imagens
/// - Cache-first na UI do Feed
class FeedPreloader {
  FeedPreloader._();
  
  static final FeedPreloader instance = FeedPreloader._();
  
  // Cache separado por scope
  final Map<String, _FeedCacheEntry> _cache = {};
  
  // TTL do cache em memória
  static const Duration _memoryTtl = Duration(minutes: 10);
  static const int _preloadLimit = 6;
  
  // Flag para evitar múltiplas requisições simultâneas
  bool _isLoading = false;
  
  /// Gera chave única para o scope
  String _scopeKey(EventPhotoFeedScope scope) {
    return switch (scope) {
      EventPhotoFeedScopeGlobal() => 'global',
      EventPhotoFeedScopeFollowing(:final userId) => 'following:$userId',
      EventPhotoFeedScopeUser(:final userId) => 'user:$userId',
      EventPhotoFeedScopeCity(:final cityId) => 'city:$cityId',
      EventPhotoFeedScopeEvent(:final eventId) => 'event:$eventId',
    };
  }
  
  /// Retorna os photos em cache para um scope (se válidos)
  List<EventPhotoModel>? getCachedPhotos(EventPhotoFeedScope scope) {
    final key = _scopeKey(scope);
    final entry = _cache[key];
    if (entry == null || !entry.isValid(_memoryTtl)) return null;
    return entry.photos;
  }
  
  /// Retorna os activities em cache para um scope (se válidos)
  List<ActivityFeedItemModel>? getCachedActivities(EventPhotoFeedScope scope) {
    final key = _scopeKey(scope);
    final entry = _cache[key];
    if (entry == null || !entry.isValid(_memoryTtl)) return null;
    return entry.activities;
  }
  
  /// Verifica se o cache está válido para um scope
  bool hasFreshCache(EventPhotoFeedScope scope) {
    final key = _scopeKey(scope);
    final entry = _cache[key];
    return entry != null && entry.isValid(_memoryTtl);
  }
  
  /// Verifica se tem cache fresco para qualquer scope
  bool get hasAnyFreshCache {
    return _cache.values.any((entry) => entry.isValid(_memoryTtl));
  }
  
  /// Pré-carrega a primeira página das 3 abas do feed em background
  /// 
  /// Chame isso no `addPostFrameCallback` da Home para não atrasar a entrada no mapa.
  /// Se já tiver cache fresco para todas as abas, não faz nada.
  Future<void> preloadAllTabs() async {
    final userId = _safeUserId();
    if (userId == null) {
      AppLogger.info(
        '⚠️ [FeedPreloader] Usuário não logado, pulando preload',
        tag: 'FEED_PRELOAD',
      );
      return;
    }
    
    // Verifica se já tem cache fresco para todas as abas principais
    final globalScope = const EventPhotoFeedScopeGlobal();
    final followingScope = EventPhotoFeedScopeFollowing(userId: userId);
    final userScope = EventPhotoFeedScopeUser(userId: userId);
    
    final hasGlobal = hasFreshCache(globalScope);
    final hasFollowing = hasFreshCache(followingScope);
    final hasUser = hasFreshCache(userScope);
    
    if (hasGlobal && hasFollowing && hasUser) {
      AppLogger.info(
        '📦 [FeedPreloader] Cache fresco para todas as abas, pulando preload',
        tag: 'FEED_PRELOAD',
      );
      return;
    }
    
    // Evita requisições simultâneas
    if (_isLoading) {
      AppLogger.info(
        '⏳ [FeedPreloader] Preload já em andamento',
        tag: 'FEED_PRELOAD',
      );
      return;
    }
    
    _isLoading = true;
    
    try {
      AppLogger.info(
        '🚀 [FeedPreloader] Iniciando preload das 3 abas...',
        tag: 'FEED_PRELOAD',
      );
      
      final stopwatch = Stopwatch()..start();
      
      final photoRepo = EventPhotoRepository(
        cacheService: EventPhotoCacheService(),
      );
      final activityRepo = ActivityFeedRepository();
      
      // Busca as 3 abas em paralelo
      final futures = <Future>[];
      
      // Global
      if (!hasGlobal) {
        futures.add(_fetchAndCache(
          photoRepo: photoRepo,
          activityRepo: activityRepo,
          scope: globalScope,
          userId: userId,
        ));
      }
      
      // Following
      if (!hasFollowing) {
        futures.add(_fetchAndCache(
          photoRepo: photoRepo,
          activityRepo: activityRepo,
          scope: followingScope,
          userId: userId,
        ));
      }
      
      // User (Meus Posts)
      if (!hasUser) {
        futures.add(_fetchAndCache(
          photoRepo: photoRepo,
          activityRepo: activityRepo,
          scope: userScope,
          userId: userId,
        ));
      }
      
      await Future.wait(futures);
      
      stopwatch.stop();
      
      AppLogger.info(
        '✅ [FeedPreloader] Preload das 3 abas concluído em ${stopwatch.elapsedMilliseconds}ms',
        tag: 'FEED_PRELOAD',
      );
      
    } catch (e) {
      AppLogger.error(
        '❌ [FeedPreloader] Erro no preload',
        tag: 'FEED_PRELOAD',
        error: e,
      );
    } finally {
      _isLoading = false;
    }
  }
  
  /// Busca e cacheia uma aba específica
  Future<void> _fetchAndCache({
    required EventPhotoRepository photoRepo,
    required ActivityFeedRepository activityRepo,
    required EventPhotoFeedScope scope,
    required String userId,
  }) async {
    try {
      // Busca EventPhotos
      final photoPage = await photoRepo.fetchFeedPageWithOwnPending(
        scope: scope,
        limit: _preloadLimit,
        currentUserId: userId,
      );
      
      // Busca ActivityFeed baseado no scope
      List<ActivityFeedItemModel> activities;
      if (scope is EventPhotoFeedScopeUser) {
        activities = await activityRepo.fetchUserFeed(
          userId: scope.userId,
          limit: _preloadLimit,
        );
      } else if (scope is EventPhotoFeedScopeFollowing) {
        // Busca IDs dos usuários seguidos
        final followingIds = await _fetchFollowingIds(userId);
        if (followingIds.isEmpty) {
          activities = [];
        } else {
          activities = await activityRepo.fetchFollowingFeed(
            userIds: followingIds,
            limit: _preloadLimit,
          );
        }
      } else {
        activities = await activityRepo.fetchGlobalFeed(limit: _preloadLimit);
      }
      
      // Salva no cache
      final key = _scopeKey(scope);
      _cache[key] = _FeedCacheEntry(
        photos: photoPage.items,
        activities: activities,
        fetchTime: DateTime.now(),
      );
      
      AppLogger.info(
        '📦 [FeedPreloader] Cache salvo para $key: ${photoPage.items.length} photos, ${activities.length} activities',
        tag: 'FEED_PRELOAD',
      );
    } catch (e) {
      AppLogger.error(
        '⚠️ [FeedPreloader] Erro ao cachear ${_scopeKey(scope)}',
        tag: 'FEED_PRELOAD',
        error: e,
      );
    }
  }
  
  String? _safeUserId() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.trim().isEmpty) return null;
      return uid;
    } catch (_) {
      return null;
    }
  }
  
  /// Busca IDs dos usuários seguidos pelo usuário
  Future<List<String>> _fetchFollowingIds(String userId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('following')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
      
      return snap.docs.map((doc) => doc.id).toList(growable: false);
    } catch (e) {
      AppLogger.error(
        '❌ [FeedPreloader._fetchFollowingIds] Erro',
        tag: 'FEED_PRELOAD',
        error: e,
      );
      return [];
    }
  }
  
  /// Pré-carrega as thumbnails das imagens em cache de todas as abas
  /// 
  /// Chame isso após o preload, passando o BuildContext.
  /// Usa `precacheImage` para fazer o download/decode das imagens em background.
  Future<void> prefetchThumbnails(BuildContext context) async {
    // Coleta todas as photos de todos os caches válidos
    final allPhotos = <EventPhotoModel>[];
    for (final entry in _cache.values) {
      if (entry.isValid(_memoryTtl)) {
        allPhotos.addAll(entry.photos);
      }
    }
    
    if (allPhotos.isEmpty) return;
    
    // Remove duplicatas por ID
    final uniquePhotos = <String, EventPhotoModel>{};
    for (final photo in allPhotos) {
      uniquePhotos[photo.id] = photo;
    }
    
    try {
      AppLogger.info(
        '🖼️ [FeedPreloader] Prefetching ${uniquePhotos.length} thumbnails...',
        tag: 'FEED_PRELOAD',
      );
      
      for (final photo in uniquePhotos.values) {
        // Prioriza thumbnailUrl, fallback para imageUrl
        String? url;
        if (photo.thumbnailUrls.isNotEmpty) {
          url = photo.thumbnailUrls.first;
        } else if (photo.thumbnailUrl != null && photo.thumbnailUrl!.isNotEmpty) {
          url = photo.thumbnailUrl;
        } else if (photo.imageUrls.isNotEmpty) {
          url = photo.imageUrls.first;
        }
        
        if (url != null && url.isNotEmpty) {
          try {
            await precacheImage(
              CachedNetworkImageProvider(url),
              context,
            );
          } catch (_) {
            // Ignora erros individuais de prefetch
          }
        }
      }
      
      AppLogger.info(
        '✅ [FeedPreloader] Prefetch de thumbnails concluído',
        tag: 'FEED_PRELOAD',
      );
    } catch (e) {
      AppLogger.error(
        '⚠️ [FeedPreloader] Erro no prefetch de thumbnails',
        tag: 'FEED_PRELOAD',
        error: e,
      );
    }
  }
  
  /// Limpa o cache manualmente (útil para logout ou refresh forçado)
  void clearCache() {
    _cache.clear();
    AppLogger.info(
      '🗑️ [FeedPreloader] Cache limpo',
      tag: 'FEED_PRELOAD',
    );
  }
  
  /// Invalida o cache de um scope específico
  void invalidateCacheFor(EventPhotoFeedScope scope) {
    final key = _scopeKey(scope);
    _cache.remove(key);
    AppLogger.info(
      '🔄 [FeedPreloader] Cache invalidado para $key',
      tag: 'FEED_PRELOAD',
    );
  }
  
  /// Invalida todo o cache para forçar refresh no próximo acesso
  void invalidateCache() {
    _cache.clear();
    AppLogger.info(
      '🔄 [FeedPreloader] Todo cache invalidado',
      tag: 'FEED_PRELOAD',
    );
  }
}
