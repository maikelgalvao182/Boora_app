import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:partiu/core/services/auth_sync_service.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/reviews/presentation/services/pending_reviews_checker_service.dart';

/// Widget que protege telas que necessitam de usuário autenticado.
/// Mostra loader enquanto aguarda inicialização completa do AuthSyncService.
/// Após autenticação, verifica automaticamente se há pending reviews.
class AuthProtectedWrapper extends StatefulWidget {
  final Widget child;
  final bool checkPendingReviews;
  
  const AuthProtectedWrapper({
    super.key,
    required this.child,
    this.checkPendingReviews = true,
  });

  @override
  State<AuthProtectedWrapper> createState() => _AuthProtectedWrapperState();
}

class _AuthProtectedWrapperState extends State<AuthProtectedWrapper> {
  bool _hasCheckedPendingReviews = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthSyncService>(
      builder: (context, authSync, _) {
        // Se ainda não inicializou ou não está logado, mostra loader
        if (!authSync.initialized || !authSync.isLoggedIn) {
          // Reset flag quando usuário desloga
          _hasCheckedPendingReviews = false;
          
          return Scaffold(
            backgroundColor: Colors.white,
            body: const Center(
              child: CupertinoActivityIndicator(
                radius: 16,
                color: GlimpseColors.primaryColorLight,
              ),
            ),
          );
        }

        // Usuário autenticado - verifica pending reviews uma vez
        // DESABILITADO: ReviewDialog deve ser aberto apenas via ReviewCard
        // if (widget.checkPendingReviews && !_hasCheckedPendingReviews) {
        //   _hasCheckedPendingReviews = true;
        //   
        //   // Agenda verificação após o frame atual
        //   WidgetsBinding.instance.addPostFrameCallback((_) {
        //     if (mounted) {
        //       PendingReviewsCheckerService()
        //           .checkAndShowPendingReviews(context);
        //     }
        //   });
        // }

        // Usuário autenticado - mostra tela protegida
        return widget.child;
      },
    );
  }
}