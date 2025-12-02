import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:partiu/features/auth/presentation/screens/sign_in_screen_refactored.dart';
import 'package:partiu/features/auth/presentation/screens/signup_wizard_screen.dart';
import 'package:partiu/features/auth/presentation/screens/email_auth_screen.dart';
import 'package:partiu/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:partiu/features/auth/presentation/screens/blocked_account_screen_router.dart';
import 'package:partiu/features/location/presentation/screens/update_location_screen_router.dart';
import 'package:partiu/features/home/presentation/screens/home_screen_refactored.dart';
import 'package:partiu/features/profile/presentation/screens/profile_screen_optimized.dart';
import 'package:partiu/features/profile/presentation/screens/edit_profile_screen_advanced.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/features/auth/presentation/widgets/signup_widgets.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/services/auth_sync_service.dart';
import 'package:partiu/features/notifications/widgets/simplified_notification_screen_wrapper.dart';

/// Rotas da aplicação
class AppRoutes {
  static const String signIn = '/sign-in';
  static const String emailAuth = '/email-auth';
  static const String forgotPassword = '/forgot-password';
  static const String signupWizard = '/signup-wizard';
  static const String signupSuccess = '/signup-success';
  static const String updateLocation = '/update-location';
  static const String home = '/home';
  static const String blocked = '/blocked';
  static const String profile = '/profile';
  static const String editProfile = '/edit-profile';
  static const String notifications = '/notifications';
}

/// Cria o GoRouter com proteção baseada no AuthSyncService
GoRouter createAppRouter(BuildContext context) {
  return GoRouter(
    initialLocation: AppRoutes.signIn,
    debugLogDiagnostics: true,
    
    // Proteção de rotas baseada no AuthSyncService
    redirect: (context, state) {
      try {
        final authSync = Provider.of<AuthSyncService>(context, listen: false);
        final currentPath = state.uri.path;
        
        debugPrint('GoRouter redirect: path=$currentPath, initialized=${authSync.initialized}, isLoggedIn=${authSync.isLoggedIn}');
        
        // Se ainda não inicializou, não navegar (aguardar)
        if (!authSync.initialized) {
          debugPrint('GoRouter: Aguardando inicialização do AuthSyncService');
          return null; // Bloqueia navegação até inicializar
        }
        
        // Rotas públicas (não necessitam autenticação)
        final publicRoutes = [
          AppRoutes.signIn,
          AppRoutes.emailAuth,
          AppRoutes.forgotPassword,
          AppRoutes.signupWizard,
          AppRoutes.signupSuccess,
        ];
        
        final isLoggedIn = authSync.isLoggedIn;
        final isPublicRoute = publicRoutes.contains(currentPath);
        
        // Se não está logado e tenta acessar rota protegida
        if (!isLoggedIn && !isPublicRoute) {
          debugPrint('GoRouter: Usuário não logado, redirecionando para login');
          return AppRoutes.signIn;
        }
        
        // Se está logado mas tenta acessar rota de login
        if (isLoggedIn && currentPath == AppRoutes.signIn) {
          debugPrint('GoRouter: Usuário logado tentando acessar login, redirecionando para home');
          return AppRoutes.home;
        }
        
        debugPrint('GoRouter: Sem redirecionamento necessário');
        return null; // Sem redirecionamento
      } catch (e) {
        debugPrint('GoRouter: Erro no redirect: $e');
        return null;
      }
    },
    
    routes: [
    // Tela de Login
    GoRoute(
      path: AppRoutes.signIn,
      name: 'signIn',
      builder: (context, state) => const SignInScreenRefactored(),
    ),
    
    // Tela de Email/Senha Auth
    GoRoute(
      path: AppRoutes.emailAuth,
      name: 'emailAuth',
      builder: (context, state) => const EmailAuthScreen(),
    ),
    
    // Tela de Recuperação de Senha
    GoRoute(
      path: AppRoutes.forgotPassword,
      name: 'forgotPassword',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    
    // Wizard de Cadastro
    GoRoute(
      path: AppRoutes.signupWizard,
      name: 'signupWizard',
      builder: (context, state) => const SignupWizardScreen(),
    ),
    
    // Tela de Sucesso após Cadastro
    GoRoute(
      path: AppRoutes.signupSuccess,
      name: 'signupSuccess',
      builder: (context, state) => const SignupSuccessScreen(),
    ),
    
    // Atualização de Localização
    GoRoute(
      path: AppRoutes.updateLocation,
      name: 'updateLocation',
      builder: (context, state) => const UpdateLocationScreenRouter(),
    ),
    
    // Home
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const HomeScreenRefactored(),
    ),
    
    // Blocked Account
    GoRoute(
      path: AppRoutes.blocked,
      name: 'blocked',
      builder: (context, state) => const BlockedAccountScreenRouter(),
    ),
    
    // Profile
    GoRoute(
      path: '${AppRoutes.profile}/:id',
      name: 'profile',
      builder: (context, state) {
        final userId = state.pathParameters['id'];
        
        if (userId == null) {
          return Scaffold(
            body: Center(
              child: Text(AppLocalizations.of(context).translate('profile_id_not_found')),
            ),
          );
        }
        
        final extra = state.extra as Map<String, dynamic>?;
        if (extra == null) {
          return Scaffold(
            body: Center(
              child: Text(AppLocalizations.of(context).translate('profile_data_not_found')),
            ),
          );
        }
        
        final user = extra['user'] as User;
        final currentUserId = extra['currentUserId'] as String;
        
        return ProfileScreenOptimized(
          user: user,
          currentUserId: currentUserId,
        );
      },
    ),
    
    // Edit Profile
    GoRoute(
      path: AppRoutes.editProfile,
      name: 'editProfile',
      builder: (context, state) => const EditProfileScreen(),
    ),
    
    // Notifications
    GoRoute(
      path: AppRoutes.notifications,
      name: 'notifications',
      builder: (context, state) => const SimplifiedNotificationScreenWrapper(),
    ),
  ],
  
  // Tratamento de erro
  errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Erro: ${state.error}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.signIn),
              child: const Text('Voltar ao Login'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Tela de sucesso após cadastro
class SignupSuccessScreen extends StatelessWidget {
  const SignupSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            const Expanded(child: SignupSuccessWidget()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: GlimpseButton(
                text: AppLocalizations.of(context).translate('continue'),
                onTap: () {
                  // Navega para atualização de localização e remove histórico
                  context.go(AppRoutes.updateLocation);
                },
                backgroundColor: GlimpseColors.primaryColorLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
