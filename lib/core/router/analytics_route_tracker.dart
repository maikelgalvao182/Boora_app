import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:go_router/go_router.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// Tracker de rotas para Firebase Analytics e Crashlytics
/// 
/// Diferente do NavigatorObserver, este tracker:
/// - Usa routeInformationProvider para capturar mudanças de rota
/// - Sanitiza os paths removendo IDs dinâmicos (:id, :eventId)
/// - Evita vazamento de dados sensíveis para o Analytics
/// - Mantém nomes de tela estáveis para melhor análise no GA4
/// - Registra breadcrumbs no Crashlytics para debug de crashes
/// 
/// Exemplo:
/// - /profile/abc123 → 'profile'
/// - /group-info/event456 → 'groupInfo'
/// - /home?tab=1 → 'home'
class AnalyticsRouteTracker {
  AnalyticsRouteTracker(this.router, this.analytics) {
    _lastLocation = router.routeInformationProvider.value.uri.toString();
    router.routeInformationProvider.addListener(_onRouteChanged);
    AppLogger.info('AnalyticsRouteTracker inicializado', tag: 'ANALYTICS');
  }

  final GoRouter router;
  final FirebaseAnalytics analytics;
  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;
  String? _lastLocation;

  /// Libera o listener
  void dispose() {
    router.routeInformationProvider.removeListener(_onRouteChanged);
    AppLogger.info('AnalyticsRouteTracker disposed', tag: 'ANALYTICS');
  }

  /// Callback quando a rota muda
  void _onRouteChanged() {
    final loc = router.routeInformationProvider.value.uri.toString();
    
    // Evita logar a mesma rota duas vezes
    if (loc == _lastLocation) return;
    _lastLocation = loc;

    final uri = Uri.parse(loc);
    final screenName = _screenNameFromUri(uri);

    // Firebase Analytics - screen view
    analytics.logScreenView(
      screenName: screenName,
      screenClass: 'GoRouter',
    );
    
    // Crashlytics - breadcrumb para debug de crashes
    // Permite ver "qual tela o usuário estava" antes do crash
    _crashlytics.log('Screen: $screenName');
    _crashlytics.setCustomKey('last_screen', screenName);
    
    AppLogger.debug('📊 [Analytics] Screen: $screenName (path: ${uri.path})', tag: 'ANALYTICS');
  }

  /// Converte URI para nome de tela sanitizado
  /// 
  /// Remove IDs dinâmicos e query params para manter
  /// cardinalidade baixa no GA4
  String _screenNameFromUri(Uri uri) {
    final p = uri.path;

    // Rotas simples (sem parâmetros dinâmicos)
    if (p == AppRoutes.home) return 'home';
    if (p == AppRoutes.signIn) return 'signIn';
    if (p == AppRoutes.emailAuth) return 'emailAuth';
    if (p == AppRoutes.emailVerification) return 'emailVerification';
    if (p == AppRoutes.forgotPassword) return 'forgotPassword';
    if (p == AppRoutes.signupWizard) return 'signupWizard';
    if (p == AppRoutes.signupSuccess) return 'signupSuccess';
    if (p == AppRoutes.updateLocation) return 'updateLocation';
    if (p == AppRoutes.splash) return 'splash';
    if (p == AppRoutes.blocked) return 'blocked';
    if (p == AppRoutes.editProfile) return 'editProfile';
    if (p == AppRoutes.profileVisits) return 'profileVisits';
    if (p == AppRoutes.blockedUsers) return 'blockedUsers';
    if (p == AppRoutes.notifications) return 'notifications';
    if (p == AppRoutes.advancedFilters) return 'advancedFilters';
    if (p == AppRoutes.schedule) return 'schedule';
    if (p == AppRoutes.referralDebug) return 'referralDebug';
    if (p == AppRoutes.eventPhotoFeed) return 'eventPhotoFeed';

    // Rotas com parâmetros dinâmicos - sanitiza removendo o ID
    if (p.startsWith('${AppRoutes.profile}/')) return 'profile';
    if (p.startsWith('${AppRoutes.groupInfo}/')) return 'groupInfo';

    // Fallback: sanitiza IDs numéricos e alfanuméricos
    // /something/abc123def → /something/:id
    return p
        .replaceAll(RegExp(r'/[a-zA-Z0-9]{20,}'), '/:id') // Firebase UIDs (20+ chars)
        .replaceAll(RegExp(r'/\d+'), '/:id'); // IDs numéricos
  }
}
