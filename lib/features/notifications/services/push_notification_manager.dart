import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui'; // DartPluginRegistrant (background isolate)
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:partiu/features/notifications/helpers/app_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partiu/firebase_options.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/features/conversations/state/conversation_activity_bus.dart';
import 'package:partiu/features/notifications/templates/notification_templates.dart';
import 'package:partiu/core/router/app_router.dart'; // ✅ rootNavigatorKey

/// 🔔 BACKGROUND NOTIFICATION TAP HANDLER (top-level, necessário para iOS/Android)
/// Quando o usuário clica numa notificação local com app em background/killed,
/// salvamos o payload e processamos quando o app voltar.
@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  // Necessário no iOS para registrar plugins (SharedPreferences etc) no isolate.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  print('╔═══════════════════════════════════════════════════════');
  print('║ 👆 NOTIFICATION TAP BACKGROUND CHAMADO!');
  print('╠═══════════════════════════════════════════════════════');
  print('║ Payload: ${response.payload}');
  print('║ ActionId: ${response.actionId}');
  print('║ NotificationResponseType: ${response.notificationResponseType}');
  print('╚═══════════════════════════════════════════════════════');
  
  final payload = response.payload;
  if (payload == null || payload.isEmpty) {
    print('⚠️ [PushManager] Payload vazio no background tap');
    return;
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_notification_payload', payload);
  await prefs.setInt('pending_notification_payload_ts', DateTime.now().millisecondsSinceEpoch);
    print('💾 [PushManager] Payload salvo: $payload');
  } catch (e) {
    print('❌ [PushManager] Erro ao salvar payload: $e');
  }
}

/// 🔔 BACKGROUND MESSAGE HANDLER (top-level, necessário para iOS/Android)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Necessário no iOS para registrar plugins (SharedPreferences etc) no isolate.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  print('╔═══════════════════════════════════════════════════════');
  print('║ 📨 BACKGROUND MESSAGE RECEBIDA');
  print('╠═══════════════════════════════════════════════════════');
  print('║ Message ID: ${message.messageId}');
  print('║ Sent Time: ${message.sentTime}');
  print('║ Data: ${message.data}');
  print('║ Notification: ${message.notification?.toMap()}');
  print('╚═══════════════════════════════════════════════════════');

  // Dedup extra (handler): alguns iOS entregam o mesmo background message mais de uma vez.
  // Usamos messageId (quando existir) para evitar chamar show() duas vezes.
  final bgMessageId = message.messageId;
  if (bgMessageId != null) {
    if (PushNotificationManager._backgroundShownMessageIds.contains(bgMessageId)) {
      print('⚠️ [PushManager] Background message duplicada (handler) - ignorando: $bgMessageId');
      return;
    }
  }

  // 🔒 Evitar duplicação:
  // O backend (PushDispatcher) envia push híbrido com `notification` + `data`
  // e marca `n_origin=push`. Nesse caso, o SO já exibe a notificação.
  // Se exibirmos uma notificação local aqui, vira DUPLICADO.
  final origin = (message.data['n_origin'] ?? '').toString();
  if (origin == 'push') {
    print(
      '🔕 [PushManager] Background push do servidor (n_origin=push). '
      'SO já exibiu. Não duplicar.'
    );
    return;
  }

  // Inicializa Firebase se necessário
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // Traduzir mensagem usando dados do SharedPreferences
  final translatedMessage = await _translateMessage(message);

  // Verificar flag de silencioso
  final silentFlag = (translatedMessage.data['n_silent'] ?? '').toString().toLowerCase();
  final isSilent = ['1', 'true', 'yes'].contains(silentFlag);
  
  if (!isSilent) {
    await PushNotificationManager.showBackgroundNotification(translatedMessage);
  } else {
    print('🔇 [SILENT] Background message marcada como silenciosa, não exibida');
  }
}

/// Traduz mensagem usando NotificationTemplates (client-side)
/// Backend envia apenas dados brutos, Flutter formata usando templates
Future<RemoteMessage> _translateMessage(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    final data = message.data;
    final nType = data['n_type'] ?? data['type'] ?? data['sub_type'] ?? '';

    // Resolve idioma salvo (se existir) para traduzir sem BuildContext
    String? languageCode = AppLocalizations.currentLocale;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString('app_locale');
      if (savedLocale != null && savedLocale.trim().isNotEmpty) {
        languageCode = savedLocale.split('_').first;
      }
    } catch (_) {
      // Ignore: fallback para AppLocalizations.currentLocale
    }

    final i18n = await AppLocalizations.loadForLanguageCode(languageCode);
    
    // Se já veio com título e corpo do backend, usa direto (fallback)
    if (message.notification?.title != null && message.notification!.title!.isNotEmpty) {
      print('ℹ️ [Translator] Mensagem já formatada pelo backend');
      return message;
    }

    late final NotificationMessage template;
    
    // Aplicar template baseado no tipo
    switch (nType) {
      // ===== MENSAGENS DE CHAT =====
      case 'chat_message':
      case 'new_message':
      case NOTIF_TYPE_MESSAGE:
        final senderName = data['n_sender_name'] ?? data['senderName'] ?? i18n.translate('someone');
        final messagePreview = data['n_message'] ?? data['messagePreview'];
        template = NotificationTemplates.newMessage(
          i18n: i18n,
          senderName: senderName,
          messagePreview: messagePreview,
        );
        break;

      case 'event_chat_message':
        final senderName = data['n_sender_name'] ?? data['senderName'] ?? i18n.translate('someone');
        final eventName = data['eventName'] ?? data['eventTitle'] ?? data['activityText'] ?? i18n.translate('event_default');
        final emoji = data['emoji'] ?? data['eventEmoji'] ?? '🎉';
        final messagePreview = data['n_message'] ?? data['messagePreview'];
        template = NotificationTemplates.eventChatMessage(
          i18n: i18n,
          senderName: senderName,
          eventName: eventName,
          emoji: emoji,
          messagePreview: messagePreview,
        );
        break;

      // ===== ATIVIDADES =====
      case 'activity_created':
        final creatorName = data['n_sender_name'] ?? data['creatorName'] ?? i18n.translate('someone');
        final activityName = data['activityName'] ?? data['eventTitle'] ?? i18n.translate('activity_default');
        final emoji = data['emoji'] ?? '🎉';
        final commonInterests = (data['commonInterests'] as String?)?.split(',') ?? [];
        template = NotificationTemplates.activityCreated(
          i18n: i18n,
          creatorName: creatorName,
          activityName: activityName,
          emoji: emoji,
          commonInterests: commonInterests,
        );
        break;

      case 'activity_join_request':
        final requesterName = data['n_sender_name'] ?? data['requesterName'] ?? i18n.translate('someone');
        final activityName = data['activityName'] ?? i18n.translate('activity_default');
        final emoji = data['emoji'] ?? '🎉';
        template = NotificationTemplates.activityJoinRequest(
          i18n: i18n,
          requesterName: requesterName,
          activityName: activityName,
          emoji: emoji,
        );
        break;

      case 'activity_join_approved':
        final activityName = data['activityName'] ?? i18n.translate('activity_default');
        final emoji = data['emoji'] ?? '🎉';
        template = NotificationTemplates.activityJoinApproved(
          i18n: i18n,
          activityName: activityName,
          emoji: emoji,
        );
        break;

      case 'activity_join_rejected':
        final activityName = data['activityName'] ?? i18n.translate('activity_default');
        final emoji = data['emoji'] ?? '🎉';
        template = NotificationTemplates.activityJoinRejected(
          i18n: i18n,
          activityName: activityName,
          emoji: emoji,
        );
        break;

      case 'activity_new_participant':
        final participantName = data['n_sender_name'] ?? data['participantName'] ?? i18n.translate('someone');
        final activityName = data['activityName'] ?? i18n.translate('activity_default');
        final emoji = data['emoji'] ?? '🎉';
        template = NotificationTemplates.activityNewParticipant(
          i18n: i18n,
          participantName: participantName,
          activityName: activityName,
          emoji: emoji,
        );
        break;

      case 'activity_heating_up':
        final activityName = data['activityName'] ?? i18n.translate('activity_default');
        final emoji = data['emoji'] ?? '🎉';
        final creatorName = data['n_sender_name'] ?? data['creatorName'] ?? i18n.translate('someone');
        final participantCount = int.tryParse(data['n_participant_count'] ?? data['participantCount'] ?? '2') ?? 2;
        template = NotificationTemplates.activityHeatingUp(
          i18n: i18n,
          activityName: activityName,
          emoji: emoji,
          creatorName: creatorName,
          participantCount: participantCount,
        );
        break;

      case 'activity_expiring_soon':
        final activityName = data['activityName'] ?? i18n.translate('activity_default');
        final emoji = data['emoji'] ?? '🎉';
        final hoursRemaining = int.tryParse(data['hoursRemaining'] ?? '1') ?? 1;
        template = NotificationTemplates.activityExpiringSoon(
          i18n: i18n,
          activityName: activityName,
          emoji: emoji,
          hoursRemaining: hoursRemaining,
        );
        break;

      case 'activity_canceled':
        final activityName = data['activityName'] ?? i18n.translate('activity_default');
        final emoji = data['emoji'] ?? '🎉';
        template = NotificationTemplates.activityCanceled(
          i18n: i18n,
          activityName: activityName,
          emoji: emoji,
        );
        break;

      // ===== VISITAS E REVIEWS =====
      case 'profile_views_aggregated':
        final count = int.tryParse(data['n_count'] ?? data['count'] ?? '1') ?? 1;
        final lastViewedAt = data['lastViewedAt'];
        final viewerNames = (data['viewerNames'] as String?)?.split(',');
        template = NotificationTemplates.profileViewsAggregated(
          i18n: i18n,
          count: count,
          lastViewedAt: lastViewedAt,
          viewerNames: viewerNames,
        );
        break;

      case 'review_pending':
      case 'new_review_received':
        final reviewerName = data['n_sender_name'] ?? data['reviewerName'] ?? i18n.translate('someone');
        final rating = double.tryParse(data['rating'] ?? '5.0') ?? 5.0;
        final comment = data['comment'];
        template = NotificationTemplates.newReviewReceived(
          i18n: i18n,
          reviewerName: reviewerName,
          rating: rating,
          comment: comment,
        );
        break;

      // ===== SYSTEM & CUSTOM =====
      case 'alert':
      case 'system_alert':
        final alertMessage = data['message'] ?? data['body'] ?? i18n.translate('notification_default');
        final alertTitle = data['title'] ?? APP_NAME;
        template = NotificationTemplates.systemAlert(
          message: alertMessage,
          title: alertTitle,
        );
        break;

      case 'custom':
        final customTitle = data['title'] ?? APP_NAME;
        final customBody = data['body'] ?? '';
        template = NotificationTemplates.custom(
          title: customTitle,
          body: customBody,
        );
        break;

      // ===== OUTROS =====
      case 'event_join':
        // Mensagem de entrada no evento (do index.ts)
        final userName = data['n_sender_name'] ?? data['userName'] ?? i18n.translate('someone');
        final activityText = data['activityText'] ?? data['eventTitle'] ?? i18n.translate('event_default');
        template = NotificationTemplates.custom(
          title: activityText,
          body: i18n
              .translate('notification_template_event_join_body')
              .replaceAll('{userName}', userName),
        );
        break;

      default:
        print('⚠️ [Translator] Tipo desconhecido: $nType');
        // Fallback para mensagem genérica
        final fallbackTitle = data['title'] ?? message.notification?.title ?? APP_NAME;
        final fallbackBody = data['body'] ?? message.notification?.body ?? i18n.translate('notification_default');
        template = NotificationTemplates.custom(
          title: fallbackTitle,
          body: fallbackBody,
        );
    }

    print('✅ [Translator] Mensagem formatada: ${template.title}');

    // Criar nova RemoteMessage com título e corpo do template
    return RemoteMessage(
      senderId: message.senderId,
      category: message.category,
      collapseKey: message.collapseKey,
      contentAvailable: message.contentAvailable,
      data: data,
      from: message.from,
      messageId: message.messageId,
      messageType: message.messageType,
      mutableContent: message.mutableContent,
      notification: RemoteNotification(
        title: template.title,
        body: template.body,
        android: message.notification?.android,
        apple: message.notification?.apple,
        web: message.notification?.web,
      ),
      sentTime: message.sentTime,
      threadId: message.threadId,
      ttl: message.ttl,
    );
  } catch (e, stackTrace) {
    print('⚠️ [Translator] Erro ao traduzir: $e');
    print('Stack: $stackTrace');
    return message;
  }
}

/// PUSH NOTIFICATION MANAGER
/// 
/// Gerencia todas as notificações push do app:
/// ✅ Notificações locais para foreground
/// ✅ Background message handler
/// ✅ Permissões iOS/Android
/// ✅ Channel Android configurado
/// ✅ Detecção de conversa atual para evitar notificações duplicadas
/// ✅ Tradução client-side de mensagens
class PushNotificationManager {
  static final instance = PushNotificationManager._();
  PushNotificationManager._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  // Debounce fields
  String? _lastOpenedId;
  DateTime _lastOpenedAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _shouldIgnore(String id) {
    final now = DateTime.now();
    if (_lastOpenedId == id && now.difference(_lastOpenedAt) < const Duration(seconds: 1)) {
      return true;
    }
    _lastOpenedId = id;
    _lastOpenedAt = now;
    return false;
  }

  // Click throttling
  final Map<String, int> _clicktimestamps = {};
  
  bool _shouldProcessClick(String clickKey, {int windowMs = 2000}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastClick = _clicktimestamps[clickKey] ?? 0;
    
    if (now - lastClick < windowMs) {
      return false;
    }
    
    _clicktimestamps[clickKey] = now;
    // Cleanup old keys
    _clicktimestamps.removeWhere((key, ts) => now - ts > 60000);
    
    return true;
  }

  // iOS: evita processar o mesmo clique 2x (resume + launchDetails)
  String? _lastProcessedPayload;

  // iOS fallback: quando o iOS não entrega callback de clique de notificação local,
  // persistimos o último payload exibido e tentamos navegar no próximo resume.
  static const String _lastShownPayloadKey = 'last_shown_local_notification_payload';
  static const String _lastShownPayloadTsKey = 'last_shown_local_notification_payload_ts';

  // Channel Android
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'boora_high_importance',
    'Notificações do $APP_NAME',
    description: 'Notificações de mensagens, rolês e atividades',
    importance: Importance.high,
    enableVibration: true,
    playSound: true,
  );

  // Controle de duplicação
  String _currentConversationId = '';
  final Set<String> _processedMessageIds = {};
  String? _pendingToken;

  // Background isolate: evita duplicar notificações locais (mesma mensagem chegando 2x)
  static final Set<String> _backgroundShownMessageIds = <String>{};
  
  // ✅ Armazena última mensagem recebida em foreground para navegação
  // No iOS, quando o SO exibe a notificação em foreground, onMessageOpenedApp
  // NÃO é chamado ao clicar. Esta variável permite processar o clique.
  RemoteMessage? _lastForegroundMessage;
  
  // Limpar cache de IDs processados a cada 5 minutos
  Timer? _cleanupTimer;
  
  /// @deprecated Use rootNavigatorKey diretamente do app_router.dart
  /// Mantido apenas para compatibilidade temporária
  @Deprecated('Use rootNavigatorKey from app_router.dart instead')
  BuildContext? _appContext;
  
  /// @deprecated Use rootNavigatorKey diretamente
  @Deprecated('Use rootNavigatorKey from app_router.dart instead')
  void setAppContext(BuildContext context) {
    _appContext = context;
    print('⚠️ [PushManager] setAppContext() é deprecated - use rootNavigatorKey');
  }
  
  /// Define qual conversa está aberta no momento
  void setCurrentConversation(String? conversationId) {
    _currentConversationId = conversationId ?? '';
    print('💬 [PushManager] Conversa atual: $_currentConversationId');
  }

  /// Limpa estado (útil no logout)
  void resetState() {
    print('🔄 [PushManager] Resetando estado');
    _currentConversationId = '';
    _processedMessageIds.clear();
    _pendingToken = null;
    _cleanupTimer?.cancel();
  }
  
  /// ✅ Chame este método quando o app voltar do background (AppLifecycleState.resumed)
  /// para verificar se há payload pendente de notificação clicada
  Future<void> checkPendingNotificationPayload() async {
    // Tentar múltiplas vezes com delay, pois o SharedPreferences pode não estar sincronizado
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        // Pequeno delay para garantir que SharedPreferences esteja sincronizado
        if (attempt > 0) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
        
        final prefs = await SharedPreferences.getInstance();
        // Recarregar para pegar mudanças de outro isolate
        await prefs.reload();
        
        final pending = prefs.getString('pending_notification_payload');
        final ts = prefs.getInt('pending_notification_payload_ts');
        print('🔍 [PushManager] Verificando payload pendente (tentativa ${attempt + 1}): ${pending != null ? "ENCONTRADO" : "vazio"}');
        
        if (pending != null && pending.isNotEmpty) {
          print('📬 [PushManager] Payload pendente encontrado no resume!');
          print('   - Payload: $pending');
          
          if (ts != null) {
            print('   - SavedAt(ms): $ts');
          }
          await prefs.remove('pending_notification_payload');
          await prefs.remove('pending_notification_payload_ts');
          
          // ✅ Verifica se já foi processado (dedupe no resume)
          if (_lastProcessedPayload == pending) {
            print('⚠️ [PushManager] Payload pendente JÁ foi processado. Ignorando.');
            return;
          }
          _lastProcessedPayload = pending;
          
          final data = (json.decode(pending) as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
          await Future.delayed(const Duration(milliseconds: 300));
          navigateFromNotificationData(data);
          return; // Sucesso, sair do loop
        }
      } catch (e) {
        print('⚠️ [PushManager] Erro ao verificar payload pendente (tentativa ${attempt + 1}): $e');
      }
    }

    // iOS fallback: quando o callback de background do plugin não dispara,
    // ainda dá para capturar clique via launchDetails.
    try {
      final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
    print('🍎 [PushManager] checkPending launchDetails: '
      'exists=${launchDetails != null} '
      'didLaunch=${launchDetails?.didNotificationLaunchApp} '
      'hasResponse=${launchDetails?.notificationResponse != null}');
      if (launchDetails != null &&
          launchDetails.didNotificationLaunchApp &&
          launchDetails.notificationResponse?.payload != null &&
          launchDetails.notificationResponse!.payload!.isNotEmpty) {
        final payload = launchDetails.notificationResponse!.payload!;

        if (_lastProcessedPayload == payload) {
          return;
        }
        _lastProcessedPayload = payload;

        print('🚀 [PushManager] checkPending: App aberto via notificação local (launchDetails)');
        print('   - Payload: $payload');

        final data = (json.decode(payload) as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
        await Future.delayed(const Duration(milliseconds: 300));
        navigateFromNotificationData(data);
      }
    } catch (e) {
      print('⚠️ [PushManager] Erro ao ler launchDetails: $e');
    }

    // Último fallback (iOS): se nada acima funcionou, mas temos um payload de notificação
    // local exibida recentemente, tentamos navegar. Isso cobre casos onde o iOS não
    // entrega o callback nem preenche didNotificationLaunchApp.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final lastShownPayload = prefs.getString(_lastShownPayloadKey);
      final lastShownTs = prefs.getInt(_lastShownPayloadTsKey);

      if (lastShownPayload != null && lastShownPayload.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final ageMs = lastShownTs != null ? (now - lastShownTs) : null;

        // Só considera se foi exibida há pouco (evita navegação fantasma dias depois).
        final isRecent = ageMs == null || ageMs < 2 * 60 * 1000; // 2 min
        if (isRecent && _lastProcessedPayload != lastShownPayload) {
          _lastProcessedPayload = lastShownPayload;
          print('🧯 [PushManager] FALLBACK iOS: usando lastShown payload para navegar');
          print('   - ageMs: ${ageMs ?? -1}');
          print('   - Payload: $lastShownPayload');

          // Consome para não repetir.
          await prefs.remove(_lastShownPayloadKey);
          await prefs.remove(_lastShownPayloadTsKey);

          final data = (json.decode(lastShownPayload) as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
          await Future.delayed(const Duration(milliseconds: 300));
          navigateFromNotificationData(data);
        }
      }
    } catch (e) {
      print('⚠️ [PushManager] Erro no fallback lastShown payload: $e');
    }
  }
  
  /// Inicia timer para limpar cache de IDs processados
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _processedMessageIds.clear();
      print('🧹 [PushManager] Cache de IDs processados limpo');
    });
  }

  /// 🔧 Inicializa o sistema de notificações push
  /// Deve ser chamado no main() ANTES do app rodar
  Future<void> initialize() async {
    try {
      print('╔═══════════════════════════════════════════════════════');
      print('║ 🔔 PUSH NOTIFICATION MANAGER - INICIALIZANDO');
      print('╚═══════════════════════════════════════════════════════');

      // 1. Configurar notificações locais
      print('📱 [PushManager] Passo 1: Configurando notificações locais...');
      await _setupLocalNotifications();

      // 2. Solicitar permissões
      print('🔐 [PushManager] Passo 2: Solicitando permissões...');
      await _requestPermissions();

      // 3. Configurar handlers
      print('🎯 [PushManager] Passo 3: Configurando handlers...');
      _setupForegroundHandler();
      _setupTokenRefresh();
      
      // Background handler (top-level)
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // iOS: apresentação em foreground
      // ✅ Habilitar banner nativo do iOS para notificações em foreground
      if (Platform.isIOS) {
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,  // ✅ Mostrar banner
          badge: false, // App controla via BadgeService
          sound: true,  // ✅ Tocar som
        );
      }

      // 4. Configurar click handler
      print('👆 [PushManager] Passo 4: Configurando click handler...');
      _setupMessageOpenedHandler();

      // 5. Criar channel Android
      print('📢 [PushManager] Passo 5: Criando channel Android...');
      await _createAndroidChannel();

      // 6. Iniciar timer de limpeza de cache
      print('🧹 [PushManager] Passo 6: Iniciando timer de limpeza...');
      _startCleanupTimer();

      print('╔═══════════════════════════════════════════════════════');
      print('║ ✅ PUSH NOTIFICATION MANAGER - INICIALIZADO');
      print('╚═══════════════════════════════════════════════════════');

    } catch (e, stackTrace) {
      print('❌ [PushManager] ERRO ao inicializar: $e');
      print('Stack: $stackTrace');
    }
  }

  /// Deve ser chamado APÓS o runApp, quando o contexto de navegação já existe
  Future<void> handleInitialMessageAfterRunApp() async {
    try {
      // 1) FCM initial message (quando é notificação do FCM mesmo)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        print('🚀 [PushManager] Initial message detectada (app aberto via notificação FCM)');
        print('   - data: ${initialMessage.data}');
        await Future.delayed(const Duration(milliseconds: 500));
        navigateFromNotificationData(initialMessage.data);
        return; // ✅ Não processa payload local se já tem FCM
      }

      // 2) Local notification pendente (quando mostrou via flutter_local_notifications)
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // ✅ Recarregar para pegar mudanças de outro isolate
      final pending = prefs.getString('pending_notification_payload');
      
      print('🔍 [PushManager] handleInitialMessage - payload pendente: ${pending != null ? "ENCONTRADO" : "vazio"}');
      
      if (pending != null && pending.isNotEmpty) {
        print('📬 [PushManager] Payload local pendente encontrado');
        print('   - Payload: $pending');
        await prefs.remove('pending_notification_payload');
        
        final data = (json.decode(pending) as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
        await Future.delayed(const Duration(milliseconds: 300));
        navigateFromNotificationData(data);
        return;
      }
      
      // 3) Verificar também o launchDetails do flutter_local_notifications
      final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails != null && 
          launchDetails.didNotificationLaunchApp && 
          launchDetails.notificationResponse != null) {
        print('🚀 [PushManager] App aberto via notificação local!');
        final response = launchDetails.notificationResponse!;
        print('   - Payload: ${response.payload}');
        
        if (response.payload != null && response.payload!.isNotEmpty) {
          if (_lastProcessedPayload == response.payload) {
            return;
          }
          _lastProcessedPayload = response.payload;
          final data = (json.decode(response.payload!) as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
          await Future.delayed(const Duration(milliseconds: 300));
          navigateFromNotificationData(data);
        }
      }
    } catch (e) {
      print('⚠️ [PushManager] Erro ao processar initial/local payload: $e');
    }
  }

  /// Handler para mensagens em FOREGROUND (app aberto)
  void _setupForegroundHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('╔═══════════════════════════════════════════════════════');
      print('║ 📨 FOREGROUND MESSAGE RECEBIDA');
      print('╠═══════════════════════════════════════════════════════');
      print('║ Message ID: ${message.messageId}');
      print('║ Sent Time: ${message.sentTime}');
      print('║ Data: ${message.data}');
      print('║ Notification: ${message.notification?.toMap()}');
      print('╚═══════════════════════════════════════════════════════');

      // Verificar flag de silencioso PRIMEIRO
      final silentFlag = (message.data['n_silent'] ?? '').toString().toLowerCase();
      final isSilent = ['1', 'true', 'yes'].contains(silentFlag);
      if (isSilent) {
        print('🔇 [PushManager] Mensagem silenciosa, não exibindo notificação');
        return;
      }

      // Não mostra notificação se está na conversa atual
      final conversationId = message.data['conversationId'] ?? 
                            message.data['n_related_id'] ?? 
                            message.data['relatedId'] ??
                            message.data['eventId'];
      final nType = message.data['n_type'] ?? message.data['type'] ?? '';

      // ✅ Padronização UI: força feedback visual no inbox para chat de evento.
      // O doc de Conversations pode ficar com unread_count=0 (ex.: mensagens system)
      // ou demorar, então marcamos a conversa como "touched" assim que o push chega.
      if (nType == 'event_chat_message') {
        final eventId = (message.data['eventId'] ?? '').toString();
        if (eventId.isNotEmpty) {
          ConversationActivityBus.instance.touch('event_$eventId');
        }
      }
      
      if (nType == NOTIF_TYPE_MESSAGE && conversationId == _currentConversationId && _currentConversationId.isNotEmpty) {
        print('💬 [PushManager] Mensagem da conversa atual, não exibindo notificação');
        return;
      }

      // ✅ iOS: Com alert:true no setForegroundNotificationPresentationOptions,
      // o SO mostra o banner automaticamente para notificações com `notification` payload.
      // Somente exibimos local se message.notification for NULL (data-only).
      if (Platform.isIOS) {
        if (message.notification != null) {
          print('🍎 [PushManager] iOS foreground: já exibido pelo sistema (alert:true). Ignorando local.');
          _lastForegroundMessage = message;
          return;
        }
        
        print('🍎 [PushManager] iOS foreground (data-only): exibindo notificação local');
        _lastForegroundMessage = message;
        final translatedMessage = await _translateMessage(message);
        await _showLocalNotification(translatedMessage);
        return;
      }

      // Android: mantém lógica de verificar n_origin para evitar duplicação
      // (porque no Android o SO pode exibir o banner automaticamente)
      final origin = (message.data['n_origin'] ?? '').toString();
      if (origin == 'push') {
        print('🤖 [PushManager] Android foreground (n_origin=push): exibindo local');
        _lastForegroundMessage = message;
        final translatedMessage = await _translateMessage(message);
        await _showLocalNotification(translatedMessage);
        return;
      }

      // Evitar duplicação usando Set de IDs processados
      final messageId = message.messageId;
      if (messageId != null && _processedMessageIds.contains(messageId)) {
        print('⚠️ [PushManager] Mensagem duplicada (ID já processado), ignorando');
        return;
      }
      if (messageId != null) {
        _processedMessageIds.add(messageId);
        if (_processedMessageIds.length > 100) {
          final oldIds = _processedMessageIds.take(50).toList();
          _processedMessageIds.removeAll(oldIds);
        }
      }

      // Data-only no Android: traduzir e exibir local
      final translatedMessage = await _translateMessage(message);
      await _showLocalNotification(translatedMessage);
    });
  }

  /// Setup listener para quando mensagem é clicada (app em background ou fechado)
  void _setupMessageOpenedHandler() {
    // Mensagem tocada quando app estava em background OU foreground (iOS 10+)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('╔═══════════════════════════════════════════════════════');
      print('║ 👆 NOTIFICAÇÃO CLICADA (onMessageOpenedApp)');
      print('╠═══════════════════════════════════════════════════════');
      print('║ Message ID: ${message.messageId}');
      print('║ Data: ${message.data}');
      print('╚═══════════════════════════════════════════════════════');
      
      try {
        navigateFromNotificationData(message.data);
      } catch (e) {
        print('⚠️ [PushManager] Erro ao processar click: $e');
      }
    });
  }

  /// 📱 Configura notificações locais (Android + iOS)
  Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentSound: true,
      defaultPresentBadge: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // No iOS, esse callback também pode ser invocado quando o app estava em background
        // e o usuário toca a notificação local.
        if (response.payload != null && response.payload!.isNotEmpty) {
          _lastProcessedPayload = response.payload;
        }
        _onNotificationTapped(response);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    print('✅ [PushManager] Notificações locais configuradas');
  }

  /// Callback quando notificação local é tocada (app em foreground)
  void _onNotificationTapped(NotificationResponse response) {
    print('╔═══════════════════════════════════════════════════════');
    print('║ 👆 NOTIFICAÇÃO LOCAL CLICADA (FOREGROUND)');
    print('╠═══════════════════════════════════════════════════════');
    
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      // ✅ Dedupe imediato: se este payload já foi processado recentemente, ignora.
      if (_lastProcessedPayload == payload) {
        print('⚠️ [PushManager] Payload já processado recentemente. Ignorando.');
        return;
      }
      _lastProcessedPayload = payload;
      
      try {
        final data = json.decode(payload) as Map<String, dynamic>;
        print('✅ [PushManager] Payload decodificado: $data');

        // ✅ Só salva como pendente se o Navigator NÃO estiver pronto
        final nav = rootNavigatorKey.currentState;
        if (nav == null) {
          SharedPreferences.getInstance().then((prefs) async {
            try {
              await prefs.setString('pending_notification_payload', payload);
              await prefs.setInt('pending_notification_payload_ts', DateTime.now().millisecondsSinceEpoch);
            } catch (_) {}
          });
        }

        // ✅ Convertemos valores para string para manter compatibilidade.
        navigateFromNotificationData(
          data.map((k, v) => MapEntry(k, v.toString())),
        );
      } catch (e) {
        print('❌ [PushManager] Erro ao processar payload: $e');
      }
    } else {
      print('⚠️ [PushManager] Payload vazio ou nulo');
    }
  }

  /// Navega baseado nos dados da notificação
  /// ✅ Usa rootNavigatorKey para navegação estável (não depende de BuildContext frágil)
  void navigateFromNotificationData(Map<String, dynamic> data) {
    print('╔═══════════════════════════════════════════════════════');
    print('║ 🧭 NAVEGANDO BASEADO EM NOTIFICAÇÃO');
    print('╠═══════════════════════════════════════════════════════');
    
    // Identificador único do clique para deduplicação
    final clickKey = data['click_uuid'] ?? 
                     data['messageId'] ?? 
                     '${data['n_type']}_${data['n_related_id']}_${data['activityId']}';
                     
    if (!_shouldProcessClick(clickKey, windowMs: 2000)) {
      print('🛑 [PushManager] Abortando navegação duplicada.');
      return;
    }
    
    print('║ Data keys: ${data.keys.toList()}');
    print('║ Full data: $data');
    print('╚═══════════════════════════════════════════════════════');
    
    final nType = data['n_type'] ?? data['type'] ?? '';
    final nSenderId = data['n_sender_id'] ?? data['senderId'] ?? '';
    // ✅ StableId: Adiciona activityId da data nativa para evitar que notificações 
    // de atividades diferentes sejam agrupadas ou causem confusão no dedupe
    final nRelatedId =
      data['conversationId'] ??
      data['n_conversation_id'] ??
      data['eventId'] ??
      data['activityId'] ??
      data['n_related_id'] ??
      data['relatedId'] ??
      '';
    final deepLink = data['deepLink'] ?? data['deep_link'] ?? '';
    final screen = data['screen'] ?? '';

    // Debounce check
    final uniqueId = '$nType-$nRelatedId-$deepLink';
    if (_shouldIgnore(uniqueId)) {
      print('🔕 [PushManager] Navegação duplicada ignorada (debounce): $uniqueId');
      return;
    }

    print('🧭 [PushManager] Parsed values:');
    print('   - nType: $nType');
    print('   - nSenderId: $nSenderId');
    print('   - nRelatedId: $nRelatedId');
    print('   - deepLink: $deepLink');
    print('   - screen: $screen');

    // ✅ Usar rootNavigatorKey para navegação estável
    final navigator = rootNavigatorKey.currentState;
    
    if (navigator == null) {
      print('⚠️ [PushManager] Navigator ainda não disponível, tentando novamente em 300ms...');
      Future.delayed(const Duration(milliseconds: 300), () {
        navigateFromNotificationData(data);
      });
      return;
    }
    
    print('✅ [PushManager] Navigator disponível, chamando AppNotifications.onNotificationClick...');

    AppNotifications().onNotificationClick(
      navigator.context,
      nType: nType,
      nSenderId: nSenderId,
      nRelatedId: nRelatedId,
      deepLink: deepLink,
      screen: screen,
    );
  }

  /// 🔔 Solicita permissões (iOS principalmente)
  Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,  // ✅ Habilitado para controle via BadgeService
        sound: true,
        provisional: false,
      );

      print('🔐 [PushManager] Permissões iOS: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        print('⚠️ [PushManager] Usuário negou permissões no iOS');
      }
    } else {
      // Android 13+
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      
      print('✅ [PushManager] Permissões Android solicitadas');
    }
  }

  /// 📢 Cria notification channel no Android
  Future<void> _createAndroidChannel() async {
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      
      print('✅ [PushManager] Android channel criado: ${_channel.id}');
    }
  }

  /// Setup listener para token refresh
  void _setupTokenRefresh() {
    _messaging.onTokenRefresh.listen((String token) {
      print('🔄 [PushManager] FCM Token refreshed: ${token.substring(0, 20)}...');
      _pendingToken = token;
      // O FcmTokenService vai pegar esse token e salvar no Firestore
    });
  }

  /// Exibe notificação local (foreground)
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    // ✅ Extrair título e corpo do notification OU dos params
    String? title = notification?.title;
    String? body = notification?.body;
    
    // Fallback para n_params se notification payload não tiver título/corpo
    if ((title == null || title.isEmpty) && data['n_params'] != null) {
      try {
        final params = data['n_params'] is String 
            ? json.decode(data['n_params']) 
            : data['n_params'];
        title = params['title'] as String?;
        body = params['body'] as String?;
      } catch (_) {}
    }
    
    // Segundo fallback para campos diretos
    title ??= data['title'] as String?;
    body ??= data['body'] as String?;
    
    if (title == null || title.isEmpty) {
      print('⚠️ [PushManager] Sem título para notificação, não exibindo');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
    // ✅ Evitar empilhar duplicadas no foreground: usar um ID estável por conversa/evento
    // (assim a notificação é substituída/atualizada).
    final stableKey = (data['eventId'] ?? data['n_related_id'] ?? data['relatedId'] ?? '')
      .toString();
    final notificationId = stableKey.isNotEmpty
      ? (stableKey.hashCode.abs() % 100000)
      : (DateTime.now().millisecondsSinceEpoch % 100000);

      await _localNotifications.show(
    notificationId,
        title ?? APP_NAME,
        body ?? '',
        notificationDetails,
        payload: json.encode(data),
      );
      
      print('✅ [PushManager] Notificação local exibida');
      print('   - Título: $title');
      print('   - Corpo: $body');
    } catch (e) {
      print('❌ [PushManager] Erro ao exibir notificação: $e');
    }
  }

  /// 🔔 Mostra notificação no background (método estático)
  /// Método estático para ser chamado do background handler
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    try {
      print('📨 [PushManager] Exibindo notificação background');

      // Dedup (background): se o Firebase entregar o mesmo messageId mais de uma vez,
      // evita criar 2 notificações iguais.
      final messageId = message.messageId;
      if (messageId != null) {
        if (_backgroundShownMessageIds.contains(messageId)) {
          print('⚠️ [PushManager] Background notif duplicada (messageId já exibido): $messageId');
          return;
        }
        _backgroundShownMessageIds.add(messageId);
        if (_backgroundShownMessageIds.length > 200) {
          _backgroundShownMessageIds.remove(_backgroundShownMessageIds.first);
        }
      }
      
      // IMPORTANTE:
      // Não inicialize o FlutterLocalNotificationsPlugin dentro do background isolate.
      // Em iOS, isso normalmente faz o callback de clique não ser entregue ao isolate
      // principal (onde o app realmente navega) e o payload nunca chega no resume.
      // A inicialização correta já acontece em _setupLocalNotifications() no isolate principal.
      final plugin = FlutterLocalNotificationsPlugin();
      
      // Criar channel (Android)
      if (Platform.isAndroid) {
        await plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_channel);
      }
      
      // ✅ Para data-only messages, não temos message.notification
      // Precisamos usar os dados do message.data diretamente
      final notification = message.notification;
      final data = message.data;
      
      // Extrair título e corpo do notification OU dos data fields
      String? title = notification?.title;
      String? body = notification?.body;
      
      // Fallback para campos do data se notification estiver vazio
      if (title == null || title.isEmpty) {
        title = data['eventName'] as String? ?? 
                data['eventTitle'] as String? ?? 
                data['activityText'] as String? ??
                data['title'] as String?;
        final emoji = data['emoji'] as String? ?? data['eventEmoji'] as String? ?? '';
        if (title != null && emoji.isNotEmpty) {
          title = '$title $emoji';
        }
      }
      
      if (body == null || body.isEmpty) {
        final senderName = data['n_sender_name'] as String? ?? data['senderName'] as String? ?? '';
        final messagePreview = data['n_message'] as String? ?? data['messagePreview'] as String? ?? '';
        if (senderName.isNotEmpty && messagePreview.isNotEmpty) {
          body = '$senderName: $messagePreview';
        } else {
          body = data['body'] as String? ?? messagePreview;
        }
      }
      
      if (title == null || title.isEmpty) {
        print('⚠️ [PushManager] Background notification sem título, não exibindo');
        return;
      }

      final androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      );

      // ✅ Usar ID estável para evitar duplicatas
      final stableKey = (data['eventId'] ?? data['n_related_id'] ?? data['relatedId'] ?? '')
        .toString();
      final notificationId = stableKey.isNotEmpty
        ? (stableKey.hashCode.abs() % 100000)
        : (DateTime.now().millisecondsSinceEpoch % 100000);

      // 🔐 FALLBACK: persistir o payload exibido. Em alguns iOS, o callback de clique
      // (onDidReceiveBackgroundNotificationResponse) não é entregue.
      // Nesse caso, no próximo resume usamos esse payload para navegar.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastShownPayloadKey, json.encode(data));
        await prefs.setInt(_lastShownPayloadTsKey, DateTime.now().millisecondsSinceEpoch);
      } catch (_) {
        // ignore
      }

      await plugin.show(
        notificationId,
        title,
        body ?? '',
        NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: json.encode(data),
      );
      
      print('✅ [PushManager] Background notification exibida');
      print('   - Título: $title');
      print('   - Corpo: $body');
    } catch (e, stackTrace) {
      print('❌ [PushManager] Erro ao exibir background notification: $e');
      print('Stack: $stackTrace');
    }
  }

  /// Subscreve em um tópico FCM
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      print('✅ [PushManager] Inscrito no tópico: $topic');
    } catch (e) {
      print('❌ [PushManager] Erro ao se inscrever no tópico: $e');
    }
  }

  /// Remove inscrição de um tópico FCM
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      print('✅ [PushManager] Desinscrito do tópico: $topic');
    } catch (e) {
      print('❌ [PushManager] Erro ao se desinscrever do tópico: $e');
    }
  }
}
