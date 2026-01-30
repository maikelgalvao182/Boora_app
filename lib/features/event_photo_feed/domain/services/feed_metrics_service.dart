import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_feed_scope.dart';

/// Provider para o serviço de métricas do feed
final feedMetricsServiceProvider = Provider<FeedMetricsService>((ref) {
  return FeedMetricsService();
});

/// ============================================================================
/// FEED METRICS SERVICE
/// ============================================================================
/// 
/// Serviço de instrumentação para medir o custo real do feed.
/// 
/// Métricas coletadas:
/// - feed_scope_load: carregamento de feed por scope
/// - likes_hydration: hidratação do cache de likes
/// - following_queries: queries de chunking na aba Following
/// 
/// Todas as métricas são enviadas para Firebase Analytics.
/// 
/// Uso:
/// ```dart
/// final metrics = ref.read(feedMetricsServiceProvider);
/// final tracker = metrics.startFeedLoad(scope);
/// // ... carregar feed
/// tracker.finish(docsRead: 20, cacheHit: false);
/// ```
class FeedMetricsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Inicia tracking de carregamento de feed
  FeedLoadTracker startFeedLoad(EventPhotoFeedScope scope) {
    return FeedLoadTracker(
      scope: scope,
      analytics: _analytics,
      startTime: DateTime.now(),
    );
  }

  /// Registra hidratação do cache de likes
  Future<void> logLikesHydration({
    required int pageSize,
    required int readsUsed,
    required bool cacheHit,
    required Duration duration,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'likes_hydration',
        parameters: {
          'page_size': pageSize,
          'reads_used': readsUsed,
          'cache_hit': cacheHit ? 1 : 0,
          'cache_hit_rate': cacheHit ? 100.0 : 0.0,
          'duration_ms': duration.inMilliseconds,
        },
      );
      
      debugPrint('📊 [FeedMetrics] likes_hydration: '
          'pageSize=$pageSize, reads=$readsUsed, cacheHit=$cacheHit, '
          'duration=${duration.inMilliseconds}ms');
    } catch (e) {
      debugPrint('⚠️ [FeedMetrics] Erro ao logar likes_hydration: $e');
    }
  }

  /// Registra queries de chunking na aba Following
  Future<void> logFollowingQueries({
    required int followingCount,
    required int chunksUsed,
    required int docsRead,
    required Duration duration,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'following_queries',
        parameters: {
          'following_count': followingCount,
          'chunks_used': chunksUsed,
          'docs_read': docsRead,
          'duration_ms': duration.inMilliseconds,
          'reads_per_chunk': chunksUsed > 0 ? (docsRead / chunksUsed).round() : 0,
        },
      );
      
      debugPrint('📊 [FeedMetrics] following_queries: '
          'following=$followingCount, chunks=$chunksUsed, docs=$docsRead, '
          'duration=${duration.inMilliseconds}ms');
    } catch (e) {
      debugPrint('⚠️ [FeedMetrics] Erro ao logar following_queries: $e');
    }
  }

  /// Registra uso do fanout (novo sistema)
  Future<void> logFanoutLoad({
    required int docsRead,
    required Duration duration,
    required bool success,
    String? fallbackReason,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'fanout_load',
        parameters: {
          'docs_read': docsRead,
          'duration_ms': duration.inMilliseconds,
          'success': success ? 1 : 0,
          if (fallbackReason != null) 'fallback_reason': fallbackReason,
        },
      );
      
      debugPrint('📊 [FeedMetrics] fanout_load: '
          'docs=$docsRead, success=$success, '
          'duration=${duration.inMilliseconds}ms');
    } catch (e) {
      debugPrint('⚠️ [FeedMetrics] Erro ao logar fanout_load: $e');
    }
  }

  /// Registra refresh de feed
  Future<void> logFeedRefresh({
    required String scope,
    required bool isIncremental,
    required int newItemsCount,
    required Duration duration,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'feed_refresh',
        parameters: {
          'scope': scope,
          'is_incremental': isIncremental ? 1 : 0,
          'new_items': newItemsCount,
          'duration_ms': duration.inMilliseconds,
        },
      );
    } catch (e) {
      debugPrint('⚠️ [FeedMetrics] Erro ao logar feed_refresh: $e');
    }
  }
}

/// Tracker para medir carregamento de feed
class FeedLoadTracker {
  FeedLoadTracker({
    required this.scope,
    required this.analytics,
    required this.startTime,
  });

  final EventPhotoFeedScope scope;
  final FirebaseAnalytics analytics;
  final DateTime startTime;

  /// Finaliza tracking e envia métricas
  Future<void> finish({
    required int docsRead,
    required bool cacheHit,
    int? followingChunks,
  }) async {
    final duration = DateTime.now().difference(startTime);
    final scopeName = _scopeToString(scope);
    
    try {
      await analytics.logEvent(
        name: 'feed_scope_load',
        parameters: {
          'scope': scopeName,
          'cache_hit': cacheHit ? 1 : 0,
          'docs_read': docsRead,
          'duration_ms': duration.inMilliseconds,
          if (followingChunks != null) 'following_chunks': followingChunks,
        },
      );
      
      debugPrint('📊 [FeedMetrics] feed_scope_load: '
          'scope=$scopeName, cacheHit=$cacheHit, docs=$docsRead, '
          'duration=${duration.inMilliseconds}ms'
          '${followingChunks != null ? ', chunks=$followingChunks' : ''}');
    } catch (e) {
      debugPrint('⚠️ [FeedMetrics] Erro ao logar feed_scope_load: $e');
    }
  }

  String _scopeToString(EventPhotoFeedScope scope) {
    return switch (scope) {
      EventPhotoFeedScopeGlobal() => 'global',
      EventPhotoFeedScopeFollowing() => 'following',
      EventPhotoFeedScopeUser() => 'user',
      EventPhotoFeedScopeCity() => 'city',
      EventPhotoFeedScopeEvent() => 'event',
    };
  }
}

/// ============================================================================
/// TTL CONFIGURATION POR SCOPE
/// ============================================================================
/// 
/// Configuração de TTL diferenciada por tipo de aba:
/// 
/// - Global: TTL maior (10-15min) - dados mudam menos frequentemente
/// - Following: TTL menor (2min) - usuário espera ver posts novos
/// - My Posts: TTL médio (5min) - próprio usuário controla
/// - City/Event: TTL médio (5min) - contexto específico
class FeedTtlConfig {
  /// TTL para cache em memória (revalidação do controller)
  static Duration getMemoryTtl(EventPhotoFeedScope scope) {
    return switch (scope) {
      EventPhotoFeedScopeGlobal() => const Duration(minutes: 2),
      EventPhotoFeedScopeFollowing() => const Duration(seconds: 45),
      EventPhotoFeedScopeUser() => const Duration(minutes: 1),
      EventPhotoFeedScopeCity() => const Duration(minutes: 1, seconds: 30),
      EventPhotoFeedScopeEvent() => const Duration(minutes: 1, seconds: 30),
    };
  }

  /// TTL para cache Hive (índice do feed)
  static Duration getHiveFeedTtl(EventPhotoFeedScope scope) {
    return switch (scope) {
      EventPhotoFeedScopeGlobal() => const Duration(minutes: 10),
      EventPhotoFeedScopeFollowing() => const Duration(minutes: 3),
      EventPhotoFeedScopeUser() => const Duration(minutes: 5),
      EventPhotoFeedScopeCity() => const Duration(minutes: 5),
      EventPhotoFeedScopeEvent() => const Duration(minutes: 5),
    };
  }

  /// TTL para cache Hive (posts individuais)
  static Duration getHivePostTtl(EventPhotoFeedScope scope) {
    return switch (scope) {
      EventPhotoFeedScopeGlobal() => const Duration(minutes: 15),
      EventPhotoFeedScopeFollowing() => const Duration(minutes: 8),
      EventPhotoFeedScopeUser() => const Duration(minutes: 10),
      EventPhotoFeedScopeCity() => const Duration(minutes: 10),
      EventPhotoFeedScopeEvent() => const Duration(minutes: 10),
    };
  }

  /// Intervalo mínimo entre refreshes silenciosos (debounce)
  static Duration getRefreshDebounce(EventPhotoFeedScope scope) {
    return switch (scope) {
      EventPhotoFeedScopeGlobal() => const Duration(seconds: 30),
      EventPhotoFeedScopeFollowing() => const Duration(seconds: 15),
      EventPhotoFeedScopeUser() => const Duration(seconds: 20),
      EventPhotoFeedScopeCity() => const Duration(seconds: 20),
      EventPhotoFeedScopeEvent() => const Duration(seconds: 20),
    };
  }
}
