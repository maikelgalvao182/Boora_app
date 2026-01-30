import 'package:flutter/foundation.dart';

/// ✅ Serviço de instrumentação para métricas do chat
/// Permite provar redução de custos e melhorias de performance
/// 
/// Métricas coletadas:
/// - chat_open: abertura de chat com cache hit e time to first paint
/// - chat_stream_docs: tamanho e frequência de snapshots
/// - chat_pagination_load: carregamento de páginas adicionais
/// - active_streams_count: streams ativos simultaneamente
class ChatAnalyticsService {
  ChatAnalyticsService._internal();
  
  static final ChatAnalyticsService _instance = ChatAnalyticsService._internal();
  static ChatAnalyticsService get instance => _instance;
  
  // ========== Estado de Streams Ativos ==========
  final Set<String> _activeMessageStreams = {};
  final Set<String> _activeMetadataStreams = {};
  final Set<String> _activePresenceStreams = {};
  
  int get activeStreamsCount => 
      _activeMessageStreams.length + 
      _activeMetadataStreams.length + 
      _activePresenceStreams.length;
  
  // ========== Tracking de Chat Open ==========
  final Map<String, DateTime> _chatOpenTimes = {};
  final Map<String, int> _snapshotCounts = {};
  
  // ========== MÉTRICA 1: chat_open ==========
  /// Registra abertura de um chat
  void logChatOpen({
    required String chatId,
    required String chatType, // '1:1' ou 'group'
    required bool cacheHit,
    required int initialMessagesRendered,
  }) {
    _chatOpenTimes[chatId] = DateTime.now();
    _snapshotCounts[chatId] = 0;
    
    _log('📊 [METRIC] chat_open', {
      'chat_id': chatId,
      'chat_type': chatType,
      'cache_hit': cacheHit,
      'initial_messages_rendered': initialMessagesRendered,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Registra time to first paint (chamar quando UI renderiza)
  void logTimeToFirstPaint({
    required String chatId,
    required bool cacheHit,
    required int messagesRendered,
  }) {
    final openTime = _chatOpenTimes[chatId];
    if (openTime == null) return;
    
    final duration = DateTime.now().difference(openTime);
    
    _log('📊 [METRIC] chat_first_paint', {
      'chat_id': chatId,
      'time_to_first_paint_ms': duration.inMilliseconds,
      'cache_hit': cacheHit,
      'messages_rendered': messagesRendered,
    });
  }
  
  // ========== MÉTRICA 2: chat_stream_docs ==========
  /// Registra recebimento de snapshot de mensagens
  void logStreamSnapshot({
    required String chatId,
    required int docsInSnapshot,
    required bool isFromCache,
  }) {
    _snapshotCounts[chatId] = (_snapshotCounts[chatId] ?? 0) + 1;
    
    _log('📊 [METRIC] chat_stream_docs', {
      'chat_id': chatId,
      'docs_in_snapshot': docsInSnapshot,
      'snapshot_count': _snapshotCounts[chatId],
      'is_from_cache': isFromCache,
      'active_streams': activeStreamsCount,
    });
  }
  
  // ========== MÉTRICA 3: chat_pagination_load ==========
  /// Registra carregamento de página de histórico
  void logPaginationLoad({
    required String chatId,
    required int pageSize,
    required int docsLoaded,
    required int durationMs,
  }) {
    _log('📊 [METRIC] chat_pagination_load', {
      'chat_id': chatId,
      'page_size': pageSize,
      'docs_loaded': docsLoaded,
      'duration_ms': durationMs,
    });
  }
  
  // ========== MÉTRICA 4: active_streams_count ==========
  /// Registra abertura de stream de mensagens
  void registerMessageStream(String chatId) {
    _activeMessageStreams.add(chatId);
    _logActiveStreams('message_stream_opened', chatId);
  }
  
  /// Registra fechamento de stream de mensagens
  void unregisterMessageStream(String chatId) {
    _activeMessageStreams.remove(chatId);
    _logActiveStreams('message_stream_closed', chatId);
  }
  
  /// Registra abertura de stream de metadata
  void registerMetadataStream(String chatId) {
    _activeMetadataStreams.add(chatId);
    _logActiveStreams('metadata_stream_opened', chatId);
  }
  
  /// Registra fechamento de stream de metadata
  void unregisterMetadataStream(String chatId) {
    _activeMetadataStreams.remove(chatId);
    _logActiveStreams('metadata_stream_closed', chatId);
  }
  
  /// Registra abertura de stream de presença
  void registerPresenceStream(String userId) {
    _activePresenceStreams.add(userId);
    _logActiveStreams('presence_stream_opened', userId);
  }
  
  /// Registra fechamento de stream de presença
  void unregisterPresenceStream(String userId) {
    _activePresenceStreams.remove(userId);
    _logActiveStreams('presence_stream_closed', userId);
  }
  
  void _logActiveStreams(String event, String id) {
    _log('📊 [METRIC] active_streams_count', {
      'event': event,
      'id': id,
      'message_streams': _activeMessageStreams.length,
      'metadata_streams': _activeMetadataStreams.length,
      'presence_streams': _activePresenceStreams.length,
      'total_active': activeStreamsCount,
    });
  }
  
  // ========== MÉTRICA EXTRA: Resumo de sessão ==========
  /// Retorna resumo das métricas da sessão atual
  Map<String, dynamic> getSessionSummary() {
    return {
      'active_message_streams': _activeMessageStreams.length,
      'active_metadata_streams': _activeMetadataStreams.length,
      'active_presence_streams': _activePresenceStreams.length,
      'total_active_streams': activeStreamsCount,
      'chats_opened': _chatOpenTimes.length,
      'total_snapshots': _snapshotCounts.values.fold(0, (a, b) => a + b),
    };
  }
  
  /// Limpa métricas (chamar no logout)
  void reset() {
    _activeMessageStreams.clear();
    _activeMetadataStreams.clear();
    _activePresenceStreams.clear();
    _chatOpenTimes.clear();
    _snapshotCounts.clear();
    _log('📊 [METRIC] analytics_reset', {});
  }
  
  // ========== Helper de Log ==========
  void _log(String tag, Map<String, dynamic> data) {
    if (kDebugMode) {
      final dataStr = data.entries.map((e) => '${e.key}=${e.value}').join(', ');
      debugPrint('$tag { $dataStr }');
    }
    
    // TODO: Integrar com Firebase Analytics ou outro serviço de métricas
    // FirebaseAnalytics.instance.logEvent(name: tag, parameters: data);
  }
}
