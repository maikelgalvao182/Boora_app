import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:partiu/features/profile/presentation/controllers/followers_controller.dart';
import 'package:partiu/features/profile/presentation/controllers/followers_cache_service.dart';

/// ✅ OTIMIZAÇÃO: Cache de FollowersController por userId
/// 
/// Evita recriar controller toda vez que a tela é aberta.
/// Controllers são mantidos por [_ttlMinutes] após último uso.
/// 
/// Economia: Elimina queries duplicadas em navegações frequentes
class FollowersControllerCache {
  FollowersControllerCache._();
  
  static final FollowersControllerCache instance = FollowersControllerCache._();
  
  /// TTL em minutos - após esse tempo sem uso, controller é descartado
  static const int _ttlMinutes = 5;
  
  /// Cache de controllers por userId
  final Map<String, _CachedController> _cache = {};
  
  /// Timer de limpeza periódica
  Timer? _cleanupTimer;
  
  /// Obtém ou cria um controller para o userId
  /// 
  /// Se já existe em cache e não expirou, retorna o existente.
  /// Caso contrário, cria um novo e armazena em cache.
  Future<FollowersController> getOrCreate(String userId) async {
    // Garantir que o cache Hive está inicializado
    await FollowersCacheService.instance.initialize();
    
    final cached = _cache[userId];
    
    if (cached != null && !cached.isExpired) {
      // ✅ Cache hit - atualiza timestamp e retorna
      cached.touch();
      debugPrint('✅ [FollowersCache] Cache HIT para $userId');
      return cached.controller;
    }
    
    // Cache miss ou expirado - criar novo
    if (cached != null) {
      // Limpar o expirado
      cached.controller.dispose();
      _cache.remove(userId);
      debugPrint('🗑️ [FollowersCache] Controller expirado removido: $userId');
    }
    
    // Criar novo controller
    final controller = FollowersController(userId: userId);
    controller.initialize();
    
    _cache[userId] = _CachedController(controller);
    debugPrint('🆕 [FollowersCache] Novo controller criado para $userId');
    
    // Iniciar timer de limpeza se não existir
    _startCleanupTimer();
    
    return controller;
  }
  
  /// Marca o controller como "em uso" (atualiza timestamp)
  void touch(String userId) {
    _cache[userId]?.touch();
  }
  
  /// Remove um controller específico do cache
  void remove(String userId) {
    final cached = _cache.remove(userId);
    if (cached != null) {
      cached.controller.dispose();
      debugPrint('🗑️ [FollowersCache] Controller removido: $userId');
    }
  }
  
  /// Limpa todo o cache
  void clear() {
    for (final cached in _cache.values) {
      cached.controller.dispose();
    }
    _cache.clear();
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    debugPrint('🗑️ [FollowersCache] Cache limpo');
  }
  
  /// Inicia timer de limpeza periódica (a cada 1 minuto)
  void _startCleanupTimer() {
    if (_cleanupTimer != null) return;
    
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _cleanupExpired(),
    );
  }
  
  /// Remove controllers expirados
  void _cleanupExpired() {
    final expiredKeys = <String>[];
    
    for (final entry in _cache.entries) {
      if (entry.value.isExpired) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      final cached = _cache.remove(key);
      cached?.controller.dispose();
      debugPrint('🗑️ [FollowersCache] Cleanup: controller expirado removido: $key');
    }
    
    // Se cache vazio, parar timer
    if (_cache.isEmpty) {
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
    }
  }
  
  /// Estatísticas do cache (debug)
  Map<String, dynamic> get stats => {
    'size': _cache.length,
    'userIds': _cache.keys.toList(),
    'timerActive': _cleanupTimer != null,
  };
}

/// Wrapper com timestamp de último acesso
class _CachedController {
  _CachedController(this.controller) : _lastAccess = DateTime.now();
  
  final FollowersController controller;
  DateTime _lastAccess;
  
  /// Atualiza timestamp de último acesso
  void touch() {
    _lastAccess = DateTime.now();
  }
  
  /// Verifica se expirou (não usado por mais de TTL)
  bool get isExpired {
    final elapsed = DateTime.now().difference(_lastAccess);
    return elapsed.inMinutes >= FollowersControllerCache._ttlMinutes;
  }
}
