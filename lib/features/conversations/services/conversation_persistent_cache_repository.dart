import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/features/conversations/models/conversation_item.dart';

/// Cache persistente para lista de conversas (cold start)
class ConversationPersistentCacheRepository {
  static final ConversationPersistentCacheRepository _instance =
      ConversationPersistentCacheRepository._internal();

  factory ConversationPersistentCacheRepository() => _instance;

  ConversationPersistentCacheRepository._internal();

  static const Duration _defaultTtl = Duration(minutes: 20);

  final HiveListCacheService<ConversationItem> _cache =
      HiveListCacheService<ConversationItem>('conversations_cache', maxItems: 50);

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _cache.initialize();
    _initialized = true;
  }

  String _buildKey(String userId) => 'user_$userId';

  Future<List<ConversationItem>?> getCached(String userId) async {
    await _ensureInitialized();
    return _cache.get(_buildKey(userId));
  }

  Future<void> cacheConversations(
    String userId,
    List<ConversationItem> items, {
    Duration ttl = _defaultTtl,
  }) async {
    await _ensureInitialized();
    await _cache.put(_buildKey(userId), items, ttl: ttl);
  }
}