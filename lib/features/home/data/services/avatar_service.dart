import 'package:cloud_firestore/cloud_firestore.dart';

/// Serviço responsável por buscar URLs de avatar dos usuários
/// 
/// Responsabilidades:
/// - Buscar avatar do Firestore
/// - Retornar fallback quando necessário
/// - Cache opcional (futuro)
class AvatarService {
  final FirebaseFirestore _firestore;
  
  /// Cache de avatares em memória
  final Map<String, String> _avatarCache = {};
  
  /// URL padrão para fallback (vazio indica usar fallback local)
  static const String defaultAvatarUrl = '';

  AvatarService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Busca URL do avatar de um usuário
  /// 
  /// Retorna:
  /// - URL do avatar se encontrado
  /// - URL padrão como fallback
  /// 
  /// Parâmetros:
  /// - [userId]: ID do usuário no Firestore
  /// - [useCache]: Se deve usar cache em memória (padrão: true)
  Future<String> getAvatarUrl(
    String userId, {
    bool useCache = true,
  }) async {
    // Verificar cache
    if (useCache && _avatarCache.containsKey(userId)) {
      return _avatarCache[userId]!;
    }

    try {
        final doc = await _firestore
          .collection('users_preview')
          .doc(userId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final photoUrl = data?['avatarThumbUrl'] as String? ??
          data?['photoUrl'] as String? ??
          defaultAvatarUrl;
        
        // Salvar no cache
        if (useCache) {
          _avatarCache[userId] = photoUrl;
        }
        
        return photoUrl;
      }
    } catch (e) {
      // Erros serão tratados retornando fallback
      // Não logamos aqui para evitar poluir logs
    }

    return defaultAvatarUrl;
  }

  /// Limpa o cache de avatares
  void clearCache() {
    _avatarCache.clear();
  }

  /// Remove um avatar específico do cache
  void removeCachedAvatar(String userId) {
    _avatarCache.remove(userId);
  }

  /// Pré-carrega múltiplos avatares em paralelo
  /// 
  /// Útil quando você sabe quais usuários precisará
  Future<Map<String, String>> preloadAvatars(List<String> userIds) async {
    final futures = userIds.map((id) => getAvatarUrl(id));
    final urls = await Future.wait(futures);
    
    return Map.fromIterables(userIds, urls);
  }
}
