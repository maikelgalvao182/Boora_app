import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:provider/provider.dart' as provider;
import 'package:partiu/firebase_options.dart';
import 'package:partiu/core/config/dependency_provider.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/controllers/locale_controller.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/core/managers/session_manager.dart';
import 'package:partiu/core/services/cache/cache_manager.dart';
import 'package:partiu/core/services/google_maps_initializer.dart';
import 'package:partiu/core/services/analytics_service.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/router/analytics_route_tracker.dart';
import 'package:partiu/core/services/auth_sync_service.dart';
// LocationSyncScheduler agora é inicializado pelo AuthSyncService após login.
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/subscription/providers/simple_subscription_provider.dart';
// import 'package:brazilian_locations/brazilian_locations.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/people_ranking_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/ranking_viewmodel.dart';
import 'package:partiu/features/notifications/services/push_notification_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:partiu/core/services/cache/hive_initializer.dart';

bool _shouldSuppressPermissionDeniedAfterLogout(Object error) {
  if (FirebaseAuth.instance.currentUser != null) return false;
  if (error is FirebaseException) {
    final isFirestore = error.plugin == 'cloud_firestore' || (error.message?.contains('cloud_firestore') == true);
    final isPermissionDenied = error.code == 'permission-denied' || (error.message?.contains('permission-denied') == true);
    return isFirestore && isPermissionDenied;
  }
  return false;
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 📦 Inicializar Hive (cache persistente) - não bloqueia se falhar
    unawaited(HiveInitializer.initialize());

    // Inicializar Firebase primeiro (necessário para Crashlytics)
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } catch (e) {
      debugPrint('Firebase já inicializado: $e');
    }

    // Captura erros do Flutter framework e envia para Crashlytics
    FlutterError.onError = (FlutterErrorDetails details) {
      final exception = details.exception;
      final stack = details.stack ?? StackTrace.current;

      if (_shouldSuppressPermissionDeniedAfterLogout(exception)) {
        AppLogger.warning(
          'Suprimindo cloud_firestore/permission-denied após logout (erro global)',
          tag: 'AUTH',
        );
        return;
      }

      // Registra no Crashlytics (usando recordFlutterError para não marcar tudo como fatal)
      FirebaseCrashlytics.instance.recordFlutterError(details);

      FlutterError.presentError(details);
      AppLogger.error(
        'Unhandled Flutter error',
        tag: 'APP',
        error: exception,
        stackTrace: stack,
      );
    };

    // Captura erros assíncronos da plataforma
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      if (_shouldSuppressPermissionDeniedAfterLogout(error)) {
        AppLogger.warning(
          'Suprimindo cloud_firestore/permission-denied após logout (PlatformDispatcher)',
          tag: 'AUTH',
        );
        return true;
      }

      // Registra no Crashlytics
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);

      AppLogger.error(
        'Unhandled async error',
        tag: 'APP',
        error: error,
        stackTrace: stack,
      );
      return false;
    };
  
    // Travar orientação em portrait
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    
    // Configurar locales para timeago
    timeago.setLocaleMessages('pt', timeago.PtBrMessages());
    timeago.setLocaleMessages('es', timeago.EsMessages());

    // Inicializar CacheManager
    CacheManager.instance.initialize();

    // Inicializar Service Locator
    final serviceLocator = ServiceLocator();

    // 🌍 LocaleController (duas camadas):
    // - null => segue idioma do sistema
    // - Locale => override manual persistido
    final localeController = LocaleController();

    // NOTA: LocationSyncScheduler agora é iniciado dentro do AuthSyncService
    // após o login bem-sucedido, não mais aqui no main.dart

    runApp(
      ProviderScope(
  child: provider.MultiProvider(
          providers: [
            provider.ChangeNotifierProvider.value(
              value: localeController,
            ),
            // AuthSyncService como singleton - ÚNICA fonte de verdade para auth
            provider.ChangeNotifierProvider(
              create: (_) => AuthSyncService(),
            ),
            // MapViewModel
            provider.ChangeNotifierProvider(
              create: (_) => MapViewModel(),
            ),
            // PeopleRankingViewModel
            provider.ChangeNotifierProvider(
              create: (_) => PeopleRankingViewModel(),
            ),
            // RankingViewModel (Locations)
            provider.ChangeNotifierProvider(
              create: (_) => RankingViewModel(),
            ),
            // ConversationsViewModel - gerencia estado das conversas
            provider.ChangeNotifierProvider(
              create: (_) => ConversationsViewModel(),
            ),
            // SimpleSubscriptionProvider - gerencia estado de assinaturas VIP
            provider.ChangeNotifierProvider(
              create: (_) => SimpleSubscriptionProvider(),
            ),
            // DependencyProvider via Provider para compatibility
            provider.Provider<ServiceLocator>.value(
              value: serviceLocator,
            ),
          ],
          child: DependencyProvider(
            serviceLocator: serviceLocator,
            child: AppBootstrap(
              serviceLocator: serviceLocator,
              localeController: localeController,
              child: const AppRoot(),
            ),
          ),
        ),
      ),
    );
  }, (Object error, StackTrace stack) {
    if (_shouldSuppressPermissionDeniedAfterLogout(error)) {
      AppLogger.warning(
        'Suprimindo cloud_firestore/permission-denied após logout (zone)',
        tag: 'AUTH',
      );
      return;
    }

    // Registra no Crashlytics
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);

    AppLogger.error(
      'Uncaught zoned error',
      tag: 'APP',
      error: error,
      stackTrace: stack,
    );
  });
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    required this.serviceLocator,
    required this.localeController,
    required this.child,
  });

  final ServiceLocator serviceLocator;
  final LocaleController localeController;
  final Widget child;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _didBootstrap = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_didBootstrap) return;
      _didBootstrap = true;
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    try {
      await Future.wait([
        AnalyticsService.instance.initialize(),
        PushNotificationManager.instance.initialize(),
        GoogleMapsInitializer.initialize(),
        SessionManager.instance.initialize(),
        widget.serviceLocator.init(),
        widget.localeController.load(),
      ]);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await AnalyticsService.instance.setUserId(currentUser.uid);
        debugPrint('📊 Analytics userId setado: ${currentUser.uid}');
      }

      // 🔔 Processar mensagem inicial (se app foi aberto via notificação)
      // Deve ser APÓS o bootstrap para garantir inicialização do push
      PushNotificationManager.instance.handleInitialMessageAfterRunApp();
    } catch (error, stack) {
      AppLogger.error(
        'Falha no bootstrap pós-primeiro-frame',
        tag: 'APP',
        error: error,
        stackTrace: stack,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // ✅ Quando app volta do background, verifica se há notificação pendente
      debugPrint('🔄 [AppRoot] App resumed - verificando payload pendente...');
      PushNotificationManager.instance.checkPendingNotificationPayload();
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🏗️ AppRoot.build() CHAMADO - Construindo MaterialApp');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    // Cria goRouter com acesso ao AuthSyncService via context
    debugPrint('📊 [AppRoot] Criando router...');
    final router = createAppRouter(context);
    debugPrint('✅ [AppRoot] Router criado');

    // Inicializa o tracker de analytics com sanitização de rotas
    // ignore: unused_local_variable
    final analyticsTracker = AnalyticsRouteTracker(router, FirebaseAnalytics.instance);
    
    debugPrint('📊 [AppRoot] Construindo MaterialApp.router...');

    final localeController = context.watch<LocaleController>();

    return MaterialApp.router(
      title: APP_NAME,
      debugShowCheckedModeBanner: false,
      
      // Configuração de rotas com go_router protegido por AuthSyncService
      routerConfig: router,
      
      // Builder para setar o contexto no PushNotificationManager
      builder: (context, child) {
        // Setar contexto para navegação de notificações push
        // Isso garante que o contexto tenha acesso aos Providers
        WidgetsBinding.instance.addPostFrameCallback((_) {
          PushNotificationManager.instance.setAppContext(context);
        });
        return child ?? const SizedBox.shrink();
      },
        
      // Configuração de localização
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        CountrySelectorLocalization.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'), // Português
        Locale('en', 'US'), // Inglês
        Locale('es', 'ES'), // Espanhol
      ],
      locale: localeController.locale, // null => segue sistema
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        // Se o usuário escolheu manualmente, `locale` não é null.
        // Aqui resolve apenas quando segue o idioma do sistema.
        if (deviceLocale == null) return supportedLocales.first;

        final deviceLang = deviceLocale.languageCode.toLowerCase();
        for (final l in supportedLocales) {
          if (l.languageCode.toLowerCase() == deviceLang) return l;
        }
        return supportedLocales.first; // fallback consistente (pt)
      },
      
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        fontFamily: FONT_PLUS_JAKARTA_SANS,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0, // Remove efeito cinza ao rolar
          surfaceTintColor: Colors.transparent, // Remove overlay Material 3
        ),
      ),
    );
  }
}
