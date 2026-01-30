import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/event_photo_feed/domain/services/event_photo_likes_cache_service.dart';

class EventPhotoLikeService {
  EventPhotoLikeService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    EventPhotoLikesCacheService? likesCache,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _likesCache = likesCache;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  EventPhotoLikesCacheService? _likesCache;

  /// Injeta o cache service (chamado pelo provider)
  void setLikesCache(EventPhotoLikesCacheService cache) {
    _likesCache = cache;
  }

  CollectionReference<Map<String, dynamic>> get _photos => _firestore.collection('EventPhotos');

  /// Verifica se o usuário curtiu uma foto (cache-first)
  /// 
  /// Consulta o cache local primeiro. Se não encontrar, faz fallback
  /// para o Stream do Firestore (comportamento legado).
  /// 
  /// **Otimização:** Use `isLikedSync()` quando possível para evitar
  /// o overhead de criar um Stream.
  Stream<int> watchLikesCount(String photoId) {
    return _photos.doc(photoId).snapshots().map((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      return (data['likesCount'] as num?)?.toInt() ?? 0;
    });
  }

  /// [DEPRECATED] Usa Stream realtime - caro em escala!
  /// Prefira usar `isLikedSync()` ou `isLikedFromCache()`.
  /// 
  /// Mantido para compatibilidade com código legado.
  @Deprecated('Use isLikedSync() ou isLikedFromCache() para evitar N+1 queries')
  Stream<bool> watchIsLiked(String photoId) {
    // Se temos cache, retorna valor do cache como Stream único
    if (_likesCache != null) {
      final isLiked = _likesCache!.isLiked(photoId);
      debugPrint('📦 [EventPhotoLikeService.watchIsLiked] Cache hit para $photoId: $isLiked');
      return Stream<bool>.value(isLiked);
    }

    // Fallback para comportamento legado (caro!)
    debugPrint('⚠️ [EventPhotoLikeService.watchIsLiked] Cache miss, usando Stream realtime para $photoId');
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return Stream<bool>.value(false);
    }

    return _photos
        .doc(photoId)
        .collection('likes')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists);
  }

  /// Verifica se o usuário curtiu uma foto (síncrono, cache-only)
  /// 
  /// **Recomendado** para uso no feed. Retorna resultado instantâneo
  /// do cache local sem nenhuma chamada de rede.
  /// 
  /// Retorna `false` se o cache não estiver disponível.
  bool isLikedSync(String photoId) {
    if (_likesCache == null) {
      debugPrint('⚠️ [EventPhotoLikeService.isLikedSync] Cache não disponível');
      return false;
    }
    return _likesCache!.isLiked(photoId);
  }

  /// Verifica se múltiplas fotos foram curtidas (batch, cache-only)
  /// 
  /// Retorna `Map<photoId, isLiked>` para uso eficiente no feed.
  Map<String, bool> areLikedSync(List<String> photoIds) {
    if (_likesCache == null) {
      return {for (final id in photoIds) id: false};
    }
    return _likesCache!.areLiked(photoIds);
  }

  /// Toggle like com atualização otimista do cache
  /// 
  /// Fluxo:
  /// 1. Atualiza cache local imediatamente (UI instantâneo)
  /// 2. Persiste no Firestore em background
  /// 3. Se falhar, reverte o cache
  Future<bool> toggleLike({
    required String photoId,
    required bool currentlyLiked,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      final i18n = await AppLocalizations.loadForLanguageCode(AppLocalizations.currentLocale);
      throw Exception(i18n.translate('user_not_authenticated'));
    }

    // 1. Atualização otimista do cache
    final nextLiked = !currentlyLiked;
    if (_likesCache != null) {
      if (nextLiked) {
        await _likesCache!.addLike(photoId);
      } else {
        await _likesCache!.removeLike(photoId);
      }
    }

    final photoRef = _photos.doc(photoId);
    final likeRef = photoRef.collection('likes').doc(uid);

    try {
      // 2. Persiste no Firestore
      return await _firestore.runTransaction((tx) async {
        final snap = await tx.get(photoRef);
        final data = snap.data() ?? const <String, dynamic>{};
        final currentCount = (data['likesCount'] as num?)?.toInt() ?? 0;

        if (currentlyLiked) {
          tx.delete(likeRef);
          tx.update(photoRef, {
            'likesCount': currentCount > 0 ? currentCount - 1 : 0,
          });
          return false;
        }

        tx.set(likeRef, {
          'userId': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.set(photoRef, {
          'likesCount': currentCount + 1,
        }, SetOptions(merge: true));

        return true;
      });
    } catch (e) {
      // 3. Reverte cache em caso de erro
      debugPrint('❌ [EventPhotoLikeService.toggleLike] Erro, revertendo cache: $e');
      if (_likesCache != null) {
        if (currentlyLiked) {
          await _likesCache!.addLike(photoId);
        } else {
          await _likesCache!.removeLike(photoId);
        }
      }
      rethrow;
    }
  }
}
