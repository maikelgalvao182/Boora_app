import 'package:partiu/core/models/user_preview_model.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';

/// Serviço de cache persistente para users_preview (Stale-While-Revalidate)
/// 
/// Fonte de verdade secundária (após memória, antes do Firestore).
/// Armazena o envelope [CachedUserPreview] para controle de frescor.
class UserPreviewCacheService {
  static final UserPreviewCacheService instance = UserPreviewCacheService._();
  UserPreviewCacheService._();

  // Cache persistente com TTL de segurança (caso o SWR falhe ou app fique muito offline)
  // Mas a lógica principal de frescor é feita no UserStore comparando cachedAt
  static const Duration _safetyTtl = Duration(days: 7);

  final HiveCacheService<CachedUserPreview> _cache = 
      HiveCacheService<CachedUserPreview>('user_previews_v1');

  Future<void> initialize() => _cache.initialize();

  /// Recupera o envelope completo do cache
  CachedUserPreview? getEnvelope(String uid) {
    return _cache.get(uid); 
  }

  /// Salva o modelo no cache envelopado com timestamp atual
  Future<void> put(String uid, UserPreviewModel user, {DateTime? remoteUpdatedAt}) async {
    final envelope = CachedUserPreview(
      data: user, 
      cachedAt: DateTime.now(),
      remoteUpdatedAt: remoteUpdatedAt
    );
    await _cache.put(uid, envelope, ttl: _safetyTtl);
  }
  
  /// Bulk insert otimizado (future use)
  Future<void> putAll(List<UserPreviewModel> users) async {
    for (var u in users) {
      await put(u.uid, u);
    }
  }
}
