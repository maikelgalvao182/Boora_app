import 'dart:async';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/helpers/app_localizations.dart' as helpers;
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/screens/chat/models/message.dart';
import 'package:partiu/screens/chat/models/reply_snapshot.dart';
import 'package:partiu/screens/chat/services/chat_message_deletion_service.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/screens/chat/services/chat_analytics_service.dart'; // ✅ INSTRUMENTAÇÃO
import 'package:partiu/screens/chat/widgets/glimpse_chat_bubble.dart';
import 'package:partiu/shared/widgets/my_circular_progress.dart';
import 'package:partiu/shared/widgets/auto_scroll_list_handler.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:flutter/material.dart';

// Model para cache de mensagem processada
class _ProcessedMessage {

  const _ProcessedMessage({
    required this.id,
    required this.message,
    required this.isUserSender,
    required this.time,
    required this.isRead,
    required this.isSystem, this.imageUrl,
    this.type,
    this.params,
    this.senderId,
    this.avatarUrl,
    this.fullName,
    this.replyTo, // 🆕
    required this.isDeleted,
    required this.signature,
  });
  final String id;
  final String message;
  final bool isUserSender;
  final String time;
  final bool isRead;
  final String? imageUrl;
  final bool isSystem;
  final String? type;
  final Map<String, dynamic>? params;
  final String? senderId;
  final String? avatarUrl;
  final String? fullName;
  final ReplySnapshot? replyTo; // 🆕
  final bool isDeleted;
  final int signature;
}

class MessageListWidget extends StatefulWidget {

  const MessageListWidget({
    required this.remoteUserId, required this.remoteUser, required this.chatService, required this.messagesController, super.key,
    this.onMessageLongPress, // 🆕 Callback para long press
    this.onReplyTap, // 🆕 Callback para tap no reply
    this.onScrollToMessageRegistered, // 🆕 Callback para registrar função de scroll
  });
  final String remoteUserId;
  final User remoteUser;
  final ChatService chatService;
  final ScrollController messagesController;
  final Function(Message)? onMessageLongPress; // 🆕
  final Function(String messageId)? onReplyTap; // 🆕
  final Function(void Function(String messageId) scrollToMessage)? onScrollToMessageRegistered; // 🆕

  @override
  State<MessageListWidget> createState() => _MessageListWidgetState();
}

class _MessageListWidgetState extends State<MessageListWidget> {
  // Cache para mensagens processadas
  final Map<String, _ProcessedMessage> _messageCache = {};
  
  // 🆕 Map para rastrear índices de mensagens (para scroll)
  final Map<String, int> _messageIndexMap = {};
  
  // 🆕 Mensagem destacada (highlight temporário)
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  // 🆕 Deleção otimista (some da UI instantaneamente)
  final Set<String> _optimisticallyDeletedMessageIds = <String>{};
    final ChatMessageDeletionService _messageDeletionService =
      ChatMessageDeletionService();
  
  // ✅ INSTRUMENTAÇÃO: Analytics service
  final ChatAnalyticsService _analytics = ChatAnalyticsService.instance;
  bool _hasLoggedFirstPaint = false;
  bool _firstSnapshotWasCache = false;
  int _snapshotCount = 0;
  
  // State for messages
  List<Message>? _messages;
  List<Message>? _allMessages; // Armazena todas as mensagens antes da filtragem
  bool _isLoading = true;
  String? _error;
  StreamSubscription? _subscription;
  int _retryCount = 0;
  static const int _maxRetries = 15;

  @override
  void initState() {
    super.initState();
    _initStream();
    _initBlockListener();
    // 🆕 Registrar função de scroll para ser acessada externamente
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onScrollToMessageRegistered?.call(scrollToMessage);
    });
  }

  @override
  void didUpdateWidget(MessageListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remoteUserId != widget.remoteUserId) {
      _subscription?.cancel();
      _messageCache.clear();
      _messages = null;
      _isLoading = true;
      _error = null;
      _retryCount = 0;
      _initStream();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _highlightTimer?.cancel(); // 🆕 Cancelar timer de highlight
    BlockService.instance.removeListener(_onBlockedUsersChanged);
    
    // ✅ INSTRUMENTAÇÃO: Desregistrar stream ao fechar
    _analytics.unregisterMessageStream(widget.remoteUserId);
    
    super.dispose();
  }
  
  // 🆕 Método público para scroll até uma mensagem (chamado via GlobalKey)
  void scrollToMessage(String messageId, {bool highlight = false}) {
    final index = _messageIndexMap[messageId];
    
    if (index != null && _messages != null) {
      // Calcular posição aproximada (lista reversa)
      final reversedIndex = _messages!.length - 1 - index;
      
      // Scroll suave
      widget.messagesController.animateTo(
        reversedIndex * 80.0, // Estimativa de altura por item
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      
      // Highlight temporário
      if (highlight) {
        setState(() => _highlightedMessageId = messageId);
        _highlightTimer?.cancel();
        _highlightTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() => _highlightedMessageId = null);
          }
        });
      }
    } else {
      debugPrint('⚠️ Mensagem $messageId não encontrada na lista');
    }
  }
  
  /// Listener para re-filtrar mensagens quando bloqueios mudam
  void _initBlockListener() {
    final isEventChat = widget.remoteUserId.startsWith('event_');
    if (!isEventChat) return; // Apenas para chats de grupo
    
    // ⬅️ ESCUTA BlockService via ChangeNotifier (REATIVO INSTANTÂNEO)
    BlockService.instance.addListener(_onBlockedUsersChanged);
  }
  
  /// Callback quando BlockService muda (via ChangeNotifier)
  void _onBlockedUsersChanged() {
    debugPrint('🔄 Bloqueios mudaram via ChangeNotifier, re-filtrando mensagens...');
    _refilterMessages();
  }
  
  /// Re-filtra mensagens removendo usuários bloqueados
  void _refilterMessages() {
    if (_allMessages == null) return;
    
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) return;
    
    final beforeCount = _allMessages!.length;
    final filteredMessages = _allMessages!.where((msg) {
      // Não filtrar minhas próprias mensagens
      if (msg.senderId == currentUserId) return true;
      
      // Se não tem senderId, manter a mensagem
      if (msg.senderId == null || msg.senderId!.isEmpty) return true;
      
      // Filtrar mensagens de usuários bloqueados
      final isBlocked = BlockService().isBlockedCached(currentUserId, msg.senderId!);
      return !isBlocked;
    }).toList();
    
    final filteredCount = beforeCount - filteredMessages.length;
    if (filteredCount > 0) {
      debugPrint('🚫 $filteredCount mensagens removidas após mudança de bloqueio');
    }
    
    if (mounted) {
      setState(() {
        _messages = filteredMessages;
      });
    }
  }

  void _initStream() {
    _subscription?.cancel();
    
    debugPrint("🔄 MessageListWidget: Initializing stream for ${widget.remoteUserId} (Attempt ${_retryCount + 1})");
    
    // ✅ INSTRUMENTAÇÃO: Registrar stream de mensagens
    _analytics.registerMessageStream(widget.remoteUserId);
    _snapshotCount = 0;
    
    _subscription = widget.chatService.getMessages(widget.remoteUserId).listen(
      (messages) {
        _snapshotCount++;
        debugPrint("📋 MessageListWidget: Received ${messages.length} messages");
        
        // ✅ INSTRUMENTAÇÃO: Log do snapshot
        // Primeiro snapshot geralmente é do cache Hive (se existir)
        final isFirstSnapshot = _snapshotCount == 1;
        if (isFirstSnapshot) {
          _firstSnapshotWasCache = messages.isNotEmpty; // Assume cache hit se veio rápido com dados
        }
        
        _analytics.logStreamSnapshot(
          chatId: widget.remoteUserId,
          docsInSnapshot: messages.length,
          isFromCache: isFirstSnapshot && _firstSnapshotWasCache,
        );
        
        // Confirmar deleções otimistas: quando o backend marcar como deleted
        // (ou a doc sumir), removemos do set local.
        final incomingIds = messages.map((m) => m.id).toSet();
        final byId = <String, Message>{for (final m in messages) m.id: m};
        _optimisticallyDeletedMessageIds.removeWhere(
          (id) => !incomingIds.contains(id) || (byId[id]?.isDeleted == true),
        );

        // Armazenar todas as mensagens para re-filtragem futura
        _allMessages = messages;
        
        // 🚫 Filtrar mensagens de usuários bloqueados (apenas em chats de grupo/evento)
        final isEventChat = widget.remoteUserId.startsWith('event_');
        final currentUserId = AppState.currentUserId;
        
        List<Message> filteredMessages = messages;
        if (isEventChat && currentUserId != null) {
          final beforeCount = messages.length;
          filteredMessages = messages.where((msg) {
            // Não filtrar minhas próprias mensagens
            if (msg.senderId == currentUserId) return true;
            
            // Se não tem senderId, manter a mensagem
            if (msg.senderId == null || msg.senderId!.isEmpty) return true;
            
            // Filtrar mensagens de usuários bloqueados
            final isBlocked = BlockService().isBlockedCached(currentUserId, msg.senderId!);
            if (isBlocked) {
              debugPrint('🚫 Mensagem de ${msg.senderId} bloqueada');
            }
            return !isBlocked;
          }).toList();
          
          final filteredCount = beforeCount - filteredMessages.length;
          if (filteredCount > 0) {
            debugPrint('🚫 $filteredCount mensagens filtradas (usuários bloqueados)');
          }
        }
        
        if (mounted) {
          setState(() {
            _messages = filteredMessages;
            _isLoading = false;
            _error = null;
            _retryCount = 0; // Reset retries on success
          });
        }
      },
      onError: (error) {
        debugPrint("❌ MessageListWidget: Stream error: $error");
        
        // Check for permission denied
        final isPermissionError = error.toString().contains('permission-denied') || 
                                  error.toString().contains('PERMISSION_DENIED');
                                  
        if (isPermissionError && _retryCount < _maxRetries) {
          debugPrint("⏳ MessageListWidget: Permission denied. Retrying in 1s... (${_retryCount + 1}/$_maxRetries)");
          _retryCount++;
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) _initStream();
          });
        } else {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _error = error.toString();
            });
          }
        }
      },
    );
  }

  Future<void> _deleteMessageOptimistically(String messageId) async {
    if (messageId.isEmpty) return;

    final i18n = AppLocalizations.of(context);

    setState(() {
      _optimisticallyDeletedMessageIds.add(messageId);
      _highlightedMessageId = null;
    });

    ToastService.showInfo(
      message: i18n.translate('message_deleted'),
      duration: const Duration(seconds: 2),
    );

    try {
      await _messageDeletionService.deleteMessageForEveryone(
        conversationId: widget.remoteUserId,
        messageId: messageId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _optimisticallyDeletedMessageIds.remove(messageId);
      });

      ToastService.showError(
        message: i18n.translate('an_error_has_occurred'),
      );
    }
  }
  
  // Pre-processar mensagens para evitar processamento no build
  List<_ProcessedMessage> _processMessages(
    List<Message> messages,
    AppLocalizations i18n,
  ) {
    final processedMessages = <_ProcessedMessage>[];
    // Get current locale for timeago formatting
    final currentLocale = i18n.translate('lang');
    
    // 🔥 IMPORTANTE: Limpar cache de mensagens que não existem mais
    final currentIds = messages.map((m) => m.id).toSet();
    _messageCache.removeWhere((id, _) => !currentIds.contains(id));
    
    for (final message in messages) {
      final docId = message.id;

      final isSoftDeleted = message.isDeleted || _optimisticallyDeletedMessageIds.contains(docId);
      final signature = Object.hash(
        message.text,
        message.imageUrl,
        message.type,
        message.isRead,
        isSoftDeleted,
        message.replyTo,
      );
      
      // Verificar cache, mas respeitar updates (ex.: soft delete)
      final cached = _messageCache[docId];
      if (cached != null && cached.signature == signature) {
        processedMessages.add(cached);
        continue;
      }
      
      // Formatar tempo uma única vez usando TimeAgoHelper com i18n
      var messageTime = '';
      if (message.timestamp != null) {
        messageTime = TimeAgoHelper.format(context, timestamp: message.timestamp!);
      }
      
      // Debug logs temporários
      print('[MessageListWidget] Processing message:');
      print('  - id: $docId');
      print('  - text: ${message.text}');
      print('  - senderId: ${message.senderId}');
      print('  - receiverId: ${message.receiverId}');
      print('  - currentUserId: ${AppState.currentUserId}');
      
      // ✅ Lógica correta do advanced-dating:
      // Uma mensagem é "enviada" (isSender=true) se senderId == currentUserId
      // Isso funciona tanto para mensagens novas quanto antigas (com fallback para user_id)
      final isSender = message.senderId == AppState.currentUserId;
      
      print('  - ✅ FINAL DECISION: isSender = $isSender');

      // Determine avatar/name for received messages
      String? avatarUrl;
      String? fullName;
      
      final bool isEventChat = widget.remoteUserId.startsWith('event_');

      if (!isSender) {
        // If 1-1 chat (not event), use remoteUser info
        if (!isEventChat) {
           avatarUrl = widget.remoteUser.photoUrl;
           final candidate = (widget.remoteUser.fullName ?? '').trim();
           if (candidate.isNotEmpty) {
             final normalized = candidate.toLowerCase();
             final isPlaceholder = normalized == 'unknown user' ||
                 normalized == 'unknow user' ||
                 normalized == 'usuário' ||
                 normalized == 'usuario';
             if (!isPlaceholder) {
               fullName = candidate;
             }
           }
        }
        // For event chat, we rely on StableAvatar fetching by senderId
      }
      
      final processedMessage = _ProcessedMessage(
        id: docId,
        message: isSoftDeleted ? i18n.translate('message_deleted_placeholder') : (message.text ?? ''),
        isUserSender: isSender,
        time: messageTime,
        isRead: message.isRead ?? false,
        imageUrl: (!isSoftDeleted && message.type == 'image') ? message.imageUrl : null,
        isSystem: message.type == 'system',
        type: isSoftDeleted ? 'text' : message.type,
        params: message.params,
        senderId: message.senderId,
        avatarUrl: avatarUrl,
        fullName: fullName,
        replyTo: message.replyTo, // 🆕 Passar dados de reply
        isDeleted: isSoftDeleted,
        signature: signature,
      );
      
      // Adicionar ao cache
      _messageCache[docId] = processedMessage;
      processedMessages.add(processedMessage);
    }
    
    return processedMessages;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    // Show error if any (and not retrying)
    if (_error != null) {
       return Center(
         child: Column(
           mainAxisAlignment: MainAxisAlignment.center,
           children: [
             const Icon(Icons.error_outline, color: Colors.red, size: 48),
             const SizedBox(height: 16),
             Text(
               i18n.translate('error') + ': ' + _error!,
               textAlign: TextAlign.center,
               style: const TextStyle(color: Colors.grey),
             ),
             TextButton(
               onPressed: () {
                 setState(() {
                   _isLoading = true;
                   _error = null;
                   _retryCount = 0;
                 });
                 _initStream();
               },
               child: Text(i18n.translate('retry')),
             )
           ],
         ),
       );
    }

    // Show loading
    if (_isLoading || _messages == null) {
      debugPrint("⏳ No data yet, showing loading spinner");
      return const Center(child: MyCircularProgress());
    }
    
    // 📊 ANALYTICS: Log do tempo até primeiro paint (uma vez só)
    if (!_hasLoggedFirstPaint && _messages!.isNotEmpty) {
      _hasLoggedFirstPaint = true;
      _analytics.logTimeToFirstPaint(
        chatId: widget.remoteUserId,
        cacheHit: _firstSnapshotWasCache,
        messagesRendered: _messages!.length,
      );
    }
    
    // Aplicar deleção otimista sem mexer no stream: filtra no build.
    final visibleMessages = _messages!;

    final messageCount = visibleMessages.length;
    debugPrint("📋 Rendering $messageCount messages");

    // Para chat estilo WhatsApp que inicia nas mensagens mais recentes:
    // - Mensagens vêm do Firestore em ordem ascending (msg1, msg2, msg3, msg4, msg5)
    // - reverse: true no ListView faz a lista crescer de baixo para cima automaticamente
    // - Resultado: mensagens mais recentes aparecem na parte inferior e o chat inicia lá
    final processedMessages = _processMessages(visibleMessages, i18n);

    return AutoScrollListHandler(
      controller: widget.messagesController,
      itemCount: processedMessages.length,
      isReverse: true,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => false, // Allow bubbling
        child: ListView.builder(
          key: const PageStorageKey('chat-list'), // ✅ Static key to prevent rebuilds
          controller: widget.messagesController,
          physics: const BouncingScrollPhysics(
            decelerationRate: ScrollDecelerationRate.fast,
          ),
          reverse: true,
          itemCount: processedMessages.length,
          itemBuilder: (context, index) {
            final reversedIndex = processedMessages.length - 1 - index;
            final processedMsg = processedMessages[reversedIndex];
            
            // 🆕 Atualizar map de índices para scroll
            _messageIndexMap[processedMsg.id] = reversedIndex;
            
            // 🆕 Verificar se está highlighted
            final isHighlighted = _highlightedMessageId == processedMsg.id;

            return RepaintBoundary(
              key: ValueKey(processedMsg.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: isHighlighted
                    ? BoxDecoration(
                        color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                child: GlimpseChatBubble(
                  message: processedMsg.message,
                  isUserSender: processedMsg.isUserSender,
                  time: processedMsg.time,
                  isRead: processedMsg.isRead,
                  imageUrl: processedMsg.imageUrl,
                  isSystem: processedMsg.isSystem,
                  type: processedMsg.type,
                  params: processedMsg.params,
                  messageId: processedMsg.id,
                  senderId: processedMsg.senderId,
                  avatarUrl: processedMsg.avatarUrl,
                  fullName: processedMsg.fullName,
                  replyTo: processedMsg.replyTo, // 🆕 Passar dados de reply
                  onLongPress: () { // 🆕 Long press para reply
                    // Buscar a mensagem original para passar ao callback
                    final originalMessage = _messages?.firstWhere(
                      (m) => m.id == processedMsg.id,
                      orElse: () => Message(
                        id: processedMsg.id,
                        userId: processedMsg.senderId ?? '',
                        senderId: processedMsg.senderId,
                        type: processedMsg.type ?? 'text',
                        text: processedMsg.message,
                        imageUrl: processedMsg.imageUrl,
                      ),
                    );
                    widget.onMessageLongPress?.call(originalMessage!);
                  },
                  onReplyTap: processedMsg.replyTo != null 
                      ? () => widget.onReplyTap?.call(processedMsg.replyTo!.messageId) 
                      : null, // 🆕 Tap no reply
                    onDelete: (!processedMsg.isSystem &&
                        processedMsg.isUserSender &&
                        !processedMsg.isDeleted &&
                        processedMsg.id.isNotEmpty)
                      ? () => _deleteMessageOptimistically(processedMsg.id)
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
