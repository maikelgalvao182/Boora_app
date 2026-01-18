import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/models/review_model.dart';
import 'package:partiu/core/models/review_stats_model.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/features/profile/data/services/profile_visits_service.dart';

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
  Future<void> load(String targetUserId) async {
    if (_isReleased) return;
    isLoading.value = true;
    error.value = null;

    try {
      // Inicia listener do perfil
      _profileSubscription = _firestore
          .collection('Users')
          .doc(targetUserId)
          .snapshots()
          .listen(
            (snapshot) {
              if (_isReleased) return;
              if (snapshot.exists && snapshot.data() != null) {
                profile.value = User.fromDocument(snapshot.data()!);
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

      // Carrega reviews
      await _loadReviews(targetUserId);
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
  Future<void> refresh(String targetUserId) async {
    await load(targetUserId);
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
