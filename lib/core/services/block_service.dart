import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fire_auth;
import 'package:flutter/foundation.dart';

/// Serviço profissional de bloqueio de usuários (REATIVO)
/// 
/// Características:
/// - Bloqueio unilateral (mas funciona como bilateral no resultado)
/// - Leve e escalável
/// - Índice simples e rápido
/// - Coleção própria (não dentro do documento do usuário)
/// - **Cache em memória para performance**
/// - **ChangeNotifier para reatividade instantânea**
/// - **Atualiza UI automaticamente sem reiniciar app**
class BlockService extends ChangeNotifier {
  BlockService._();
  
  static final BlockService instance = BlockService._();
  factory BlockService() => instance;

  final _db = FirebaseFirestore.instance;
  static const String _collection = 'blockedUsers';
  
  // ==================== CACHE REATIVO ====================
  
  /// Cache de usuários bloqueados (blockerId -> Set de targetIds)
  final Map<String, Set<String>> _blockedByMeCache = {};
  
  /// Cache de usuários que me bloquearam (targetId -> Set de blockerIds)
  final Map<String, Set<String>> _blockedMeCache = {};
  
  /// Stream subscriptions ativas
  final Map<String, StreamSubscription> _subscriptions = {};

  StreamSubscription<fire_auth.User?>? _authSubscription;
  
  /// Flag para controlar se já foi inicializado
  bool _isInitialized = false;

  // ==================== INICIALIZAÇÃO ====================
  
  /// Inicializa o cache para um usuário
  /// **CHAMAR ISSO NO LOGIN**
  Future<void> initialize(String userId) async {
    if (_isInitialized) {
      debugPrint('⚠️ [BlockService] Já inicializado, pulando...');
      return;
    }
    
    debugPrint('🔄 [BlockService] Inicializando cache para $userId');

    _authSubscription ??= fire_auth.FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) return;
      unawaited(reset());
    });
    
    // Cancela subscriptions antigas se existirem
    await _cancelSubscriptions();
    
    // Limpa caches
    _blockedByMeCache.clear();
    _blockedMeCache.clear();
    
    // Carrega bloqueados por mim
    _subscriptions['blockedByMe'] = _db
        .collection(_collection)
        .where('blockerId', isEqualTo: userId)
        .limit(500) // Limite para reduzir leituras Firestore
        .snapshots()
      .listen((snapshot) {
      final blockedIds = snapshot.docs
          .map((doc) => doc.data()['targetId'] as String)
          .toSet();
      
      _blockedByMeCache[userId] = blockedIds;
      notifyListeners(); // ⬅️ NOTIFICA UI INSTANTANEAMENTE
      
      debugPrint('✅ [BlockService] Cache atualizado: ${blockedIds.length} bloqueados');
    }, onError: (error) {
      final isPermissionDenied = error is FirebaseException && error.code == 'permission-denied';
      final isLoggedOut = fire_auth.FirebaseAuth.instance.currentUser == null;
      if (isPermissionDenied && isLoggedOut) {
        unawaited(reset());
        return;
      }

      debugPrint('❌ [BlockService] Erro no stream blockedByMe: $error');
    });
    
    // Carrega quem me bloqueou
    _subscriptions['blockedMe'] = _db
        .collection(_collection)
        .where('targetId', isEqualTo: userId)
        .limit(500) // Limite para reduzir leituras Firestore
        .snapshots()
      .listen((snapshot) {
      final blockerIds = snapshot.docs
          .map((doc) => doc.data()['blockerId'] as String)
          .toSet();
      
      _blockedMeCache[userId] = blockerIds;
      notifyListeners(); // ⬅️ NOTIFICA UI INSTANTANEAMENTE
      
      debugPrint('✅ [BlockService] Cache atualizado: ${blockerIds.length} me bloquearam');
    }, onError: (error) {
      final isPermissionDenied = error is FirebaseException && error.code == 'permission-denied';
      final isLoggedOut = fire_auth.FirebaseAuth.instance.currentUser == null;
      if (isPermissionDenied && isLoggedOut) {
        unawaited(reset());
        return;
      }

      debugPrint('❌ [BlockService] Erro no stream blockedMe: $error');
    });
    
    _isInitialized = true;
  }

  Future<void> reset() async {
    await _cancelSubscriptions();
    _blockedByMeCache.clear();
    _blockedMeCache.clear();
    _isInitialized = false;
    notifyListeners();
  }
  
  /// Libera recursos
  @override
  Future<void> dispose() async {
    await _cancelSubscriptions();
    _blockedByMeCache.clear();
    _blockedMeCache.clear();
    _isInitialized = false;
    await _authSubscription?.cancel();
    _authSubscription = null;
    super.dispose();
  }
  
  Future<void> _cancelSubscriptions() async {
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }

  // ==================== MÉTODOS RÁPIDOS (COM CACHE) ====================
  
  /// Verifica se existe bloqueio entre dois usuários (INSTANTÂNEO)
  /// 
  /// Usa cache em memória - **não faz query no Firestore**
  /// 
  /// Retorna true se:
  /// - uid1 bloqueou uid2 OU
  /// - uid2 bloqueou uid1
  bool isBlockedCached(String uid1, String uid2) {
    final blockedByMe = _blockedByMeCache[uid1]?.contains(uid2) ?? false;
    final blockedMe = _blockedMeCache[uid1]?.contains(uid2) ?? false;
    
    final result = blockedByMe || blockedMe;
    
    if (result) {
      debugPrint('🚫 [BlockService] isBlockedCached($uid1, $uid2) = TRUE (blockedByMe: $blockedByMe, blockedMe: $blockedMe)');
    }
    
    return result;
  }
  
  /// Verifica se uid1 bloqueou uid2 (INSTANTÂNEO)
  bool hasBlockedCached(String blockerId, String targetId) {
    return _blockedByMeCache[blockerId]?.contains(targetId) ?? false;
  }
  
  /// Retorna Set de todos os IDs bloqueados (bilateral)
  /// **Use isso para filtrar listas**
  Set<String> getAllBlockedIds(String userId) {
    final blockedByMe = _blockedByMeCache[userId] ?? {};
    final blockedMe = _blockedMeCache[userId] ?? {};
    
    return {...blockedByMe, ...blockedMe};
  }
  
  /// Filtra uma lista de IDs removendo bloqueados
  /// **Método helper super útil**
  List<String> filterBlockedIds(String currentUserId, List<String> userIds) {
    final blockedIds = getAllBlockedIds(currentUserId);
    return userIds.where((id) => !blockedIds.contains(id)).toList();
  }
  
  /// Filtra uma lista de objetos com userId
  /// **Funciona com qualquer model que tenha userId**
  List<T> filterBlocked<T>(
    String currentUserId,
    List<T> items,
    String Function(T) getUserId,
  ) {
    final blockedIds = getAllBlockedIds(currentUserId);
    return items.where((item) => !blockedIds.contains(getUserId(item))).toList();
  }

  // ==================== MÉTODOS DE MODIFICAÇÃO ====================

  /// Gera o ID do documento no formato {blockerId}_{targetId}
  String _generateDocId(String blockerId, String targetId) {
    return '${blockerId}_$targetId';
  }

  /// Bloqueia um usuário
  /// 
  /// [blockerId] - ID do usuário que está bloqueando
  /// [targetId] - ID do usuário que será bloqueado
  Future<void> blockUser(String blockerId, String targetId) async {
    debugPrint('🚫 [BlockService] Bloqueando $targetId');
    
    final docId = _generateDocId(blockerId, targetId);

    await _db.collection(_collection).doc(docId).set({
      'blockerId': blockerId,
      'targetId': targetId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    // Atualiza cache local imediatamente
    _blockedByMeCache[blockerId] ??= {};
    _blockedByMeCache[blockerId]!.add(targetId);
    
    // ⬅️ NOTIFICA TODAS AS TELAS INSTANTANEAMENTE
    notifyListeners();
    
    debugPrint('✅ [BlockService] Bloqueio efetivado + UI notificada');
  }

  /// Desbloqueia um usuário
  /// 
  /// [blockerId] - ID do usuário que está desbloqueando
  /// [targetId] - ID do usuário que será desbloqueado
  Future<void> unblockUser(String blockerId, String targetId) async {
    debugPrint('✅ [BlockService] Desbloqueando $targetId');
    
    final docId = _generateDocId(blockerId, targetId);
    await _db.collection(_collection).doc(docId).delete();
    
    // Atualiza cache local imediatamente
    _blockedByMeCache[blockerId]?.remove(targetId);
    
    // ⬅️ NOTIFICA TODAS AS TELAS INSTANTANEAMENTE
    notifyListeners();
    
    debugPrint('✅ [BlockService] Desbloqueio efetivado + UI notificada');
  }

  // ==================== MÉTODOS LEGACY (COM QUERY) ====================
  // Use apenas se o cache não estiver inicializado

  /// Verifica se existe bloqueio entre dois usuários (bilateral)
  /// **AVISO: Faz query no Firestore - use isBlockedCached() se possível**
  Future<bool> isBlocked(String uid1, String uid2) async {
    final doc1 = _generateDocId(uid1, uid2);
    final doc2 = _generateDocId(uid2, uid1);

    final result = await _db
        .collection(_collection)
        .where(FieldPath.documentId, whereIn: [doc1, doc2])
        .limit(1)
        .get();

    return result.docs.isNotEmpty;
  }

  /// Verifica se uid1 bloqueou uid2 (unilateral)
  /// **AVISO: Faz query no Firestore - use hasBlockedCached() se possível**
  Future<bool> hasBlocked(String blockerId, String targetId) async {
    final docId = _generateDocId(blockerId, targetId);
    final doc = await _db.collection(_collection).doc(docId).get();
    return doc.exists;
  }

  /// Lista todos os usuários bloqueados por um usuário
  Future<List<String>> getBlockedUsers(String blockerId) async {
    final result = await _db
        .collection(_collection)
        .where('blockerId', isEqualTo: blockerId)
        .get();

    return result.docs.map((doc) => doc.data()['targetId'] as String).toList();
  }

  /// Lista todos os usuários que bloquearam um usuário
  Future<List<String>> getBlockedByUsers(String targetId) async {
    final result = await _db
        .collection(_collection)
        .where('targetId', isEqualTo: targetId)
        .get();

    return result.docs.map((doc) => doc.data()['blockerId'] as String).toList();
  }

  /// Stream de usuários bloqueados (em tempo real)
  Stream<List<String>> watchBlockedUsers(String blockerId) {
    return _db
        .collection(_collection)
        .where('blockerId', isEqualTo: blockerId)
        .snapshots()
        .map((snapshot) => 
          snapshot.docs.map((doc) => doc.data()['targetId'] as String).toList()
        );
  }
}
