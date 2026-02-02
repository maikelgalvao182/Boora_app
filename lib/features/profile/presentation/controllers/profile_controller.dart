import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/models/review_model.dart';
import 'package:partiu/core/models/review_stats_model.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/features/profile/data/services/profile_visits_service.dart';
import 'package:partiu/features/profile/data/services/profile_static_cache_service.dart';
import 'package:partiu/features/profile/data/services/profile_gallery_cache_service.dart';

/// Controller MVVM para tela de perfil
/// 
/// Responsabilidades:
/// - Carrega dados do usuário do Firestore
/// - Gerencia estado de loading/error
/// - Integra com UserStore para dados reativos
/// - Carrega reviews e estatísticas
class ProfileController {
  ProfileController({required this.userId, User? initialUser}) {
    if (initialUser != null) {
      profile.value = initialUser;
    }
  }

  final String userId;

  // State
  final ValueNotifier<User?> profile = ValueNotifier(null);
  final ValueNotifier<bool> isLoading = ValueNotifier(false);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<List<Review>> reviews = ValueNotifier([]);
  final ValueNotifier<ReviewStats?> reviewStats = ValueNotifier(null);

  StreamSubscription<DocumentSnapshot>? _profileSubscription;
  StreamSubscription<QuerySnapshot>? _reviewsSubscription;

  bool _isReleased = false;

  final _firestore = FirebaseFirestore.instance;
  final ProfileStaticCacheService _profileCache = ProfileStaticCacheService.instance;
  final ProfileGalleryCacheService _galleryCache = ProfileGalleryCacheService.instance;

  /// Avatar URL reativo (via UserStore)
  ValueNotifier<String> get avatarUrl {
    final notifier = ValueNotifier<String>('');
    
    // Obtém URL diretamente do UserStore
    final url = UserStore.instance.getAvatarUrl(userId);
    if (url != null && url.isNotEmpty) {
      notifier.value = url;
    }
    
    return notifier;
  }

  /// Carrega dados do perfil
  ///
  /// [useStream]: quando true, mantém listener realtime no Users/{uid}.
  /// [includeReviews]: quando true, abre stream de reviews.
  Future<void> load(
    String targetUserId, {
    bool useStream = true,
    bool includeReviews = true,
  }) async {
    // 🔒 Stream hard-disabled para reduzir custo (galeria está no doc Users)
    useStream = false;
    if (_isReleased) return;
    isLoading.value = true;
    error.value = null;

    try {
      // Cancela listeners antigos para evitar duplicação
      _profileSubscription?.cancel();
      _profileSubscription = null;

      if (useStream) {
        // Inicia listener do perfil
        _profileSubscription = _firestore
            .collection('Users')
            .doc(targetUserId)
            .snapshots()
            .listen(
              (snapshot) {
                if (_isReleased) return;
                debugPrint('📊 [ProfileController] Stream emitiu snapshot para userId: $targetUserId');
                if (snapshot.exists && snapshot.data() != null) {
                  final data = snapshot.data()!;
                  debugPrint('📊 [ProfileController] Dados mudaram - followersCount: ${data['followersCount']}, followingCount: ${data['followingCount']}');
                  profile.value = User.fromDocument(data);
                  error.value = null;
                } else {
                  error.value = 'Usuário não encontrado';
                }
                isLoading.value = false;
              },
              onError: (e, stack) {
                if (_isReleased) return;
                // Em logout, o Firestore pode disparar permission-denied em streams ativos.
                // Guardamos para não tentar atualizar notifiers já descartados.
                error.value = 'Erro ao carregar perfil: $e';
                isLoading.value = false;
                AppLogger.error(
                  'Erro no stream do perfil',
                  tag: 'ProfileController',
                  error: e,
                  stackTrace: stack,
                );
              },
            );
      } else {
        await _profileCache.ensureInitialized();
        await _galleryCache.ensureInitialized();
        final cached = _profileCache.get(targetUserId);
        if (cached != null && profile.value == null) {
          final cachedUser = User.fromDocument(cached);
          profile.value = _hydrateGalleryFromCache(cachedUser);
          isLoading.value = false;
        }

        final snapshot = await _firestore
            .collection('Users')
            .doc(targetUserId)
            .get();

        if (_isReleased) return;
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data()!;
          final freshUser = User.fromDocument(data);
          profile.value = freshUser;
          error.value = null;
          await _profileCache.put(targetUserId, data);
          await _cacheGalleryFromUser(freshUser);
        } else {
          error.value = 'Usuário não encontrado';
        }
        isLoading.value = false;
      }

      if (includeReviews) {
        await _loadReviews(targetUserId);
      } else {
        _reviewsSubscription?.cancel();
        _reviewsSubscription = null;
      }
    } catch (e, stack) {
      if (_isReleased) return;
      error.value = 'Erro ao carregar perfil: $e';
      isLoading.value = false;
      AppLogger.error(
        'Erro ao carregar perfil',
        tag: 'ProfileController',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Carrega reviews do usuário
  Future<void> _loadReviews(String targetUserId) async {
    try {
      AppLogger.info(
        'Iniciando carregamento de reviews para usuário: ${targetUserId.substring(0, 8)}...',
        tag: 'ProfileController',
      );
      
      _reviewsSubscription = _firestore
          .collection('Reviews')
          .where('reviewee_id', isEqualTo: targetUserId) // FIXADO: era 'revieweeId' (camelCase)
          .orderBy('created_at', descending: true) // FIXADO: era 'createdAt' (camelCase)
          .limit(50)
          .snapshots()
          .listen(
        (snapshot) {
          if (_isReleased) return;
          AppLogger.info(
            'Reviews carregadas: ${snapshot.docs.length} documentos',
            tag: 'ProfileController',
          );
          final loadedReviews = snapshot.docs
              .map((doc) => Review.fromFirestore(doc.data(), doc.id))
              .toList();

          reviews.value = loadedReviews;

          // Calcula estatísticas
          if (loadedReviews.isNotEmpty) {
            final reviewData = snapshot.docs.map((doc) => doc.data()).toList();
            reviewStats.value = ReviewStats.fromReviews(reviewData);
          } else {
            reviewStats.value = const ReviewStats(
              totalReviews: 0,
              overallRating: 0.0,
            );
          }
        },
        onError: (e, stack) {
          if (_isReleased) return;

          final errorText = e.toString();
          AppLogger.error(
            'Erro no stream de reviews',
            tag: 'ProfileController',
            error: e,
            stackTrace: stack,
          );

          if (errorText.contains('failed-precondition')) {
            AppLogger.warning(
              'Índice necessário para query de reviews (Firestore)',
              tag: 'ProfileController',
            );
          }

          if (errorText.contains('permission-denied')) {
            // Pode acontecer durante logout; não quebra a UI.
            AppLogger.warning(
              'Permissão negada no stream de reviews (possível logout em andamento)',
              tag: 'ProfileController',
            );
          }
        },
        cancelOnError: true,
      );
    } catch (e, stack) {
      if (_isReleased) return;
      AppLogger.error(
        'Erro ao configurar listener de reviews',
        tag: 'ProfileController',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Refresh manual
  Future<void> refresh(
    String targetUserId, {
    bool useStream = true,
    bool includeReviews = true,
  }) async {
    await load(
      targetUserId,
      useStream: useStream,
      includeReviews: includeReviews,
    );
  }

  /// Registra visita ao perfil usando ProfileVisitsService
  /// 
  /// Features:
  /// - Anti-spam: 15min cooldown entre visitas
  /// - TTL: 7 dias de expiração automática
  /// - Incrementa visitCount em visitas repetidas
  Future<void> registerVisit(String currentUserId) async {
    if (currentUserId.isEmpty || currentUserId == userId) {
      AppLogger.info(
        'Visita não registrada: ${currentUserId.isEmpty ? "userId vazio" : "próprio perfil"}',
        tag: 'ProfileController',
      );
      return; // Não registra visita no próprio perfil
    }

    try {
      if (_isReleased) return;
      AppLogger.info(
        'Registrando visita: ${currentUserId.substring(0, 8)}... → ${userId.substring(0, 8)}...',
        tag: 'ProfileController',
      );
      
      await ProfileVisitsService.instance.recordVisit(
        visitedUserId: userId,
      );
      
      if (_isReleased) return;
      AppLogger.success('Visita registrada com sucesso', tag: 'ProfileController');
    } catch (e, stack) {
      if (_isReleased) return;
      AppLogger.error(
        'Erro ao registrar visita',
        tag: 'ProfileController',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Verifica se é o próprio perfil
  bool isMyProfile(String currentUserId) {
    return userId == currentUserId;
  }

  Future<void> _cacheGalleryFromUser(User user) async {
    if (user.userId.isEmpty) return;
    final urls = _extractGalleryUrls(user.userGallery);
    if (urls.isEmpty) return;
    await _galleryCache.putPage(user.userId, 0, urls);
  }

  User _hydrateGalleryFromCache(User user) {
    final gallery = user.userGallery;
    final hasGallery = gallery != null && gallery.isNotEmpty;
    if (hasGallery) return user;

    final cachedUrls = _galleryCache.getPage(user.userId, 0);
    if (cachedUrls == null || cachedUrls.isEmpty) return user;

    final hydratedGallery = <String, dynamic>{};
    for (var i = 0; i < cachedUrls.length; i++) {
      hydratedGallery['${i + 1}'] = cachedUrls[i];
    }

    return user.copyWith(userGallery: hydratedGallery);
  }

  List<String> _extractGalleryUrls(Map<String, dynamic>? gallery) {
    if (gallery == null || gallery.isEmpty) return const <String>[];

    final entries = gallery.entries.where((e) => e.value != null).toList();
    entries.sort((a, b) {
      int parseKey(String k) {
        final numPart = RegExp(r'(\d+)').firstMatch(k)?.group(1);
        return int.tryParse(numPart ?? k) ?? 0;
      }
      return parseKey(a.key).compareTo(parseKey(b.key));
    });

    final urls = <String>[];
    for (final entry in entries) {
      final value = entry.value;
      final url = value is Map ? (value['url'] ?? '').toString() : value.toString();
      if (url.trim().isNotEmpty) {
        urls.add(url.trim());
      }
    }

    if (urls.isEmpty) return urls;
    final seen = <String>{};
    final unique = <String>[];
    for (final url in urls) {
      if (seen.add(url)) unique.add(url);
    }
    return unique;
  }

  /// Libera recursos
  void release() {
    if (_isReleased) return;
    _isReleased = true;
    AppLogger.info('Liberando recursos do controller', tag: 'ProfileController');
    _profileSubscription?.cancel();
    _reviewsSubscription?.cancel();
    profile.dispose();
    isLoading.dispose();
    error.dispose();
    reviews.dispose();
    reviewStats.dispose();
    AppLogger.success('Recursos liberados', tag: 'ProfileController');
  }
}
