import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/common/mixins/stream_subscription_mixin.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/screens/chat/components/glimpse_chat_input.dart';
import 'package:partiu/screens/chat/models/message.dart';
import 'package:partiu/screens/chat/models/reply_snapshot.dart';
import 'package:partiu/shared/widgets/image_source_bottom_sheet.dart';
import 'package:partiu/screens/chat/services/application_removal_service.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/screens/chat/services/fee_auto_heal_service.dart';
import 'package:partiu/screens/chat/services/chat_analytics_service.dart'; // ✅ INSTRUMENTAÇÃO
import 'package:partiu/screens/chat/widgets/chat_app_bar_widget.dart';
import 'package:partiu/screens/chat/widgets/confirm_presence_widget.dart';
import 'package:partiu/screens/chat/widgets/dummy_presence_header.dart';
import 'package:partiu/screens/chat/widgets/message_list_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/features/notifications/services/push_notification_manager.dart';

class ChatScreenRefactored extends StatefulWidget {

  const ChatScreenRefactored({
    required this.user, 
    super.key, 
    this.optimisticIsVerified,
    this.isEvent = false,
    this.eventId,
  });
  /// Get user object
  final User user;
  /// Optimistic verification flag passed from conversation list to avoid initial false->true flicker
  final bool? optimisticIsVerified;
  final bool isEvent;
  final String? eventId;

  @override
  ChatScreenRefactoredState createState() => ChatScreenRefactoredState();
}

class ChatScreenRefactoredState extends State<ChatScreenRefactored>
  with StreamSubscriptionMixin {
  // Variables
  final _textController = TextEditingController();
  final _messagesController = ScrollController();
  final _chatService = ChatService(); // B1.1: Agora usa singleton automaticamente
  final _applicationRemovalService = ApplicationRemovalService();
  final _feeAutoHealService = FeeAutoHealService();
  // ✅ OTIMIZADO: Removido stream de conversa - usando get() único
  // late Stream<DocumentSnapshot<Map<String, dynamic>>> _conversationDoc;
  Map<String, dynamic>? _conversationData; // Dados carregados via get()
  String? _applicationId;
  bool _showRealPresenceWidget = false; // Controla quando mostrar o widget real
  
  // 🆕 Estado de reply
  ReplySnapshot? _replySnapshot;
  void Function(String messageId)? _scrollToMessageFunc;
  
  // B1.3: Conversa é ouvida via StreamSubscriptionMixin (sem leaks)
  
  // B1.2: Cached computed properties para evitar recálculo no build()
  late AppLocalizations _i18n;
  late ProgressDialog _pr;
  bool _initialized = false;
  
  // B1.2: Lazy initialization method
  void _ensureInitialized() {
    if (!_initialized) {
      _i18n = AppLocalizations.of(context);
      _pr = ProgressDialog(context);
      _initialized = true;
    }
  }

  /// Get image from camera / gallery
  Future<void> _getImage() async {
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => ImageSourceBottomSheet(
          onImageSelected: (file) async {
            if (mounted) {
              await _sendImageMessage(file);
            }
          },
          cropToSquare: false, // Chat não precisa de crop quadrado
          minWidth: 1200,
          minHeight: 1200,
          quality: 80,
        ),
      );
    } catch (e) {
      // Ignore image picker errors
    }
  }

  // 🆕 Método para iniciar reply após long press
  Future<void> _handleReplyMessage(Message message) async {
    if (!mounted) return;

    // Inicia reply direto (sem abrir um segundo Cupertino).
    // ⚠️ Importante: NÃO usar widget.user.fullName aqui, pois em chats de evento
    // esse valor pode ser o nome do evento (e não do autor real da mensagem).
    final senderName = await _resolveReplySenderName(message);

    if (!mounted) return;

    setState(() {
      _replySnapshot = ReplySnapshot(
        messageId: message.id,
        senderId: message.senderId ?? '',
        senderName: senderName,
        text: message.text,
        imageUrl: message.imageUrl,
        type: message.type,
      );
    });

    HapticFeedback.mediumImpact();
  }

  Future<String> _resolveReplySenderName(Message message) async {
    final senderId = (message.senderId ?? '').trim();
    if (senderId.isEmpty) return '';

    if (senderId == AppState.currentUserId) {
      return _i18n.translate('you');
    }

    // 1) Tenta cache reativo local (rápido, sem await)
    final cached = UserStore.instance.getNameNotifier(senderId).value?.trim() ?? '';
    if (cached.isNotEmpty) return cached;

    // 2) Fallback: busca no Firestore Users (para não salvar nome errado no snapshot)
    final data = await UserRepository().getUserById(senderId);
    final fetched = (data?['fullName'] as String?)?.trim() ?? (data?['fullname'] as String?)?.trim() ?? '';
    return fetched;
  }
  
  // 🆕 Método para cancelar reply
  void _handleCancelReply() {
    setState(() {
      _replySnapshot = null;
    });
  }
  
  // 🆕 Método para scroll até mensagem original
  void _handleScrollToMessage(String messageId) {
    _scrollToMessageFunc?.call(messageId);
  }

  void _safeSetState(VoidCallback action) {
    if (!mounted) return;
    setState(action);
  }

  // Send text message (uses provided text to avoid race with controller clearing)
  Future<void> _sendTextMessage(String inputText) async {
    await _chatService.sendTextMessage(
      context: context,
      text: inputText,
      receiver: widget.user,
      i18n: _i18n,
      setIsSending: (isSending) {
        if (!mounted) return;
        setState(() {});
      },
      replySnapshot: _replySnapshot, // 🆕 Passar snapshot de reply
    );
    
    // 🆕 Limpar reply após enviar
    if (_replySnapshot != null && mounted) {
      setState(() {
        _replySnapshot = null;
      });
    }
    // Removido auto-scroll - ListView já posiciona naturalmente na mensagem mais recente
  }

  // Send image message
  Future<void> _sendImageMessage(File imageFile) async {
    if (!mounted) return;
    await _chatService.sendImageMessage(
      context: context,
      imageFile: imageFile,
      receiver: widget.user,
      i18n: _i18n,
      progressDialog: _pr,
      setIsSending: (isSending) => _safeSetState(() {}),
      replySnapshot: _replySnapshot, // 🆕 Passar snapshot de reply
    );
    
    // 🆕 Limpar reply após enviar
    if (_replySnapshot != null) {
      _safeSetState(() {
        _replySnapshot = null;
      });
    }
    // Removido auto-scroll - ListView já posiciona naturalmente na mensagem mais recente
  }
  
    @override
  @override
  void initState() {
    super.initState();

    // 🔔 Define conversa atual para o PushNotificationManager
    // Isso evita notificações duplicadas enquanto está nesta tela
    // Para conversas 1-1, o conversationId é o userId do outro usuário
    final conversationId = widget.user.userId;
    PushNotificationManager.instance.setCurrentConversation(conversationId);
    debugPrint('🔔 PushManager: Conversa atual definida: $conversationId');

    // 🔍 DEBUG: Log completo do user object
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🔍 ChatScreen initState - Debug User Object:');
    debugPrint('   - userId: "${widget.user.userId}"');
    debugPrint('   - fullName: "${widget.user.fullName}"');
    debugPrint('   - profilePhoto: "${widget.user.photoUrl}"');
    debugPrint('   - isEvent: ${widget.isEvent}');
    debugPrint('   - eventId: ${widget.eventId}');
    debugPrint('   - userId.isEmpty: ${widget.user.userId.isEmpty}');
    debugPrint('   - userId.length: ${widget.user.userId.length}');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // Validar userId antes de inicializar streams
    if (widget.user.userId.isEmpty) {
      debugPrint('⚠️ ChatScreen: userId está vazio, não iniciando streams');
      return;
    }

    // 📊 ANALYTICS: Log de abertura do chat para medir performance
    ChatAnalyticsService.instance.logChatOpen(
      chatId: widget.user.userId,
      chatType: widget.isEvent ? 'event' : '1:1',
      cacheHit: false, // Será true quando implementar cache hit detection
      initialMessagesRendered: 0, // Atualizado após render
    );

    // Removido auto-scroll inicial - ListView já inicia na posição correta das mensagens mais recentes

    // ✅ OTIMIZADO: Usar get() único em vez de stream para metadata da conversa
    // Stream removido - economiza ~1 read por segundo enquanto chat está aberto
    _loadConversationData();
    debugPrint('✅ ChatScreen: Carregando conversa via get() para userId: ${widget.user.userId}');
    
    // Carregar applicationId se for evento
    if (widget.isEvent && widget.eventId != null) {
      _loadApplicationId();
    }

    // Check blocked user
    final localUserId = AppState.currentUserId;
    if (localUserId != null) {
      _chatService.checkBlockedUserStatus(
        remoteUserId: widget.user.userId,
        localUserId: localUserId,
      );
    }

    // ✅ OTIMIZADO: Stream de presença removido - usar getUserOnce() se necessário
    // _chatService.getUserUpdates(widget.user.userId).listen((userModel) {
    //   // Update do remote user pode ser implementado posteriormente se necessário
    // });
    
    // Listener reativo de bloqueios
    BlockService.instance.addListener(_onBlockedUsersChanged);
  }
  
  void _onBlockedUsersChanged() {
    if (!mounted) return;
    // Força rebuild da tela quando houver mudança nos bloqueios
    setState(() {});
  }

  /// ✅ OTIMIZADO: Carrega dados da conversa com get() único (em vez de stream)
  /// Economiza reads do Firestore - stream gerava ~1 read/segundo
  Future<void> _loadConversationData() async {
    try {
      final data = await _chatService.getConversationOnce(widget.user.userId);
      
      if (!mounted) return;
      
      if (data == null) {
        debugPrint('⚠️ Conversa não existe ainda');
        return;
      }
      
      debugPrint('📬 ChatScreen: Dados da conversa carregados via get()');
      debugPrint('   - data keys: ${data.keys.toList()}');
      
      _conversationData = data;
      
      // A3.1: Auto-heal logic (executar uma vez ao abrir)
      final currentUserId = AppState.currentUserId;
      if (currentUserId != null) {
        _feeAutoHealService.processAutoHeal(
          conversationId: widget.user.userId,
          currentUserId: currentUserId,
          otherUserId: widget.user.userId,
          conversationData: data,
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar conversa: $e');
    }
  }

  /// Carrega applicationId do usuário atual para este evento
  Future<void> _loadApplicationId() async {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null || widget.eventId == null) return;

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('EventApplications')
          .where('eventId', isEqualTo: widget.eventId)
          .where('userId', isEqualTo: currentUserId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        setState(() {
          _applicationId = querySnapshot.docs.first.id;
        });
        debugPrint('✅ ApplicationId carregado: $_applicationId');
      } else {
        debugPrint('⚠️ Nenhuma application encontrada para este evento');
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar applicationId: $e');
    }
  }

  @override
  void dispose() {
    // 🔔 Limpa conversa atual do PushNotificationManager
    PushNotificationManager.instance.setCurrentConversation(null);
    debugPrint('🔔 PushManager: Conversa atual limpa');
    
    BlockService.instance.removeListener(_onBlockedUsersChanged);
    _textController.dispose();
    _messagesController.dispose();
    _feeAutoHealService.dispose(); // A3.1: Cleanup do auto-heal service
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    // B1.2: Lazy initialization para evitar recálculos
    _ensureInitialized();
    
    // Detecta se o teclado está aberto
    final viewInsets = MediaQuery.of(context).viewInsets;
    final isKeyboardOpen = viewInsets.bottom > 0;
    
    return Scaffold(
      backgroundColor: GlimpseColors.bgColorLight,
      appBar: ChatAppBarWidget(
        user: widget.user,
        chatService: _chatService,
        applicationRemovalService: _applicationRemovalService,
        onDeleteChat: () {
          _chatService.confirmDeleteChat(
            context: context,
            userId: widget.user.userId,
            i18n: _i18n,
            progressDialog: _pr,
          );
        },
        onRemoveApplicationSuccess: () {
          if (mounted) Navigator.of(context).pop();
        },
        optimisticIsVerified: widget.optimisticIsVerified,
      ),
      body: Column(
        children: <Widget>[
          /// Widget de confirmação de presença (apenas para eventos)
          if (widget.isEvent && widget.eventId != null)
            _showRealPresenceWidget && _applicationId != null
                ? ConfirmPresenceWidget(
                    applicationId: _applicationId!,
                    eventId: widget.eventId!,
                  )
                : DummyPresenceHeader(
                    onTap: () {
                      setState(() => _showRealPresenceWidget = true);
                    },
                  ),

          /// Show messages
          Expanded(
            child: MessageListWidget(
              remoteUserId: widget.isEvent
                  ? "event_${widget.eventId}"
                  : widget.user.userId,
              remoteUser: widget.user,
              chatService: _chatService,
              messagesController: _messagesController,
              onMessageLongPress: _handleReplyMessage, // 🆕 Callback para reply
              onReplyTap: _handleScrollToMessage, // 🆕 Callback para scroll
              onScrollToMessageRegistered: (scrollFunc) {
                _scrollToMessageFunc = scrollFunc;
              },
            ),
          ),

          /// Payment lock removido. Apenas bloqueio por block de usuário permanece.
          GlimpseChatInput(
            textController: _textController,
            // Apenas bloqueio por usuário bloqueado (desativado para eventos)
            isBlocked: widget.isEvent ? false : _chatService.isRemoteUserBlocked,
            blockedMessage: _i18n.translate('you_have_blocked_this_user_you_can_not_send_a_message'),
            onSendText: _sendTextMessage,
            onSendImage: () async { await _getImage(); },
            replySnapshot: _replySnapshot, // 🆕 Passar dados de reply
            onCancelReply: _handleCancelReply, // 🆕 Callback para cancelar
            isOwnReply: _replySnapshot?.senderId == AppState.currentUserId, // 🆕 Se é reply de msg própria
          ),
          // Espaço dinâmico: reduz quando teclado está aberto
          SizedBox(height: isKeyboardOpen ? 0 : 28),
        ],
      ),
    );
  }

  // Pagamento de fee removido. Campo _isProcessingPayment eliminado.
}
