import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:partiu/core/services/cache/avatar_cache_service.dart';
import 'package:partiu/core/services/cache/image_caches.dart';

/// Estado do avatar
enum AvatarState { loading, loaded, empty }

/// Entry com estado e provider
class AvatarEntry {
  AvatarEntry({required this.state, required this.provider});

  final AvatarState state;
  final ImageProvider provider;
}

/// Store simplificado para avatares com cache reativo
class AvatarStore {
  AvatarStore._internal();
  static final AvatarStore instance = AvatarStore._internal();

  // Cache de notifiers
  final Map<String, ValueNotifier<AvatarEntry>> _avatarNotifiers = {};
  static const AssetImage _emptyImage = AssetImage('assets/images/empty_avatar.jpg');
  
  // Cache de listeners do Firestore para evitar duplicatas
  final Map<String, StreamSubscription<DocumentSnapshot>> _firebaseListeners = {};

  /// Obtém notifier com estado (loading/loaded/empty)
  ValueNotifier<AvatarEntry> getAvatarEntryNotifier(String userId) {
    if (!_avatarNotifiers.containsKey(userId)) {
      _avatarNotifiers[userId] = ValueNotifier<AvatarEntry>(
        AvatarEntry(
          state: AvatarState.loading,
          provider: _emptyImage,
        ),
      );
      
      // Carregar avatar real do Firebase/Storage
      _loadAvatar(userId);
    }
    return _avatarNotifiers[userId]!;
  }

  /// Carrega avatar do usuário do Firestore
  Future<void> _loadAvatar(String userId) async {
    if (userId.trim().isEmpty) return;
    
    // Verificar cache primeiro
    final cachedUrl = AvatarCacheService.instance.getAvatarUrl(userId);
    if (cachedUrl != null && cachedUrl.isNotEmpty) {
      _updateAvatar(userId, cachedUrl);
      return;
    }
    
    // Evitar listeners duplicados
    if (_firebaseListeners.containsKey(userId)) {
      return;
    }
    
    // Escutar mudanças em tempo real do Firestore
    _firebaseListeners[userId] = FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!snapshot.exists || snapshot.data() == null) {
              _setEmptyAvatar(userId);
              return;
            }
            
            final data = snapshot.data()!;
            // Campo oficial: photoUrl
            // ⚠️ FILTRAR URLs do Google OAuth (dados legados)
            var rawPhotoUrl = data['photoUrl'] as String? ?? '';
            if (rawPhotoUrl.contains('googleusercontent.com') || 
                rawPhotoUrl.contains('lh3.google')) {
              rawPhotoUrl = '';
            }
            final photoUrl = rawPhotoUrl;
            
            if (photoUrl.isEmpty) {
              _setEmptyAvatar(userId);
            } else {
              // Atualizar cache
              AvatarCacheService.instance.updateAvatar(userId, photoUrl);
              _updateAvatar(userId, photoUrl);
            }
          },
          onError: (error) {
            _setEmptyAvatar(userId);
          },
        );
  }
  
  /// Atualiza avatar com nova URL
  void _updateAvatar(String userId, String imageUrl) {
    if (!_avatarNotifiers.containsKey(userId)) return;
    
    // ✅ Evita NetworkImage cru (cache só em memória). Vamos sempre para o
    // cache em disco via CachedNetworkImageProvider + cache manager.
    final provider = CachedNetworkImageProvider(
      imageUrl,
      cacheManager: AvatarImageCache.instance,
      // Cache key estável por URL. Se a URL for versionada (recomendado),
      // isso vira "immutable" na prática.
      cacheKey: imageUrl,
    );
    _avatarNotifiers[userId]!.value = AvatarEntry(
      state: AvatarState.loaded,
      provider: provider,
    );
  }
  
  /// Define avatar como vazio
  void _setEmptyAvatar(String userId) {
    if (!_avatarNotifiers.containsKey(userId)) return;
    
    _avatarNotifiers[userId]!.value = AvatarEntry(
      state: AvatarState.empty,
      provider: _emptyImage,
    );
  }

  /// Pré-carrega avatar com URL conhecida do cache
  void preloadAvatar(String userId, String imageUrl) {
    if (userId.trim().isEmpty || imageUrl.isEmpty) return;
    
    // Atualizar cache
    AvatarCacheService.instance.updateAvatar(userId, imageUrl);
    
    // Criar notifier se não existir e atualizar
    if (!_avatarNotifiers.containsKey(userId)) {
      _avatarNotifiers[userId] = ValueNotifier<AvatarEntry>(
        AvatarEntry(
          state: AvatarState.loading,
          provider: _emptyImage,
        ),
      );
    }
    
    _updateAvatar(userId, imageUrl);
    
    // Iniciar listener do Firestore se ainda não existe
    if (!_firebaseListeners.containsKey(userId)) {
      _loadAvatar(userId);
    }
  }
  
  /// Invalida e recarrega avatar de um usuário
  /// Use quando o usuário atualizar sua foto de perfil
  void invalidateAndReload(String userId) {
    if (userId.trim().isEmpty) return;
    
    // Limpar cache
    AvatarCacheService.instance.invalidateAvatar(userId);
    
    // Definir como loading
    if (_avatarNotifiers.containsKey(userId)) {
      _avatarNotifiers[userId]!.value = AvatarEntry(
        state: AvatarState.loading,
        provider: _emptyImage,
      );
    }
    
    // Cancelar listener antigo
    _firebaseListeners[userId]?.cancel();
    _firebaseListeners.remove(userId);
    
    // Recarregar
    _loadAvatar(userId);
  }

  /// Limpa cache e cancela todos os listeners
  void dispose() {
    for (final notifier in _avatarNotifiers.values) {
      notifier.dispose();
    }
    _avatarNotifiers.clear();
    
    for (final listener in _firebaseListeners.values) {
      listener.cancel();
    }
    _firebaseListeners.clear();
    
    AvatarCacheService.instance.clearAll();
  }
  
  /// Cancela listener de um usuário específico
  void cancelListener(String userId) {
    _firebaseListeners[userId]?.cancel();
    _firebaseListeners.remove(userId);
  }
}
