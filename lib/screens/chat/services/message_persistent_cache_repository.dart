import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/screens/chat/models/message_cache_item.dart';

/// Cache persistente das últimas mensagens por conversa
class MessagePersistentCacheRepository {
  static final MessagePersistentCacheRepository _instance =
      MessagePersistentCacheRepository._internal();

  factory MessagePersistentCacheRepository() => _instance;

  MessagePersistentCacheRepository._internal();

  static const Duration _defaultTtl = Duration(minutes: 20);
  static const int _maxItems = 30;

  final HiveListCacheService<MessageCacheItem> _cache =
      HiveListCacheService<MessageCacheItem>('messages_cache', maxItems: _maxItems);

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _cache.initialize();
    _initialized = true;
  }

  String _buildKey(String currentUserId, String conversationId) {
    return 'user_${currentUserId}_$conversationId';
  }

  Future<List<MessageCacheItem>?> getCached(
    String currentUserId,
    String conversationId,
  ) async {
    await _ensureInitialized();
    return _cache.get(_buildKey(currentUserId, conversationId));
  }

  Future<void> cacheMessages(
    String currentUserId,
    String conversationId,
    List<MessageCacheItem> items, {
    Duration ttl = _defaultTtl,
  }) async {
    await _ensureInitialized();
    await _cache.put(_buildKey(currentUserId, conversationId), items, ttl: ttl);
  }
}