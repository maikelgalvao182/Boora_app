import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/shared/repositories/user_repository.dart';

/// ✅ Cache Hive para lista de seguidores/seguindo
/// 
/// Implementa Stale-While-Revalidate:
/// 1. Mostra cache instantaneamente (se válido)
/// 2. Revalida em background do Firestore
/// 3. Atualiza UI quando dados frescos chegam
/// 
/// Estrutura do cache:
/// - Key: "followers:{userId}" ou "following:{userId}"
/// - Value: JSON com lista de {id, createdAt} + metadata
/// 
/// TTLs (conforme recomendação):
/// - followers/following index: 20 minutos
/// - users_preview cache: 30 minutos
/// 
/// 🔗 Usa UserRepository.getUsersByIds() que busca de users_preview (não Users completo)
/// 🔗 Batch com whereIn chunks de 10 (evita 30 gets paralelos)
class FollowersCacheService {
  FollowersCacheService._();
  
  static final FollowersCacheService instance = FollowersCacheService._();
  
  /// Cache para lista de IDs (followers/following) - Hive persistente
  late final HiveCacheService<String> _indexCache;
  
  /// Cache para users_preview - Hive persistente (30 min TTL)
  late final HiveCacheService<String> _usersPreviewCache;
  
  /// Repository para buscar users_preview do Firestore
  final UserRepository _userRepository = UserRepository();
  
  bool _initialized = false;
  
  /// TTL para index de followers/following: 20 minutos
  static const Duration _indexTtl = Duration(minutes: 20);
  
  /// TTL para users_preview: 30 minutos
  static const Duration _usersPreviewTtl = Duration(minutes: 30);
  
  /// TTL para considerar cache "fresh" (não precisa revalidar): 5 minutos
  static const Duration _freshThreshold = Duration(minutes: 5);
  
  /// Inicializa os boxes do Hive
  Future<void> initialize() async {
    if (_initialized) return;
    
    _indexCache = HiveCacheService<String>('followers_index');
    _usersPreviewCache = HiveCacheService<String>('followers_users_preview');
    
    await Future.wait([
      _indexCache.initialize(),
      _usersPreviewCache.initialize(),
    ]);
    
    _initialized = true;
    debugPrint('✅ [FollowersCache] Inicializado (TTL index: ${_indexTtl.inMinutes}min, users: ${_usersPreviewTtl.inMinutes}min)');
  }
  
  /// Garante que o serviço está inicializado
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }
  
  // ========== FOLLOWERS INDEX CACHE ==========
  
  /// Obtém lista de followers do cache (IDs + createdAt)
  /// 
  /// Retorna null se cache vazio ou expirado
  Future<FollowersIndexEntry?> getFollowersIndex(String userId) async {
    await _ensureInitialized();
    
    final key = 'followers:$userId';
    final json = _indexCache.get(key);
    
    if (json == null) {
      debugPrint('📦 [FollowersCache] INDEX MISS: $key');
      return null;
    }
    
    try {
      final entry = FollowersIndexEntry.fromJson(jsonDecode(json) as Map<String, dynamic>);
      debugPrint('📦 [FollowersCache] INDEX HIT: $key (${entry.items.length} items, age: ${entry.ageMinutes}min)');
      return entry;
    } catch (e) {
      debugPrint('📦 [FollowersCache] INDEX ERROR: $key ($e)');
      await _indexCache.delete(key);
      return null;
    }
  }
  
  /// Salva lista de followers no cache (IDs + createdAt)
  Future<void> saveFollowersIndex(
    String userId, 
    List<FollowerIndexItem> items, {
    bool hasMore = true,
  }) async {
    await _ensureInitialized();
    
    final key = 'followers:$userId';
    final entry = FollowersIndexEntry(
      items: items,
      hasMore: hasMore,
      cachedAt: DateTime.now(),
    );
    
    await _indexCache.put(key, jsonEncode(entry.toJson()), ttl: _indexTtl);
    debugPrint('📦 [FollowersCache] INDEX SAVED: $key (${items.length} items, TTL: ${_indexTtl.inMinutes}min)');
  }
  
  // ========== FOLLOWING INDEX CACHE ==========
  
  /// Obtém lista de following do cache (IDs + createdAt)
  Future<FollowersIndexEntry?> getFollowingIndex(String userId) async {
    await _ensureInitialized();
    
    final key = 'following:$userId';
    final json = _indexCache.get(key);
    
    if (json == null) {
      debugPrint('📦 [FollowersCache] INDEX MISS: $key');
      return null;
    }
    
    try {
      final entry = FollowersIndexEntry.fromJson(jsonDecode(json) as Map<String, dynamic>);
      debugPrint('📦 [FollowersCache] INDEX HIT: $key (${entry.items.length} items, age: ${entry.ageMinutes}min)');
      return entry;
    } catch (e) {
      debugPrint('📦 [FollowersCache] INDEX ERROR: $key ($e)');
      await _indexCache.delete(key);
      return null;
    }
  }
  
  /// Salva lista of following no cache (IDs + createdAt)
  Future<void> saveFollowingIndex(
    String userId, 
    List<FollowerIndexItem> items, {
    bool hasMore = true,
  }) async {
    await _ensureInitialized();
    
    final key = 'following:$userId';
    final entry = FollowersIndexEntry(
      items: items,
      hasMore: hasMore,
      cachedAt: DateTime.now(),
    );
    
    await _indexCache.put(key, jsonEncode(entry.toJson()), ttl: _indexTtl);
    debugPrint('📦 [FollowersCache] INDEX SAVED: $key (${items.length} items, TTL: ${_indexTtl.inMinutes}min)');
  }
  
  // ========== USERS PREVIEW CACHE (Hive persistente) ==========
  
  /// Obtém users_preview do cache Hive
  /// 
  /// Retorna Map com userId -> userData apenas para IDs encontrados
  Future<Map<String, Map<String, dynamic>>> getUsersPreviewFromCache(List<String> userIds) async {
    await _ensureInitialized();
    
    final result = <String, Map<String, dynamic>>{};
    
    for (final id in userIds) {
      final json = _usersPreviewCache.get(id);
      if (json != null) {
        try {
          result[id] = jsonDecode(json) as Map<String, dynamic>;
        } catch (e) {
          await _usersPreviewCache.delete(id);
        }
      }
    }
    
    if (result.isNotEmpty) {
      debugPrint('📦 [FollowersCache] USERS cache: ${result.length}/${userIds.length} hits');
    }
    
    return result;
  }
  
  /// Busca users_preview que não estão no cache (via UserRepository batch)
  /// 
  /// ✅ Usa users_preview collection (não Users completo)
  /// ✅ Batch com whereIn chunks de 10 (não 30 gets paralelos)
  Future<Map<String, Map<String, dynamic>>> fetchMissingUsersPreview(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    
    debugPrint('📦 [FollowersCache] Fetching ${userIds.length} users from users_preview');
    
    // UserRepository.getUsersByIds() já usa:
    // 1. users_preview collection (leve, ~500 bytes)
    // 2. Batch whereIn chunks de 10
    final usersMap = await _userRepository.getUsersByIds(userIds);
    
    // Salvar no cache Hive para próxima vez
    // ⚠️ Sanitizar dados antes de serializar (Timestamp → int)
    for (final entry in usersMap.entries) {
      final sanitized = _sanitizeForJson(entry.value);
      await _usersPreviewCache.put(
        entry.key, 
        jsonEncode(sanitized), 
        ttl: _usersPreviewTtl,
      );
    }
    
    debugPrint('📦 [FollowersCache] USERS fetched & cached: ${usersMap.length} users');
    return usersMap;
  }
  
  /// Converte Timestamp e outros tipos não-serializáveis para JSON
  Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    
    for (final entry in data.entries) {
      final value = entry.value;
      
      if (value is Timestamp) {
        // Converter Timestamp para milliseconds
        result[entry.key] = value.millisecondsSinceEpoch;
      } else if (value is DateTime) {
        // Converter DateTime para milliseconds
        result[entry.key] = value.millisecondsSinceEpoch;
      } else if (value is Map<String, dynamic>) {
        // Recursivamente sanitizar maps aninhados
        result[entry.key] = _sanitizeForJson(value);
      } else if (value is List) {
        // Sanitizar listas
        result[entry.key] = value.map((item) {
          if (item is Timestamp) return item.millisecondsSinceEpoch;
          if (item is DateTime) return item.millisecondsSinceEpoch;
          if (item is Map<String, dynamic>) return _sanitizeForJson(item);
          return item;
        }).toList();
      } else {
        // Valor já é serializável
        result[entry.key] = value;
      }
    }
    
    return result;
  }
  
  // ========== INVALIDATION ==========
  
  /// Invalida cache de seguidores para um usuário
  Future<void> invalidateFollowers(String userId) async {
    await _ensureInitialized();
    await _indexCache.delete('followers:$userId');
    debugPrint('📦 [FollowersCache] INVALIDATED: followers:$userId');
  }
  
  /// Invalida cache de seguindo para um usuário
  Future<void> invalidateFollowing(String userId) async {
    await _ensureInitialized();
    await _indexCache.delete('following:$userId');
    debugPrint('📦 [FollowersCache] INVALIDATED: following:$userId');
  }
  
  /// Invalida todo o cache de um usuário
  Future<void> invalidateUser(String userId) async {
    await invalidateFollowers(userId);
    await invalidateFollowing(userId);
  }
  
  /// Invalida um user preview específico
  Future<void> invalidateUserPreview(String userId) async {
    await _ensureInitialized();
    await _usersPreviewCache.delete(userId);
    debugPrint('📦 [FollowersCache] USER PREVIEW INVALIDATED: $userId');
  }
  
  /// Limpa todo o cache de index (não afeta users_preview)
  Future<void> clearIndexCache() async {
    await _ensureInitialized();
    await _indexCache.clear();
    debugPrint('📦 [FollowersCache] INDEX CLEARED');
  }
  
  /// Limpa todo o cache
  Future<void> clearAll() async {
    await _ensureInitialized();
    await Future.wait([
      _indexCache.clear(),
      _usersPreviewCache.clear(),
    ]);
    debugPrint('📦 [FollowersCache] ALL CLEARED');
  }
}

// ========== MODELS ==========

/// Item do index: ID + createdAt
class FollowerIndexItem {
  FollowerIndexItem({
    required this.id,
    required this.createdAt,
  });
  
  factory FollowerIndexItem.fromJson(Map<String, dynamic> json) {
    return FollowerIndexItem(
      id: json['id'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }
  
  final String id;
  final DateTime createdAt;
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };
}

/// Entrada do cache com metadata
class FollowersIndexEntry {
  FollowersIndexEntry({
    required this.items,
    required this.hasMore,
    required this.cachedAt,
  });
  
  factory FollowersIndexEntry.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List<dynamic>)
        .map((e) => FollowerIndexItem.fromJson(e as Map<String, dynamic>))
        .toList();
    
    return FollowersIndexEntry(
      items: itemsList,
      hasMore: json['hasMore'] as bool? ?? true,
      cachedAt: DateTime.fromMillisecondsSinceEpoch(json['cachedAt'] as int),
    );
  }
  
  final List<FollowerIndexItem> items;
  final bool hasMore;
  final DateTime cachedAt;
  
  /// Lista de IDs (convenience getter)
  List<String> get ids => items.map((e) => e.id).toList();
  
  /// Idade do cache em minutos
  int get ageMinutes => DateTime.now().difference(cachedAt).inMinutes;
  
  /// Verifica se o cache está "fresco" (menos de 5 min)
  bool get isFresh => DateTime.now().difference(cachedAt) < FollowersCacheService._freshThreshold;
  
  Map<String, dynamic> toJson() => {
    'items': items.map((e) => e.toJson()).toList(),
    'hasMore': hasMore,
    'cachedAt': cachedAt.millisecondsSinceEpoch,
  };
}
