import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart' as fire_auth;
import 'package:partiu/screens/notifications/helpers/app_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partiu/firebase_options.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/constants/constants.dart';

/// 🔔 BACKGROUND MESSAGE HANDLER (top-level, necessário para iOS/Android)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📨 Background message recebida: ${message.messageId}');
  print('  - data: ${message.data}');
  print('  - notification: ${message.notification?.toMap()}');

  // Inicializa Firebase se necessário
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  // Tradução local do conteúdo da notificação
  final translation = await PushNotificationManager.translateNotificationLocally(message);
  print('  - translated: $translation');

  // Cria uma nova RemoteMessage com título/corpo traduzidos
  final translatedMessage = RemoteMessage(
    messageId: message.messageId,
    data: message.data,
    notification: RemoteNotification(
      title: translation['title'],
      body: translation['body'],
      android: message.notification?.android,
      apple: message.notification?.apple,
    ),
    sentTime: message.sentTime,
    ttl: message.ttl,
    category: message.category,
    collapseKey: message.collapseKey,
    contentAvailable: message.contentAvailable,
    from: message.from,
    messageType: message.messageType,
    mutableContent: message.mutableContent,
    senderId: message.senderId,
    threadId: message.threadId,
  );

  // Silent? (n_silent flag)
  final silentFlag = (translatedMessage.data['n_silent'] ?? '').toString().toLowerCase();
  final isSilent = ['1', 'true', 'yes'].contains(silentFlag);
  if (!isSilent) {
    await PushNotificationManager.showBackgroundNotification(translatedMessage);
  } else {
    print('[SILENT] Background message marcada como silenciosa, não exibida');
  }
}

/// PUSH NOTIFICATION MANAGER
/// 
/// SIMPLIFICADO: Remove lógica específica de casamento, mantém apenas message/alert/custom
/// 
/// Características:
/// ✅ Notificações locais para foreground
/// ✅ Background message handler
/// ✅ Permissões iOS/Android
/// ✅ Channel Android configurado
/// ✅ Detecção de conversa atual para evitar notificações duplicadas
/// ✅ Tradução client-side usando SharedPreferences
class PushNotificationManager {
  static final instance = PushNotificationManager._();
  PushNotificationManager._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // Android notification channel
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'partiu_high_importance', // id
    'Partiu Notifications', // title
    description: 'This channel is used for important notifications.',
    importance: Importance.max,
    playSound: true,
    enableLights: true,
    enableVibration: true,
  );

  String _currentConversationId = '';
  String _lastMessageId = '';
  String _lastNavigationKey = '';
  DateTime? _lastNavigationAt;
  String? _pendingToken; // token aguardando login
  StreamSubscription<fire_auth.User?>? _authListener;

  /// 🌐 Tradução local de notificações (client-side)
  /// Backend envia dados estruturados, Flutter traduz baseado no idioma do SharedPreferences
  static Future<Map<String, String>> translateNotificationLocally(RemoteMessage message) async {
    try {
      // 1. Get language from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final localeStr = prefs.getString('app_locale') ?? 'pt';
      final languageCode = localeStr.split('_').first.split('-').first.toLowerCase();
      
      // 2. Load AppLocalizations
      final appLoc = AppLocalizations(Locale(languageCode));
      await appLoc.load();

      // 3. Extract structured data from message
      final data = message.data;
      final type = data['type'] ?? '';
      String senderName = data['senderName'] ?? '';
      
      print('🔍 [DEBUG] Original senderName from backend: "$senderName"');
      
      // ✅ Translate masked_someone based on locale
      if (senderName == 'masked_someone' || senderName == 'Someone' || senderName == 'Alguém') {
        senderName = languageCode == 'pt' ? 'Alguém' : 'Someone';
        print('🔄 [MASKED] Translated to: "$senderName" for locale: $languageCode');
      } else if (senderName.isEmpty) {
        senderName = languageCode == 'pt' ? 'Alguém' : 'Someone';
        print('⚠️ [EMPTY] Using fallback: "$senderName" for locale: $languageCode');
      }
      
      print('🌐 [TRANSLATE] locale: $localeStr, type: $type, senderName: $senderName');
      
      // 4. Map type to key and params
      String key = 'notification_default';
      Map<String, String> params = {};
      
      // Common params
      params['senderName'] = senderName;
      
      switch (type) {
        case NOTIF_TYPE_MESSAGE:
        case 'new_message':
           key = 'notification_message';
           break;
        case 'alert':
           key = 'notification_alert';
           break;
        case 'custom':
           // Para custom, tentar usar mensagem dos params
           final customMessage = data['message'] ?? data['body'];
           if (customMessage != null && customMessage.toString().isNotEmpty) {
             return {'title': 'Partiu', 'body': customMessage.toString()};
           }
           key = 'notification_default';
           break;
        default:
           key = 'notification_default';
      }
      
      String body = appLoc.translate(key);
      
      // Replace placeholders (support both {{key}} and {key})
      params.forEach((k, v) {
        body = body.replaceAll('{{$k}}', v).replaceAll('{$k}', v);
      });
      
      // Special case for message preview (append if exists)
      if ((type == NOTIF_TYPE_MESSAGE || type == 'new_message') && 
          (data['messagePreview'] ?? '').toString().isNotEmpty) {
         body += ': ${data['messagePreview']}';
      }

      return {'title': 'Partiu', 'body': body};
      
    } catch (e) {
       print('Error translating notification locally: $e');
       return {'title': 'Partiu', 'body': 'Nova notificação'};
    }
  }

  /// Reseta completamente o estado interno relacionado à sessão do usuário
  void resetState() {
    print('Resetando estado do PushNotificationManager');
    _currentConversationId = '';
    _lastMessageId = '';
    _lastNavigationKey = '';
    _lastNavigationAt = null;
    _pendingToken = null;
  }

  /// 🔧 Inicializa o sistema de notificações push
  /// Deve ser chamado no main() ANTES do app rodar
  Future<void> initialize() async {
    try {
      print('🔔 Inicializando PushNotificationManager...');

      // 1. Configurar notificações locais
      await _setupLocalNotifications();

      // 2. Solicitar permissões
      await _requestPermissions();

      // 3. Configurar handlers
      _setupForegroundHandler();
      _setupTokenRefresh();
      // Background handler (top-level)
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // iOS: apresentação em foreground
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: false,
        sound: true,
      );

      // Mensagem tocada quando app estava em background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        try {
          navigateFromNotificationData(message.data);
        } catch (e) {
          print('Falha ao processar onMessageOpenedApp: $e');
        }
      });

      // 4. Criar channel Android
      await _createAndroidChannel();

      print('[OK] PushNotificationManager inicializado');

    } catch (e) {
      print('[ERROR] Erro ao inicializar PushNotificationManager: $e');
    }
  }

  /// Deve ser chamado APÓS o runApp, quando o contexto de navegação já existe
  Future<void> handleInitialMessageAfterRunApp() async {
    try {
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        print('[INIT] initialMessage detected (post-runApp)');
        navigateFromNotificationData(initialMessage.data);
      }
    } catch (e) {
      print('Failed to process initialMessage (post-runApp): $e');
    }
  }

  /// ÚNICO handler de navegação para cliques de notificação
  void navigateFromNotificationData(Map<String, dynamic> raw) {
    // Normaliza dados em strings
    final data = <String, String>{
      'type': (raw['type'] ?? '').toString(),
      'senderId': (raw['senderId'] ?? raw['n_sender_id'] ?? '').toString(),
      'relatedId': (raw['relatedId'] ?? raw['n_related_id'] ?? '').toString(),
      'deepLink': (raw['deepLink'] ?? raw['deeplink'] ?? '').toString(),
      'screen': (raw['screen'] ?? '').toString(),
    };

    final key = _computeNavigationKey(data);
    final now = DateTime.now();
    if (_lastNavigationKey == key && _lastNavigationAt != null &&
        now.difference(_lastNavigationAt!).inMilliseconds < 1500) {
      print('⏭️  Navegação ignorada (duplicada em <1.5s): $key');
      return;
    }
    _lastNavigationKey = key;
    _lastNavigationAt = now;

    // Agenda após o frame para garantir que Navigator existe
    WidgetsBinding.instance.addPostFrameCallback((_) {
      int attempts = 0;
      Future<void> tryNavigate() async {
        // TODO: Ajustar para usar NavigationService do Partiu
        final ctx = null; // NavigationService.instance.context;
        if (ctx != null) {
          print('➡️  Navegando a partir de push (type=${data['type']}, relatedId=${data['relatedId']})');
          AppNotifications().onNotificationClick(
            ctx,
            nType: data['type'] ?? '',
            nSenderId: data['senderId'] ?? '',
            nRelatedId: data['relatedId'],
            deepLink: data['deepLink'],
            screen: data['screen'],
          );
          return;
        }

        if (attempts < 5) {
          attempts++;
          await Future<void>.delayed(const Duration(milliseconds: 120));
          return tryNavigate();
        }

        print('Contexto de navegação indisponível após tentativas');
      }

      tryNavigate();
    });
  }

  String _computeNavigationKey(Map<String, String> data) {
    return [
      data['type'] ?? '',
      data['senderId'] ?? '',
      data['relatedId'] ?? '',
      data['deepLink'] ?? '',
      data['screen'] ?? '',
    ].join('|');
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
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    print('📱 Local notifications configuradas');
  }

  /// 🔔 Solicita permissões (iOS principalmente)
  Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: false,
        sound: true,
        provisional: false,
      );

      print('🔐 Permissões iOS: ${settings.authorizationStatus}');
    } else {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      
      print('🔐 Permissões Android solicitadas');
    }
  }

  /// 📢 Cria notification channel no Android
  Future<void> _createAndroidChannel() async {
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      
      print('📢 Android channel criado: ${_channel.id}');
    }
  }

  /// Handler para mensagens em FOREGROUND (app aberto)
  void _setupForegroundHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('╔═══════════════════════════════════════');
      print('║ 📨 MENSAGEM RECEBIDA (FOREGROUND)');
      print('╠═══════════════════════════════════════');
      print('║ Message ID: ${message.messageId}');
      print('║ Sent Time: ${message.sentTime}');
      print('║ Data: ${message.data}');
      print('╚═══════════════════════════════════════');

      // Não mostra notificação se está na conversa atual
      final conversationId = message.data['conversationId'] ?? 
                            message.data['n_related_id'] ?? 
                            message.data['relatedId'];
      
      if (conversationId == _currentConversationId && conversationId != null) {
        print('⏭️  Ignorando notificação - já está no chat: $conversationId');
        return;
      }

      // Evita duplicatas no Android
      if (Platform.isAndroid && message.messageId == _lastMessageId) {
        print('⏭️  Ignorando notificação duplicada');
        return;
      }

      _lastMessageId = message.messageId ?? '';

      // Traduz notificação localmente
      final translation = await translateNotificationLocally(message);
      print('🌐 Tradução local aplicada: ${translation['body']}');
      
      // Create new RemoteMessage with translated notification
      final translatedMessage = RemoteMessage(
        messageId: message.messageId,
        data: message.data,
        notification: RemoteNotification(
          title: translation['title'],
          body: translation['body'],
          android: message.notification?.android,
          apple: message.notification?.apple,
        ),
        sentTime: message.sentTime,
        ttl: message.ttl,
        category: message.category,
        collapseKey: message.collapseKey,
        contentAvailable: message.contentAvailable,
        from: message.from,
        messageType: message.messageType,
        mutableContent: message.mutableContent,
        senderId: message.senderId,
        threadId: message.threadId,
      );

      // Mostra notificação local com tradução
      _showLocalNotification(translatedMessage);
    });
  }

  /// Handler para refresh de token
  void _setupTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print('[LOADING] Token FCM atualizado');
      try {
        final user = fire_auth.FirebaseAuth.instance.currentUser;
        if (user == null) {
          _pendingToken = newToken;
          _ensureAuthListener();
          print('[DEFER] Token aguardando login para sync');
          return;
        }
        // TODO: Sincronizar token com backend
        // UserPushNotificationService().syncToken(newToken);
      } catch (e) {
        print('Falha ao sincronizar token atualizado: $e');
      }
    });
  }

  void _ensureAuthListener() {
    if (_authListener != null) return;
    _authListener = fire_auth.FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && _pendingToken != null) {
        final token = _pendingToken!;
        _pendingToken = null;
        print('[RESUME] Sincronizando token pendente após login');
        // TODO: Sincronizar token
        // UserPushNotificationService().syncToken(token);
        _authListener?.cancel();
        _authListener = null;
      }
    });
  }

  /// 💬 Mostra notificação local (quando app está aberto)
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final notification = message.notification;
      final data = message.data;

      final title = notification?.title ?? data['title'] ?? 'Nova mensagem';
      final body = notification?.body ?? data['body'] ?? '';

      // Empacotar payload como JSON
      final payloadData = <String, dynamic>{
        'type': data['type'] ?? '',
        'relatedId': data['relatedId'] ?? data['n_related_id'],
        'senderId': data['senderId'] ?? data['n_sender_id'],
        'title': title,
        'body': body,
        'message': body,
        'deepLink': data['deepLink'] ?? data['deeplink'] ?? '',
      };
      final payloadJson = jsonEncode(payloadData);

      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      );

      await _localNotifications.show(
        notification.hashCode,
        title,
        body,
        notificationDetails,
        payload: payloadJson,
      );

      print('[OK] Notificação local exibida');
    } catch (e) {
      print('[ERROR] Erro ao mostrar notificação local: $e');
    }
  }

  /// 👆 Callback quando usuário toca na notificação
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      Map<String, dynamic> data;
      try {
        data = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        data = {
          'type': 'message',
          'relatedId': payload,
          'message': '',
          'senderId': '',
        };
      }
      navigateFromNotificationData(data);
    } catch (e) {
      print('Erro ao processar toque na notificação: $e');
    }
  }

  /// Define a conversa atual (para evitar notificações duplicadas)
  void setCurrentConversation(String? conversationId) {
    _currentConversationId = conversationId ?? '';
    print('[MARKER] Conversa atual: $_currentConversationId');
  }

  /// Limpa a conversa atual
  void clearCurrentConversation() {
    _currentConversationId = '';
    print('🔕 Conversa atual limpa');
  }

  /// Obtém o token FCM
  Future<String?> getToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        print('[TARGET] Token FCM obtido');
        return token;
      }
      return null;
    } catch (e) {
      print('[ERROR] Erro ao obter token FCM: $e');
      return null;
    }
  }

  /// Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      print('📤 Subscribed to topic: $topic');
    } catch (e) {
      print('[ERROR] Erro ao subscribir topic: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      print('📥 Unsubscribed from topic: $topic');
    } catch (e) {
      print('[ERROR] Erro ao unsubscribir topic: $e');
    }
  }

  /// 🔔 Mostra notificação no background
  /// Método estático para ser chamado do background handler
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    try {
      print('📨 Exibindo notificação background');
      
      final plugin = FlutterLocalNotificationsPlugin();
      
      // Configurar plugin
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      
      await plugin.initialize(
        const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
      );
      
      // Criar channel (Android)
      const channel = AndroidNotificationChannel(
        'partiu_high_importance',
        'Partiu Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.max,
        playSound: true,
        enableLights: true,
        enableVibration: true,
      );
      
      if (Platform.isAndroid) {
        await plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }
      
      // Flag silenciosa
      final silentFlag = (message.data['n_silent'] ?? '').toString().toLowerCase();
      final isSilent = ['1','true','yes'].contains(silentFlag);

      final title = message.data['title'] ?? 
                   message.notification?.title ?? 
                   'Partiu';
      final body = message.data['body'] ?? 
                  message.notification?.body ?? 
                  '';
      
      if (isSilent) {
        print('[SILENT] Notificação marcada como silenciosa, pulando exibição visual');
        return;
      }
      if (body.isEmpty) {
        print('[WARN] Body vazio, ignorando notificação');
        return;
      }
      
      print('[INFO] Título: $title');
      print('[INFO] Body: ${body.substring(0, body.length > 50 ? 50 : body.length)}...');
      
      // Payload JSON
      final payloadData = <String, dynamic>{
        'type': message.data['type'] ?? '',
        'relatedId': message.data['relatedId'] ?? message.data['n_related_id'],
        'senderId': message.data['senderId'] ?? message.data['n_sender_id'],
        'title': title,
        'body': body,
        'message': body,
        'deepLink': message.data['deepLink'] ?? message.data['deeplink'] ?? '',
      };
      final payloadJson = jsonEncode(payloadData);

      await plugin.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            enableLights: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        payload: payloadJson,
      );
      
      print('[OK] Notificação background exibida');
    } catch (e) {
      print('[ERROR] Erro ao exibir notificação background: $e');
    }
  }
}
