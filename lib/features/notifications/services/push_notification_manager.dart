import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart' as fire_auth;
import 'package:partiu/features/notifications/helpers/app_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partiu/firebase_options.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/features/notifications/templates/notification_templates.dart';

/// 🔔 BACKGROUND MESSAGE HANDLER (top-level, necessário para iOS/Android)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('╔═══════════════════════════════════════════════════════');
  print('║ 📨 BACKGROUND MESSAGE RECEBIDA');
  print('╠═══════════════════════════════════════════════════════');
  print('║ Message ID: ${message.messageId}');
  print('║ Sent Time: ${message.sentTime}');
  print('║ Data: ${message.data}');
  print('║ Notification: ${message.notification?.toMap()}');
  print('╚═══════════════════════════════════════════════════════');

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
    final data = message.data;
    final nType = data['n_type'] ?? data['type'] ?? data['sub_type'] ?? '';
    
    // Se já veio com título e corpo do backend, usa direto (fallback)
    if (message.notification?.title != null && message.notification!.title!.isNotEmpty) {
      print('ℹ️ [Translator] Mensagem já formatada pelo backend');
      return message;
    }

    NotificationMessage? template;
    
    // Aplicar template baseado no tipo
    switch (nType) {
      // ===== MENSAGENS DE CHAT =====
      case 'chat_message':
      case 'new_message':
      case NOTIF_TYPE_MESSAGE:
        final senderName = data['n_sender_name'] ?? data['senderName'] ?? 'Alguém';
        final messagePreview = data['n_message'] ?? data['messagePreview'];
        template = NotificationTemplates.newMessage(
          senderName: senderName,
          messagePreview: messagePreview,
        );
        break;

      case 'event_chat_message':
        final senderName = data['n_sender_name'] ?? data['senderName'] ?? 'Alguém';
        final eventName = data['eventName'] ?? data['eventTitle'] ?? data['activityText'] ?? 'Evento';
        final emoji = data['emoji'] ?? data['eventEmoji'] ?? '🎉';
        final messagePreview = data['n_message'] ?? data['messagePreview'];
        template = NotificationTemplates.eventChatMessage(
          senderName: senderName,
          eventName: eventName,
          emoji: emoji,
          messagePreview: messagePreview,
        );
        break;

      // ===== ATIVIDADES =====
      case 'activity_created':
        final creatorName = data['n_sender_name'] ?? data['creatorName'] ?? 'Alguém';
        final activityName = data['activityName'] ?? data['eventTitle'] ?? 'Atividade';
        final emoji = data['emoji'] ?? '🎉';
        final commonInterests = (data['commonInterests'] as String?)?.split(',') ?? [];
        template = NotificationTemplates.activityCreated(
          creatorName: creatorName,
          activityName: activityName,
          emoji: emoji,
          commonInterests: commonInterests,
        );
        break;

      case 'activity_join_request':
        final requesterName = data['n_sender_name'] ?? data['requesterName'] ?? 'Alguém';
        final activityName = data['activityName'] ?? 'Atividade';
        final emoji = data['emoji'] ?? '🎉';
        template = NotificationTemplates.activityJoinRequest(
          requesterName: requesterName,
          activityName: activityName,
          emoji: emoji,
        );
        break;

      case 'activity_join_approved':
        final activityName = data['activityName'] ?? 'Atividade';
        final emoji = data['emoji'] ?? '🎉';
        template = NotificationTemplates.activityJoinApproved(
          activityName: activityName,
          emoji: emoji,
        );
        break;

      case 'activity_join_rejected':
        final activityName = data['activityName'] ?? 'Atividade';
        final emoji = data['emoji'] ?? '🎉';
        template = NotificationTemplates.activityJoinRejected(
          activityName: activityName,
          emoji: emoji,
        );
        break;

      case 'activity_new_participant':
        final participantName = data['n_sender_name'] ?? data['participantName'] ?? 'Alguém';
        final activityName = data['activityName'] ?? 'Atividade';
        final emoji = data['emoji'] ?? '🎉';
        template = NotificationTemplates.activityNewParticipant(
          participantName: participantName,
          activityName: activityName,
          emoji: emoji,
        );
        break;

      case 'activity_heating_up':
        final activityName = data['activityName'] ?? 'Atividade';
        final emoji = data['emoji'] ?? '🎉';
        final creatorName = data['n_sender_name'] ?? data['creatorName'] ?? 'Alguém';
        final participantCount = int.tryParse(data['n_participant_count'] ?? data['participantCount'] ?? '2') ?? 2;
        template = NotificationTemplates.activityHeatingUp(
          activityName: activityName,
          emoji: emoji,
          creatorName: creatorName,
          participantCount: participantCount,
        );
        break;

      case 'activity_expiring_soon':
        final activityName = data['activityName'] ?? 'Atividade';
        final emoji = data['emoji'] ?? '🎉';
        final hoursRemaining = int.tryParse(data['hoursRemaining'] ?? '1') ?? 1;
        template = NotificationTemplates.activityExpiringSoon(
          activityName: activityName,
          emoji: emoji,
          hoursRemaining: hoursRemaining,
        );
        break;

      case 'activity_canceled':
        final activityName = data['activityName'] ?? 'Atividade';
        final emoji = data['emoji'] ?? '🎉';
        template = NotificationTemplates.activityCanceled(
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
          count: count,
          lastViewedAt: lastViewedAt,
          viewerNames: viewerNames,
        );
        break;

      case 'review_pending':
      case 'new_review_received':
        final reviewerName = data['n_sender_name'] ?? data['reviewerName'] ?? 'Alguém';
        final rating = double.tryParse(data['rating'] ?? '5.0') ?? 5.0;
        final comment = data['comment'];
        template = NotificationTemplates.newReviewReceived(
          reviewerName: reviewerName,
          rating: rating,
          comment: comment,
        );
        break;

      // ===== SYSTEM & CUSTOM =====
      case 'alert':
      case 'system_alert':
        final alertMessage = data['message'] ?? data['body'] ?? 'Alerta';
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
        final userName = data['n_sender_name'] ?? data['userName'] ?? 'Alguém';
        final activityText = data['activityText'] ?? data['eventTitle'] ?? 'Evento';
        template = NotificationTemplates.custom(
          title: activityText,
          body: '$userName entrou no evento',
        );
        break;

      default:
        print('⚠️ [Translator] Tipo desconhecido: $nType');
        // Fallback para mensagem genérica
        final fallbackTitle = data['title'] ?? message.notification?.title ?? APP_NAME;
        final fallbackBody = data['body'] ?? message.notification?.body ?? 'Nova notificação';
        template = NotificationTemplates.custom(
          title: fallbackTitle,
          body: fallbackBody,
        );
    }

    // Se não encontrou template, retorna original
    if (template == null) {
      print('⚠️ [Translator] Template nulo, usando mensagem original');
      return message;
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
  
  // Limpar cache de IDs processados a cada 5 minutos
  Timer? _cleanupTimer;
  
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
      // ⚠️ badge: false aqui porque o app controla via BadgeService
      // (evita que push sobrescreva o contador correto)
      if (Platform.isIOS) {
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: false,  // App controla via BadgeService
          sound: true,
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
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        print('🚀 [PushManager] Initial message detectada (app aberto via notificação)');
        print('   - data: ${initialMessage.data}');
        
        // Aguarda um pouco para garantir que o contexto está disponível
        await Future.delayed(const Duration(milliseconds: 500));
        
        navigateFromNotificationData(initialMessage.data);
      }
    } catch (e) {
      print('⚠️ [PushManager] Erro ao processar initial message: $e');
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

      // 🔒 GUARD CLAUSE: Se a mensagem já vem com notification payload,
      // significa que o SO (iOS/Android) já exibiu automaticamente.
      // NÃO devemos criar notificação local para evitar duplicação.
      final hasSystemNotification = message.notification != null;
      final origin = message.data['n_origin'] ?? '';

      if (hasSystemNotification && origin == 'push') {
        print('🔕 [PushManager] Push já exibido pelo SO. Não criar notificação local.');
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
        // Limitar tamanho do Set para não crescer infinitamente
        if (_processedMessageIds.length > 100) {
          final oldIds = _processedMessageIds.take(50).toList();
          _processedMessageIds.removeAll(oldIds);
        }
      }

      // Não mostra notificação se está na conversa atual
      final conversationId = message.data['conversationId'] ?? 
                            message.data['n_related_id'] ?? 
                            message.data['relatedId'];

      final nType = message.data['n_type'] ?? message.data['type'] ?? '';
      
      if (nType == NOTIF_TYPE_MESSAGE && conversationId == _currentConversationId) {
        print('💬 [PushManager] Mensagem da conversa atual, não exibindo notificação');
        return;
      }

      // Verificar flag de silencioso
      final silentFlag = (message.data['n_silent'] ?? '').toString().toLowerCase();
      final isSilent = ['1', 'true', 'yes'].contains(silentFlag);

      if (isSilent) {
        print('🔇 [PushManager] Mensagem silenciosa, não exibindo notificação');
        return;
      }

      // ⚠️ SOMENTE se for DATA-ONLY (sem notification payload do SO)
      // Traduzir mensagem
      final translatedMessage = await _translateMessage(message);

      // Exibir notificação local
      await _showLocalNotification(translatedMessage);
    });
  }

  /// Setup listener para quando mensagem é clicada (app em background ou fechado)
  void _setupMessageOpenedHandler() {
    // Mensagem tocada quando app estava em background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('👆 [PushManager] Notificação clicada (app em background)');
      print('   - data: ${message.data}');
      
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
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    print('✅ [PushManager] Notificações locais configuradas');
  }

  /// Callback quando notificação local é tocada
  void _onNotificationTapped(NotificationResponse response) {
    print('👆 [PushManager] Notificação local clicada');
    print('   - payload: ${response.payload}');
    
    if (response.payload != null) {
      try {
        final data = json.decode(response.payload!) as Map<String, dynamic>;
        navigateFromNotificationData(data.map((k, v) => MapEntry(k, v.toString())));
      } catch (e) {
        print('⚠️ [PushManager] Erro ao processar payload: $e');
      }
    }
  }

  /// Navega baseado nos dados da notificação
  void navigateFromNotificationData(Map<String, dynamic> data) {
    print('🧭 [PushManager] Navegando baseado em notificação');
    print('   - data: $data');
    
    final nType = data['n_type'] ?? data['type'] ?? '';
    final nSenderId = data['n_sender_id'] ?? data['senderId'] ?? '';
    final nRelatedId = data['n_related_id'] ?? data['relatedId'] ?? '';
    final deepLink = data['deepLink'] ?? data['deep_link'] ?? '';
    final screen = data['screen'] ?? '';

    // Agenda para próximo frame quando contexto estará disponível
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Tenta encontrar o contexto pelo BuildContext do MaterialApp
      // Usa o context do rootNavigator para garantir que está disponível
      final context = WidgetsBinding.instance.renderViewElement;
      
      if (context == null || !context.mounted) {
        print('⚠️ [PushManager] Contexto não disponível ainda, tentando novamente...');
        Future.delayed(const Duration(milliseconds: 500), () {
          navigateFromNotificationData(data);
        });
        return;
      }

      AppNotifications().onNotificationClick(
        context,
        nType: nType,
        nSenderId: nSenderId,
        nRelatedId: nRelatedId,
        deepLink: deepLink,
        screen: screen,
      );
    });
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

    if (notification == null) {
      print('⚠️ [PushManager] Notification payload vazio, não exibindo');
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
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        notification.title ?? APP_NAME,
        notification.body ?? '',
        notificationDetails,
        payload: json.encode(data),
      );
      
      print('✅ [PushManager] Notificação local exibida');
      print('   - Título: ${notification.title}');
      print('   - Corpo: ${notification.body}');
    } catch (e) {
      print('❌ [PushManager] Erro ao exibir notificação: $e');
    }
  }

  /// 🔔 Mostra notificação no background (método estático)
  /// Método estático para ser chamado do background handler
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    try {
      print('📨 [PushManager] Exibindo notificação background');
      
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
      if (Platform.isAndroid) {
        await plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_channel);
      }
      
      // Exibir notificação
      final notification = message.notification;
      if (notification == null) {
        print('⚠️ [PushManager] Background notification sem payload');
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

      await plugin.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        notification.title ?? APP_NAME,
        notification.body ?? '',
        NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: json.encode(message.data),
      );
      
      print('✅ [PushManager] Background notification exibida');
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
