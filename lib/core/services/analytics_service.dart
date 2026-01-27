import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// Serviço centralizado de Analytics e Crashlytics
/// 
/// Responsabilidades:
/// - Rastrear eventos do usuário (DAU, tempo de sessão, etc.)
/// - Capturar erros para Crashlytics
/// - Gerenciar lifecycle do app para métricas de engajamento
/// 
/// Eventos rastreados:
/// - app_session_start: Quando o usuário abre o app
/// - app_session_end: Quando o app vai para background (com duração)
/// - sign_up: Quando cria conta
/// - login: Quando faz login
/// - screen_view: Quando navega entre telas
class AnalyticsService with WidgetsBindingObserver {
  AnalyticsService._();
  static final AnalyticsService _instance = AnalyticsService._();
  static AnalyticsService get instance => _instance;

  /// Instância do Firebase Analytics
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Instância do Firebase Crashlytics
  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  /// Timestamp de quando o app entrou em foreground
  DateTime? _foregroundAt;

  /// Flag para evitar session_start duplicado na mesma sessão
  bool _sentSessionStart = false;

  /// Flag para evitar inicialização dupla
  bool _isInitialized = false;

  /// Inicializa o serviço de analytics
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Habilita coleta de analytics (desabilitar em debug se necessário)
      await _analytics.setAnalyticsCollectionEnabled(!kDebugMode);

      // Configura Crashlytics
      await _crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

      // Registra observer de lifecycle
      WidgetsBinding.instance.addObserver(this);

      _isInitialized = true;
      AppLogger.info('AnalyticsService inicializado', tag: 'ANALYTICS');
    } catch (e, stack) {
      AppLogger.error(
        'Erro ao inicializar AnalyticsService',
        tag: 'ANALYTICS',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Libera recursos
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  // ========== LIFECYCLE EVENTS ==========

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _onAppPaused();
        break;
      default:
        break;
    }
  }

  void _onAppResumed() {
    _foregroundAt = DateTime.now();
    
    // Evita session_start duplicado (ex: resumed após inactive)
    if (!_sentSessionStart) {
      logEvent('app_session_start');
      _sentSessionStart = true;
      AppLogger.debug('📊 Session started', tag: 'ANALYTICS');
    }
  }

  void _onAppPaused() {
    final started = _foregroundAt;
    if (started != null) {
      final durationSeconds = DateTime.now().difference(started).inSeconds;
      logEvent('app_session_end', parameters: {
        'duration_sec': durationSeconds,
      });
      AppLogger.debug('📊 Session ended: ${durationSeconds}s', tag: 'ANALYTICS');
    }
    _foregroundAt = null;
    _sentSessionStart = false;
  }

  // ========== USER EVENTS ==========

  /// Loga evento de signup
  /// 
  /// [method] - Método de signup: 'email', 'google', 'apple'
  Future<void> logSignUp({required String method}) async {
    try {
      await _analytics.logSignUp(signUpMethod: method);
      AppLogger.debug('📊 SignUp logged: $method', tag: 'ANALYTICS');
    } catch (e) {
      AppLogger.warning('Erro ao logar signup: $e', tag: 'ANALYTICS');
    }
  }

  /// Loga evento de login
  /// 
  /// [method] - Método de login: 'email', 'google', 'apple'
  Future<void> logLogin({required String method}) async {
    try {
      await _analytics.logLogin(loginMethod: method);
      AppLogger.debug('📊 Login logged: $method', tag: 'ANALYTICS');
    } catch (e) {
      AppLogger.warning('Erro ao logar login: $e', tag: 'ANALYTICS');
    }
  }

  /// Define o ID do usuário para analytics
  Future<void> setUserId(String? userId) async {
    try {
      await _analytics.setUserId(id: userId);
      await _crashlytics.setUserIdentifier(userId ?? '');
      AppLogger.debug('📊 User ID set: $userId', tag: 'ANALYTICS');
    } catch (e) {
      AppLogger.warning('Erro ao setar userId: $e', tag: 'ANALYTICS');
    }
  }

  /// Define propriedade do usuário
  Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    try {
      await _analytics.setUserProperty(name: name, value: value);
      if (value != null) {
        await _crashlytics.setCustomKey(name, value);
      }
    } catch (e) {
      AppLogger.warning('Erro ao setar user property: $e', tag: 'ANALYTICS');
    }
  }

  // ========== SCREEN TRACKING ==========

  /// Loga visualização de tela
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    try {
      await _analytics.logScreenView(
        screenName: screenName,
        screenClass: screenClass,
      );
    } catch (e) {
      AppLogger.warning('Erro ao logar screen view: $e', tag: 'ANALYTICS');
    }
  }

  // ========== CUSTOM EVENTS ==========

  /// Loga evento customizado
  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    try {
      await _analytics.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (e) {
      AppLogger.warning('Erro ao logar evento $name: $e', tag: 'ANALYTICS');
    }
  }

  /// Loga criação de evento
  Future<void> logEventCreated({
    required String eventId,
    required String category,
    required String emoji,
  }) async {
    await logEvent('event_created', parameters: {
      'event_id': eventId,
      'category': category,
      'emoji': emoji,
    });
  }

  /// Loga participação em evento
  Future<void> logEventJoined({
    required String eventId,
    required String category,
  }) async {
    await logEvent('event_joined', parameters: {
      'event_id': eventId,
      'category': category,
    });
  }

  /// Loga envio de mensagem no chat
  Future<void> logMessageSent({
    required String eventId,
    required bool isGroupChat,
  }) async {
    await logEvent('message_sent', parameters: {
      'event_id': eventId,
      'is_group_chat': isGroupChat,
    });
  }

  /// Loga compra de assinatura VIP
  Future<void> logVipPurchase({
    required String plan,
    required double price,
    required String currency,
  }) async {
    await logEvent('vip_purchase', parameters: {
      'plan': plan,
      'price': price,
      'currency': currency,
    });
  }

  // ========== ERROR TRACKING ==========

  /// Registra erro no Crashlytics
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    try {
      await _crashlytics.recordError(
        exception,
        stack,
        reason: reason,
        fatal: fatal,
      );
    } catch (e) {
      AppLogger.warning('Erro ao registrar crash: $e', tag: 'ANALYTICS');
    }
  }

  /// Registra erro do Flutter framework (não marca como fatal por padrão)
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    try {
      await _crashlytics.recordFlutterError(details);
    } catch (e) {
      AppLogger.warning('Erro ao registrar Flutter error: $e', tag: 'ANALYTICS');
    }
  }

  /// Adiciona log ao Crashlytics (para contexto)
  Future<void> log(String message) async {
    try {
      await _crashlytics.log(message);
    } catch (e) {
      // Silencioso
    }
  }

  // ========== DEBUG / TESTING ==========

  /// Força um crash de teste para validar o Crashlytics
  /// ⚠️ USAR APENAS EM DEBUG PARA VALIDAÇÃO
  /// 
  /// Após chamar, o crash deve aparecer no Firebase Console em ~5 minutos
  void forceCrashForTesting() {
    AppLogger.warning('⚠️ Forçando crash de teste...', tag: 'ANALYTICS');
    _crashlytics.crash();
  }

  /// Envia um erro não-fatal de teste
  Future<void> sendTestError() async {
    await recordError(
      Exception('Teste de erro não-fatal - pode ignorar'),
      StackTrace.current,
      reason: 'Teste de validação do Crashlytics',
      fatal: false,
    );
    AppLogger.info('✅ Erro de teste enviado ao Crashlytics', tag: 'ANALYTICS');
  }

  /// Habilita modo debug do Analytics (eventos aparecem em tempo real no DebugView)
  /// 
  /// Para iOS: rode no terminal antes de buildar:
  /// ```
  /// flutter run --dart-define=DEBUG_ANALYTICS=true
  /// ```
  /// 
  /// Para Android, rode:
  /// ```
  /// adb shell setprop debug.firebase.analytics.app com.maikelgalvao.partiu
  /// ```
  Future<void> enableDebugMode() async {
    // No Android, o debug mode é habilitado via adb
    // No iOS, é habilitado via -FIRDebugEnabled
    AppLogger.info(
      '📊 Para ver eventos em tempo real:\n'
      '   Android: adb shell setprop debug.firebase.analytics.app com.maikelgalvao.partiu\n'
      '   iOS: Adicione -FIRDebugEnabled nos launch arguments',
      tag: 'ANALYTICS',
    );
  }
}
