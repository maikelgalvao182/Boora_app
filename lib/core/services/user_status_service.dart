import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fire_auth;
import 'package:flutter/foundation.dart';

/// Serviço para verificar status de usuários (active/inactive)
/// 
/// Características:
/// - Cache em memória para performance
/// - ChangeNotifier para reatividade
/// - Carrega status sob demanda
/// - TTL de 5 minutos para cache
class UserStatusService extends ChangeNotifier {
  UserStatusService._();
  
  static final UserStatusService instance = UserStatusService._();
  factory UserStatusService() => instance;

  final _db = FirebaseFirestore.instance;
  
  // ==================== CACHE ====================
  
  /// Cache de status de usuários (userId -> status)
  final Map<String, _CachedStatus> _statusCache = {};
  
  /// TTL do cache (5 minutos)
  static const Duration _cacheTtl = Duration(minutes: 5);
  
  // ==================== MÉTODOS PÚBLICOS ====================
  
  /// Verifica se um usuário está ativo (status == 'active')
  /// Retorna true se ativo ou se não conseguir verificar (fail-safe)
  bool isUserActive(String userId) {
    if (userId.isEmpty) return true;
    
    final cached = _statusCache[userId];
    if (cached != null && !cached.isExpired) {
      return cached.status == 'active';
    }
    
    // Se não tem cache, agenda busca em background e retorna true (fail-safe)
    _fetchStatusInBackground(userId);
    return true;
  }
  
  /// Verifica se um usuário está inativo
  bool isUserInactive(String userId) {
    if (userId.isEmpty) return false;
    
    final cached = _statusCache[userId];
    if (cached != null && !cached.isExpired) {
      return cached.status == 'inactive';
    }
    
    // Se não tem cache, retorna false (fail-safe - não bloqueia UI)
    _fetchStatusInBackground(userId);
    return false;
  }
  
  /// Verifica se um usuário está ativo de forma síncrona (apenas cache)
  /// Retorna null se não tiver no cache
  bool? isUserActiveCached(String userId) {
    if (userId.isEmpty) return null;
    
    final cached = _statusCache[userId];
    if (cached != null && !cached.isExpired) {
      return cached.status == 'active';
    }
    
    return null;
  }
  
  /// Busca status de um usuário (com await)
  Future<String> fetchUserStatus(String userId) async {
    if (userId.isEmpty) return 'active';
    
    // Verifica cache primeiro
    final cached = _statusCache[userId];
    if (cached != null && !cached.isExpired) {
      return cached.status;
    }
    
    try {
      final doc = await _db
          .collection('users_preview')
          .doc(userId)
          .get();
      
      if (!doc.exists) {
        _statusCache[userId] = _CachedStatus(status: 'active', fetchedAt: DateTime.now());
        return 'active';
      }
      
      final data = doc.data();
      final status = data?['status'] as String? ?? 'active';
      
      _statusCache[userId] = _CachedStatus(status: status, fetchedAt: DateTime.now());
      
      if (status == 'inactive') {
        debugPrint('👤 [UserStatusService] User $userId is inactive');
        notifyListeners();
      }
      
      return status;
    } catch (e) {
      debugPrint('❌ [UserStatusService] Error fetching status for $userId: $e');
      return 'active'; // Fail-safe
    }
  }
  
  /// Busca status de múltiplos usuários de uma vez
  Future<Map<String, String>> fetchUsersStatus(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    
    final result = <String, String>{};
    final toFetch = <String>[];
    
    // Verifica cache primeiro
    for (final userId in userIds) {
      final cached = _statusCache[userId];
      if (cached != null && !cached.isExpired) {
        result[userId] = cached.status;
      } else {
        toFetch.add(userId);
      }
    }
    
    // Busca os que faltam
    if (toFetch.isNotEmpty) {
      // Busca em chunks de 10 (limite do whereIn)
      for (var i = 0; i < toFetch.length; i += 10) {
        final chunk = toFetch.skip(i).take(10).toList();
        
        try {
          final snapshot = await _db
              .collection('users_preview')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final status = data['status'] as String? ?? 'active';
            _statusCache[doc.id] = _CachedStatus(status: status, fetchedAt: DateTime.now());
            result[doc.id] = status;
          }
          
          // IDs não encontrados = active
          for (final id in chunk) {
            if (!result.containsKey(id)) {
              _statusCache[id] = _CachedStatus(status: 'active', fetchedAt: DateTime.now());
              result[id] = 'active';
            }
          }
        } catch (e) {
          debugPrint('❌ [UserStatusService] Error fetching batch status: $e');
          // Fail-safe: assume todos ativos
          for (final id in chunk) {
            if (!result.containsKey(id)) {
              result[id] = 'active';
            }
          }
        }
      }
    }
    
    return result;
  }
  
  /// Atualiza o cache com um status conhecido
  void updateCache(String userId, String status) {
    _statusCache[userId] = _CachedStatus(status: status, fetchedAt: DateTime.now());
    if (status == 'inactive') {
      notifyListeners();
    }
  }
  
  /// Limpa o cache
  void clearCache() {
    _statusCache.clear();
  }
  
  // ==================== MÉTODOS PRIVADOS ====================
  
  /// Busca status em background (não bloqueia)
  void _fetchStatusInBackground(String userId) {
    Future.microtask(() => fetchUserStatus(userId));
  }
}

/// Cache de status com TTL
class _CachedStatus {
  final String status;
  final DateTime fetchedAt;
  
  _CachedStatus({required this.status, required this.fetchedAt});
  
  bool get isExpired => DateTime.now().difference(fetchedAt) > UserStatusService._cacheTtl;
}
