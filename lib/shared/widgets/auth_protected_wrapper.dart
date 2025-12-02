import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:partiu/core/services/auth_sync_service.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Widget que protege telas que necessitam de usuário autenticado.
/// Mostra loader enquanto aguarda inicialização completa do AuthSyncService.
class AuthProtectedWrapper extends StatelessWidget {
  final Widget child;
  final String? loadingMessage;
  
  const AuthProtectedWrapper({
    super.key,
    required this.child,
    this.loadingMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthSyncService>(
      builder: (context, authSync, _) {
        // Se ainda não inicializou ou não está logado, mostra loader
        if (!authSync.initialized || !authSync.isLoggedIn) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  if (loadingMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      loadingMessage!,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        // Usuário autenticado - mostra tela protegida
        return child;
      },
    );
  }
}