import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:partiu/firebase_options.dart';
import 'package:partiu/core/config/dependency_provider.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/managers/session_manager.dart';
import 'package:partiu/core/services/cache/cache_manager.dart';
import 'package:partiu/core/services/google_maps_initializer.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/services/auth_sync_service.dart';
import 'package:partiu/core/services/location_service.dart';
import 'package:partiu/core/services/location_background_updater.dart'; // LocationSyncScheduler
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/subscription/providers/simple_subscription_provider.dart';
import 'package:brazilian_locations/brazilian_locations.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/people_ranking_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/ranking_viewmodel.dart';
import 'package:partiu/features/notifications/services/push_notification_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Travar orientação em portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  
  // Inicializar BrazilianLocations
  await BrazilianLocations.initialize();
  
  // Configurar locales para timeago
  timeago.setLocaleMessages('pt', timeago.PtBrMessages());
  timeago.setLocaleMessages('es', timeago.EsMessages());
  
  // Inicializar Firebase (protegido contra hot reload)
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Firebase já inicializado: $e');
  }

  // 🔔 Inicializar Push Notification Manager (ANTES do runApp)
  await PushNotificationManager.instance.initialize();
  debugPrint('✅ PushNotificationManager iniciado');

  // Inicializar Google Maps
  await GoogleMapsInitializer.initialize();

  // Inicializar SessionManager
  await SessionManager.instance.initialize();

  // Inicializar CacheManager
  CacheManager.instance.initialize();

  // Inicializar Service Locator
  final serviceLocator = ServiceLocator();
  await serviceLocator.init();

  // Inicializar LocationSyncScheduler para atualização automática de localização
  // Isso mantém o Firestore atualizado a cada 10 minutos automaticamente
  final locationService = serviceLocator.get<LocationService>();
  LocationSyncScheduler.start(
    locationService,
    config: LocationConfig.standard, // Usar configuração padrão (Uber/Tinder)
  );
  debugPrint('✅ LocationSyncScheduler iniciado');

  runApp(
    MultiProvider(
      providers: [
        // AuthSyncService como singleton - ÚNICA fonte de verdade para auth
        ChangeNotifierProvider(
          create: (_) => AuthSyncService(),
        ),
        // MapViewModel
        ChangeNotifierProvider(
          create: (_) => MapViewModel(),
        ),
        // PeopleRankingViewModel
        ChangeNotifierProvider(
          create: (_) => PeopleRankingViewModel(),
        ),
        // RankingViewModel (Locations)
        ChangeNotifierProvider(
          create: (_) => RankingViewModel(),
        ),
        // ConversationsViewModel - gerencia estado das conversas
        ChangeNotifierProvider(
          create: (_) => ConversationsViewModel(),
        ),
        // SimpleSubscriptionProvider - gerencia estado de assinaturas VIP
        ChangeNotifierProvider(
          create: (_) => SimpleSubscriptionProvider(),
        ),
        // DependencyProvider via Provider para compatibility
        Provider<ServiceLocator>.value(
          value: serviceLocator,
        ),
      ],
      child: DependencyProvider(
        serviceLocator: serviceLocator,
        child: const AppRoot(),
      ),
    ),
  );
  
  // 🔔 Processar mensagem inicial (se app foi aberto via notificação)
  // Deve ser APÓS runApp para ter contexto de navegação disponível
  PushNotificationManager.instance.handleInitialMessageAfterRunApp();
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🏗️ AppRoot.build() CHAMADO - Construindo MaterialApp');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    // Cria goRouter com acesso ao AuthSyncService via context
    debugPrint('📊 [AppRoot] Criando router...');
    final router = createAppRouter(context);
    debugPrint('✅ [AppRoot] Router criado');
    
    debugPrint('📊 [AppRoot] Construindo MaterialApp.router...');
    return MaterialApp.router(
      title: APP_NAME,
      debugShowCheckedModeBanner: false,
      
      // Configuração de rotas com go_router protegido por AuthSyncService
      routerConfig: router,
        
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
      locale: const Locale('pt', 'BR'), // Idioma padrão
      
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
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
