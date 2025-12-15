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
import 'package:partiu/shared/widgets/image_source_bottom_sheet.dart';
import 'package:partiu/screens/chat/services/application_removal_service.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/screens/chat/services/fee_auto_heal_service.dart';
import 'package:partiu/screens/chat/widgets/chat_app_bar_widget.dart';
import 'package:partiu/screens/chat/widgets/confirm_presence_widget.dart';
import 'package:partiu/screens/chat/widgets/dummy_presence_header.dart';
import 'package:partiu/screens/chat/widgets/message_list_widget.dart';
import 'package:partiu/screens/chat/widgets/user_presence_status_widget.dart';
import 'package:partiu/features/conversations/utils/conversation_styles.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:flutter/material.dart';
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
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _conversationDoc;
  String? _applicationId;
  bool _showRealPresenceWidget = false; // Controla quando mostrar o widget real
  
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

  void _confirmDeleteChat() {
    _chatService.confirmDeleteChat(
      context: context,
      userId: widget.user.userId,
      i18n: _i18n,
      progressDialog: _pr,
    );
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

  // Send text message (uses provided text to avoid race with controller clearing)
  Future<void> _sendTextMessage(String inputText) async {
    await _chatService.sendTextMessage(
      context: context,
      text: inputText,
      receiver: widget.user,
      i18n: _i18n,
      setIsSending: (isSending) => setState(() {}),
    );
    // Removido auto-scroll - ListView já posiciona naturalmente na mensagem mais recente
  }

  // Send image message
  Future<void> _sendImageMessage(File imageFile) async {
    await _chatService.sendImageMessage(
      context: context,
      imageFile: imageFile,
      receiver: widget.user,
      i18n: _i18n,
      progressDialog: _pr,
      setIsSending: (isSending) => setState(() {}),
    );
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

    // Removido auto-scroll inicial - ListView já inicia na posição correta das mensagens mais recentes

    // Stream do resumo de conversa (para fee lock) - usando cache
    _conversationDoc = _chatService.getConversationStream(widget.user.userId);
    debugPrint('✅ ChatScreen: Iniciando stream de conversa para userId: ${widget.user.userId}');
    
    // Carregar applicationId se for evento
    if (widget.isEvent && widget.eventId != null) {
      _loadApplicationId();
    }
    
  // B1.3: Proper stream subscription management via mixin
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;
  sub = _conversationDoc.listen((snap) {
      debugPrint('📬 ChatScreen: Recebeu snapshot de conversa');
      debugPrint('   - exists: ${snap.exists}');
      debugPrint('   - id: ${snap.id}');
      
      if (!snap.exists) {
        debugPrint('⚠️ Conversa não existe ainda');
        return;
      }
      final data = snap.data();
      debugPrint('   - data keys: ${data?.keys.toList()}');
      
      // A3.1: Auto-heal logic movida para background service (não bloqueia UI)
      if (data != null) {
  final currentUserId = AppState.currentUserId;
        if (currentUserId != null) {
          _feeAutoHealService.processAutoHeal(
            conversationId: snap.id,
            currentUserId: currentUserId,
            otherUserId: widget.user.userId,
            conversationData: data,
          );
        }
      }
      
      if (!mounted) return; // evita setState após dispose
    }, onError: (error) async {
      // Ignore permission errors (e.g., after logout) and stop listening
      final msg = error.toString();
      if (msg.contains('permission-denied') || msg.contains('PERMISSION_DENIED')) {
        try {
          await sub?.cancel();
        } catch (_) {}
      }
    });
    addSubscription(sub);

    // Check blocked user
    final localUserId = AppState.currentUserId;
    if (localUserId != null) {
      _chatService.checkBlockedUserStatus(
        remoteUserId: widget.user.userId,
        localUserId: localUserId,
      );
    }

    // Carregar applicationId se for evento
    if (widget.isEvent && widget.eventId != null) {
      _loadApplicationId();
    }

    // Listen for remote user updates (simplificado para evitar conversão complexa)
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
          ),
          // Espaço dinâmico: reduz quando teclado está aberto
          SizedBox(height: isKeyboardOpen ? 0 : 28),
        ],
      ),
    );
  }

  // Pagamento de fee removido. Campo _isProcessingPayment eliminado.
}
