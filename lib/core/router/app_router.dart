import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:partiu/features/auth/presentation/screens/sign_in_screen_refactored.dart';
import 'package:partiu/features/auth/presentation/screens/signup_wizard_screen.dart';
import 'package:partiu/features/auth/presentation/screens/email_auth_screen.dart';
import 'package:partiu/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:partiu/features/auth/presentation/screens/email_verification_screen.dart';
import 'package:partiu/features/auth/presentation/screens/blocked_account_screen_router.dart';
import 'package:partiu/features/location/presentation/screens/update_location_screen_router.dart';
import 'package:partiu/features/home/presentation/screens/home_screen_refactored.dart';
import 'package:partiu/features/home/presentation/screens/splash_screen.dart';
import 'package:partiu/features/home/presentation/screens/advanced_filters_screen.dart';
import 'package:partiu/features/home/presentation/widgets/referral_debug_screen.dart';
import 'package:partiu/features/profile/presentation/screens/profile_screen_optimized.dart';
import 'package:partiu/features/profile/presentation/screens/profile_screen_router.dart';
import 'package:partiu/features/profile/presentation/screens/edit_profile_screen_advanced.dart';
import 'package:partiu/features/profile/presentation/screens/profile_visits_screen.dart';
import 'package:partiu/features/profile/presentation/screens/blocked_users_screen.dart';
import 'package:partiu/features/profile/presentation/screens/followers_screen.dart';
import 'package:partiu/features/events/presentation/screens/group_info/group_info_screen.dart';
import 'package:partiu/features/home/presentation/widgets/schedule_drawer.dart';
import 'package:partiu/features/home/presentation/screens/actions_tab.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/features/auth/presentation/widgets/signup_widgets.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/services/session_cleanup_service.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/services/auth_sync_service.dart';
import 'package:partiu/features/notifications/widgets/simplified_notification_screen_wrapper.dart';
import 'package:partiu/features/event_photo_feed/presentation/screens/event_photo_feed_screen.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/common/state/app_state.dart';

/// Rotas da aplicação
class AppRoutes {
  static const String signIn = '/sign-in';
  static const String emailAuth = '/email-auth';
  static const String emailVerification = '/email-verification';
  static const String forgotPassword = '/forgot-password';
  static const String signupWizard = '/signup-wizard';
  static const String signupSuccess = '/signup-success';
  static const String updateLocation = '/update-location';
  static const String home = '/home';
  static const String blocked = '/blocked';
  static const String profile = '/profile';
  static const String editProfile = '/edit-profile';
  static const String profileVisits = '/profile-visits';
  static const String followers = '/followers';
  static const String blockedUsers = '/blocked-users';
  static const String notifications = '/notifications';
  static const String advancedFilters = '/advanced-filters';
  static const String schedule = '/schedule';
  static const String groupInfo = '/group-info';
  static const String splash = '/splash';
  static const String referralDebug = '/referral-debug';
  static const String eventPhotoFeed = '/event-photo-feed';
  static const String actions = '/actions';
}

/// GlobalKey para acessar o Navigator root do app
/// Usado para navegação de push notifications quando o context não tem Navigator
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Cria o GoRouter com proteção baseada no AuthSyncService
GoRouter createAppRouter(BuildContext context) {
  debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  debugPrint('🛣️ createAppRouter() CHAMADO');
  debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  final authSync = Provider.of<AuthSyncService>(context, listen: false);

  return GoRouter(
    navigatorKey: rootNavigatorKey, // Usar GlobalKey para navegação externa
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    refreshListenable: authSync, // Ouve mudanças no AuthSyncService
    // Screen tracking feito via AnalyticsRouteTracker (sanitizado)
    // Não usar FirebaseGoRouterObserver aqui para evitar duplicação
    
    // Proteção de rotas baseada no AuthSyncService
    redirect: (context, state) {
      try {
        final currentPath = state.uri.path;
        final fullUri = state.uri.toString();

        // Tratamento de deep links (boora://)
        if (fullUri.startsWith('boora://')) {
          debugPrint('🔗 [GoRouter] Deep link detectado: $fullUri');
          
          // Deep link para main = home
          if (fullUri.contains('boora://main')) {
            debugPrint('🏠 [GoRouter] Redirecionando deep link main para /home');
            return AppRoutes.home;
          }
          
          // Outros deep links podem ser tratados aqui
          // Por padrão, redireciona para home
          debugPrint('🏠 [GoRouter] Deep link não específico, redirecionando para /home');
          return AppRoutes.home;
        }

        // Rotas públicas (não necessitam autenticação)
        // Importante: precisam permanecer acessíveis mesmo enquanto o AuthSyncService
        // ainda está sincronizando sessão (ex.: durante login social + checagem Firestore).
        final publicRoutes = [
          AppRoutes.signIn,
          AppRoutes.emailAuth,
          AppRoutes.emailVerification,
          AppRoutes.forgotPassword,
          AppRoutes.signupWizard,
          AppRoutes.signupSuccess,
          AppRoutes.splash,
        ];
        
        debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        debugPrint('🔀 [GoRouter] redirect CHAMADO');
        debugPrint('🔀 path: $currentPath');
        debugPrint('🔀 initialized: ${authSync.initialized}');
        debugPrint('🔀 isLoggedIn: ${authSync.isLoggedIn}');
        debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        
        // PROTEÇÃO: Se logout está em andamento, bloqueia navegação
        if (SessionCleanupService.isLoggingOut) {
          debugPrint('🚫 [GoRouter] Logout em andamento, bloqueando navegação');
          return null;
        }
        
        // Se ainda não inicializou, só força splash quando estiver saindo de rotas públicas.
        // Isso evita reiniciar o app no meio de um login (ex.: Google/Apple) e quebrar
        // o fluxo de navegação (callbacks com context desmontado).
        if (!authSync.initialized) {
          debugPrint('⏳ [GoRouter] Aguardando inicialização do AuthSyncService');
          
          // 🛡️ PROTEÇÃO: Se o usuário está logado no Firebase mas initialized é false,
          // e já está na home, permitir navegação para evitar loop infinito.
          // Isso pode acontecer quando o snapshot listener do Firestore demora a responder.
          if (currentPath == AppRoutes.home && authSync.firebaseUser != null) {
            debugPrint('⚠️ [GoRouter] FirebaseUser presente mas initialized=false na home - permitindo navegação para evitar loop');
            return null;
          }
          
          if (publicRoutes.contains(currentPath)) {
            return null;
          }
          return AppRoutes.splash;
        }
        
        debugPrint('✅ [GoRouter] AuthSyncService inicializado, processando redirect...');

        // 🚀 IMPORTANTE: Não redirecionar automaticamente do splash!
        // O SplashScreen faz o AppInitializerService.initialize() e 
        // navega manualmente para /home quando estiver pronto.
        // Isso evita que o usuário veja tela vazia enquanto carrega.
        if (currentPath == AppRoutes.splash) {
          debugPrint('📍 [GoRouter] Splash ativo - SplashScreen controla navegação');
          return null; // Deixa o SplashScreen controlar
        }
        
        final isLoggedIn = authSync.isLoggedIn;
        final isPublicRoute = publicRoutes.contains(currentPath);
        
        // Se não está logado e tenta acessar rota protegida
        if (!isLoggedIn && !isPublicRoute) {
          // Pode existir sessão Firebase válida enquanto o SessionManager ainda sincroniza.
          // Nessa janela, evitar redirecionar para login para não simular logout indevido.
          if (authSync.firebaseUser != null) {
            debugPrint('⏳ [GoRouter] Sessão Firebase ativa aguardando sincronização local, mantendo rota atual');
            return null;
          }

          debugPrint('🔒 [GoRouter] Usuário não logado, redirecionando para login');
          return AppRoutes.signIn;
        }
        
        // Se está logado mas tenta acessar rota de login
        if (isLoggedIn && currentPath == AppRoutes.signIn) {
          debugPrint('🏠 [GoRouter] Usuário logado tentando acessar login, redirecionando para home');
          return AppRoutes.home;
        }
        
        debugPrint('✅ [GoRouter] Sem redirecionamento necessário');
        return null; // Sem redirecionamento
      } catch (e) {
        debugPrint('❌ [GoRouter] Erro no redirect: $e');
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

    GoRoute(
      path: AppRoutes.eventPhotoFeed,
      name: 'eventPhotoFeed',
      builder: (context, state) => const EventPhotoFeedScreen(),
    ),
    
    GoRoute(
      path: AppRoutes.actions,
      name: 'actions',
      builder: (context, state) => const ActionsTab(),
    ),
    
    // Tela de Email/Senha Auth
    GoRoute(
      path: AppRoutes.emailAuth,
      name: 'emailAuth',
      builder: (context, state) => const EmailAuthScreen(),
    ),

    // Tela de Verificação de E-mail
    GoRoute(
      path: AppRoutes.emailVerification,
      name: 'emailVerification',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final emailFromExtra = extra?['email'] as String?;
        final emailFromQuery = state.uri.queryParameters['email'];

        return EmailVerificationScreen(
          email: emailFromExtra ?? emailFromQuery,
        );
      },
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
    
    // Home (agora aponta para SplashScreen para inicialização)
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) {
        // Suporte a deep linking para abas específicas: /home?tab=1
        final tabParam = state.uri.queryParameters['tab'];
        final initialIndex = tabParam != null ? int.tryParse(tabParam) ?? 0 : 0;
        
        return HomeScreenRefactored(initialIndex: initialIndex);
      },
    ),

    // Splash Screen
    GoRoute(
      path: AppRoutes.splash,
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
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
        
        // Se extra é null (ex: hot reload ou deep link), mostra tela de loading que busca os dados
        if (extra == null) {
          final cachedUser = ProfileScreenRouter.getCachedUser(userId);
          final currentUserId = AppState.currentUserId;
          debugPrint('🔍 [AppRouter] Profile: extra é null, verificando cache para userId=$userId');
          debugPrint('🔍 [AppRouter] Profile: cachedUser=${cachedUser != null}, currentUserId=$currentUserId');
          if (cachedUser != null && currentUserId != null && currentUserId.isNotEmpty) {
            debugPrint('✅ [AppRouter] Profile: usando cache para userId=$userId');
            return ProfileScreenOptimized(
              user: cachedUser,
              currentUserId: currentUserId,
            );
          }

          debugPrint('⚠️ [AppRouter] Profile: extra é null para userId=$userId, usando fallback');
          return _ProfileFallbackLoader(userId: userId);
        }
        
        final user = extra['user'] as User;
        final currentUserId = extra['currentUserId'] as String;
        
        // Cacheia o usuário para reconstruções futuras (ex: refresh do GoRouter)
        ProfileScreenRouter.cacheUser(user);
        debugPrint('💾 [AppRouter] Profile: cacheando user ${user.userId}');
        
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
    
    // Profile Visits
    GoRoute(
      path: AppRoutes.profileVisits,
      name: 'profileVisits',
      builder: (context, state) => const ProfileVisitsScreen(),
    ),

    // Followers / Following
    GoRoute(
      path: AppRoutes.followers,
      name: 'followers',
      builder: (context, state) => const FollowersScreen(),
    ),
    
    // Blocked Users
    GoRoute(
      path: AppRoutes.blockedUsers,
      name: 'blockedUsers',
      builder: (context, state) => const BlockedUsersScreen(),
    ),
    
    // Notifications
    GoRoute(
      path: AppRoutes.notifications,
      name: 'notifications',
      builder: (context, state) => const SimplifiedNotificationScreenWrapper(),
    ),
    
    // Advanced Filters
    GoRoute(
      path: AppRoutes.advancedFilters,
      name: 'advancedFilters',
      builder: (context, state) => const AdvancedFiltersScreen(),
    ),
    
    // Schedule
    GoRoute(
      path: AppRoutes.schedule,
      name: 'schedule',
      builder: (context, state) => const ScheduleDrawer(),
    ),
    
    // Referral Debug (apenas para desenvolvimento)
    GoRoute(
      path: AppRoutes.referralDebug,
      name: 'referralDebug',
      builder: (context, state) => const ReferralDebugScreen(),
    ),
    
    // Group Info
    GoRoute(
      path: '${AppRoutes.groupInfo}/:eventId',
      name: 'groupInfo',
      builder: (context, state) {
        final eventId = state.pathParameters['eventId'];
        
        if (eventId == null) {
          return Scaffold(
            body: Center(
              child: Text(AppLocalizations.of(context).translate('event_not_found')),
            ),
          );
        }
        
        return GroupInfoScreen(eventId: eventId);
      },
    ),
  ],
  
  // Tratamento de erro
  errorBuilder: (context, state) {
      final uri = state.uri.toString();
      
      // Se for um deep link (boora://), redireciona para home
      if (uri.contains('boora://') || uri.contains('boora%3A')) {
        debugPrint('🔗 [GoRouter errorBuilder] Deep link detectado: $uri');
        // Usa WidgetsBinding para navegar após o frame atual
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            context.go(AppRoutes.home);
          }
        });
        // Retorna um scaffold vazio enquanto redireciona
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      }
      
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('${AppLocalizations.of(context).translate('error')}: ${state.error}'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.signIn),
                child: Text(AppLocalizations.of(context).translate('back_to_sign_in')),
              ),
            ],
          ),
        ),
      );
    },
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

/// Fallback loader para quando o profile é acessado sem extra (deep link, hot reload)
class _ProfileFallbackLoader extends StatefulWidget {
  const _ProfileFallbackLoader({required this.userId});
  
  final String userId;

  @override
  State<_ProfileFallbackLoader> createState() => _ProfileFallbackLoaderState();
}

class _ProfileFallbackLoaderState extends State<_ProfileFallbackLoader> {
  User? _user;
  String? _currentUserId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    debugPrint('🔄 [ProfileFallback] Carregando dados para userId=${widget.userId}');
    try {
      final currentUserId = AppState.currentUserId;
      if (currentUserId == null || currentUserId.isEmpty) {
        setState(() {
          _error = 'user_not_authenticated';
          _loading = false;
        });
        return;
      }

      // Import inline para evitar dependência circular
      final userRepository = UserRepository();
      final userData = await userRepository.getUserById(widget.userId);
      
      if (userData == null) {
        debugPrint('❌ [ProfileFallback] Usuário não encontrado: ${widget.userId}');
        setState(() {
          _error = 'profile_data_not_found';
          _loading = false;
        });
        return;
      }

      final normalized = <String, dynamic>{
        ...userData,
        'userId': widget.userId,
      };
      
      debugPrint('✅ [ProfileFallback] Dados carregados para ${widget.userId}');
      setState(() {
        _user = User.fromDocument(normalized);
        _currentUserId = currentUserId;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ [ProfileFallback] Erro ao carregar: $e');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => context.pop(),
          ),
          title: Text(
            i18n.translate('profile'),
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Ícone
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_off_outlined,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 24),
                // Título
                Text(
                  i18n.translate('profile_not_available'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // Descrição
                Text(
                  i18n.translate('profile_not_available_description'),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Botão
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Text(i18n.translate('go_back')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ProfileScreenOptimized(
      user: _user!,
      currentUserId: _currentUserId!,
    );
  }
}
