import 'dart:async';
import 'package:flutter/material.dart';
import 'package:partiu/features/profile/data/repositories/follow_repository.dart';

class FollowController extends ValueNotifier<bool> {
  final String myUid;
  final String targetUid;
  final FollowRepository _repository = FollowRepository();
  StreamSubscription<bool>? _subscription;
  bool _disposed = false;
  bool _firstStreamEmission = true;
  
  final ValueNotifier<bool> isLoading = ValueNotifier(false);

  FollowController({required this.myUid, required this.targetUid}) : super(false) {
    debugPrint('🔗 [FollowController] Criado: hashCode=$hashCode, myUid=$myUid, targetUid=$targetUid');
    _init();
  }

  void _init() {
    debugPrint('🔗 [FollowController] _init: Escutando stream isFollowing');
    _subscription = _repository.isFollowing(myUid, targetUid).listen(
      (isFollowing) {
        debugPrint('🔗 [FollowController] Stream emitiu: isFollowing=$isFollowing, firstEmission=$_firstStreamEmission, currentValue=$value');
        _firstStreamEmission = false;
        // Use scheduleMicrotask to avoid "setState during build" errors if stream emits synchronously
        Future.microtask(() {
          if (!_disposed) {
            // Só atualiza se o valor realmente mudou
            if (value != isFollowing) {
              debugPrint('🔗 [FollowController] Atualizando value: $value -> $isFollowing');
              value = isFollowing;
            } else {
              debugPrint('🔗 [FollowController] Valor já é $isFollowing, ignorando');
            }
          }
        });
      },
      onError: (e) {
        debugPrint('❌ [FollowController] Erro no stream: $e');
      },
    );
  }

  @override
  void dispose() {
    debugPrint('🔗 [FollowController] dispose() chamado');
    _disposed = true;
    _subscription?.cancel();
    isLoading.dispose();
    super.dispose();
  }

  Future<void> toggleFollow() async {
    debugPrint('🔗 [FollowController] toggleFollow() chamado. Atual: $value, Loading: ${isLoading.value}');
    
    if (isLoading.value) {
      debugPrint('🔗 [FollowController] Já está carregando, ignorando');
      return;
    }
    
    final previousValue = value;
    // Optimistic update para reação instantânea
    value = !previousValue;

    isLoading.value = true;
    debugPrint('🔗 [FollowController] isLoading = true');
    
    try {
      if (!previousValue) {
        debugPrint('🔗 [FollowController] Chamando followUser($targetUid)...');
        await _repository.followUser(targetUid);
        debugPrint('🔗 [FollowController] followUser concluído com sucesso');
      } else {
        debugPrint('🔗 [FollowController] Chamando unfollowUser($targetUid)...');
        await _repository.unfollowUser(targetUid);
        debugPrint('🔗 [FollowController] unfollowUser concluído com sucesso');
      }
    } catch (e, stack) {
      debugPrint('❌ [FollowController] Erro em toggleFollow: $e');
      debugPrint('❌ [FollowController] Stack: $stack');
      // Rollback em caso de erro
      if (!_disposed) {
        value = previousValue;
      }
      rethrow; 
    } finally {
      if (!_disposed) {
        isLoading.value = false;
        debugPrint('🔗 [FollowController] isLoading = false');
      }
    }
  }
}
