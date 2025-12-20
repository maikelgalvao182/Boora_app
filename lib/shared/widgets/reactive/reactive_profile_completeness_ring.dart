import 'package:flutter/material.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/features/profile/data/services/profile_completeness_prompt_service.dart';
import 'package:partiu/shared/widgets/profile_completeness_ring.dart';

/// 🎯 Anel de completude de perfil reativo com atualização em TEMPO REAL
/// 
/// Observa mudanças no documento do Firestore via Stream e recalcula
/// automaticamente o percentual de completude quando o perfil é atualizado.
/// 
/// Features:
/// - ✅ Atualização em tempo real via Firestore Streams
/// - ✅ Recalcula percentual automaticamente quando campos são preenchidos
/// - ✅ Otimizado para evitar rebuilds desnecessários
/// - ✅ Fallback para 0% se usuário não estiver logado
/// 
/// Usage:
/// ```dart
/// ReactiveProfileCompletenessRing(
///   size: 100,
///   child: StableAvatar(...),
/// )
/// 
/// // Com customização
/// ReactiveProfileCompletenessRing(
///   size: 120,
///   strokeWidth: 4,
///   child: StableAvatar(...),
/// )
/// ```
class ReactiveProfileCompletenessRing extends StatelessWidget {
  const ReactiveProfileCompletenessRing({
    required this.size,
    required this.child,
    this.strokeWidth = 4.0,
    this.showBadge = true,
    super.key,
  });

  final double size;
  final Widget child;
  final double strokeWidth;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: AppState.currentUser,
      builder: (context, user, _) {
        if (user == null || user.userId.isEmpty) {
          // Sem usuário logado - mostra anel vazio
          return ProfileCompletenessRing(
            size: size,
            strokeWidth: strokeWidth,
            percentage: 0,
            showBadge: showBadge,
            child: child,
          );
        }
        
        // 🎯 REATIVO: Observa mudanças no Firestore em tempo real
        return StreamBuilder<int>(
          stream: ProfileCompletenessPromptService.instance.watchCompleteness(user.userId),
          initialData: 0,
          builder: (context, snapshot) {
            final percentage = snapshot.data ?? 0;
            
            return ProfileCompletenessRing(
              size: size,
              strokeWidth: strokeWidth,
              percentage: percentage,
              showBadge: showBadge,
              child: child,
            );
          },
        );
      },
    );
  }
}
