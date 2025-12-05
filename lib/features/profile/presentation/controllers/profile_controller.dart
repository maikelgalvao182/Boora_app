import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/models/review_model.dart';
import 'package:partiu/core/models/review_stats_model.dart';
import 'package:partiu/shared/stores/user_store.dart';

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
              if (snapshot.exists && snapshot.data() != null) {
                profile.value = User.fromDocument(snapshot.data()!);
                error.value = null;
              } else {
                error.value = 'Usuário não encontrado';
              }
              isLoading.value = false;
            },
            onError: (e) {
              error.value = 'Erro ao carregar perfil: $e';
              isLoading.value = false;
            },
          );

      // Carrega reviews
      await _loadReviews(targetUserId);
    } catch (e) {
      error.value = 'Erro ao carregar perfil: $e';
      isLoading.value = false;
    }
  }

  /// Carrega reviews do usuário
  Future<void> _loadReviews(String targetUserId) async {
    try {
      debugPrint('🔍 [ProfileController] Iniciando carregamento de reviews para usuário: ${targetUserId.substring(0, 8)}...');
      
      _reviewsSubscription = _firestore
          .collection('Reviews')
          .where('revieweeId', isEqualTo: targetUserId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .listen(
        (snapshot) {
          debugPrint('✅ [ProfileController] Reviews carregadas: ${snapshot.docs.length} documentos');
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
        onError: (error) {
          debugPrint('❌ [ProfileController] Erro no stream de reviews: $error');
          if (error.toString().contains('failed-precondition')) {
            debugPrint('⚠️  [ProfileController] Índice necessário: https://console.firebase.google.com');
          }
          if (error.toString().contains('permission-denied')) {
            debugPrint('⚠️  [ProfileController] Permissão negada - possível logout em andamento');
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('❌ [ProfileController] Erro ao configurar listener de reviews: $e');
    }
  }

  /// Refresh manual
  Future<void> refresh(String targetUserId) async {
    await load(targetUserId);
  }

  /// Registra visita ao perfil
  Future<void> registerVisit(String currentUserId) async {
    if (currentUserId.isEmpty || currentUserId == userId) {
      debugPrint('⏭️  [ProfileController] Visita não registrada: ${currentUserId.isEmpty ? "userId vazio" : "próprio perfil"}');
      return; // Não registra visita no próprio perfil
    }

    try {
      debugPrint('📝 [ProfileController] Registrando visita: ${currentUserId.substring(0, 8)}... → ${userId.substring(0, 8)}...');
      
      await _firestore.collection('Visits').add({
        'visitorId': currentUserId,
        'visitedUserId': userId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'profile',
      });
      
      debugPrint('✅ [ProfileController] Visita registrada com sucesso');
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        debugPrint('⚠️  [ProfileController] Permissão negada ao registrar visita - usuário pode estar deslogado');
      } else {
        debugPrint('❌ [ProfileController] Erro ao registrar visita: $e');
      }
    }
  }

  /// Verifica se é o próprio perfil
  bool isMyProfile(String currentUserId) {
    return userId == currentUserId;
  }

  /// Libera recursos
  void release() {
    debugPrint('🧹 [ProfileController] Liberando recursos do controller');
    _profileSubscription?.cancel();
    _reviewsSubscription?.cancel();
    profile.dispose();
    isLoading.dispose();
    error.dispose();
    reviews.dispose();
    reviewStats.dispose();
    debugPrint('✅ [ProfileController] Recursos liberados');
  }
}
