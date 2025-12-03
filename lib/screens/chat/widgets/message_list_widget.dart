import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/screens/chat/models/message.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/screens/chat/widgets/glimpse_chat_bubble.dart';
import 'package:partiu/shared/widgets/my_circular_progress.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

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
}

class MessageListWidget extends StatefulWidget {

  const MessageListWidget({
    required this.remoteUserId, required this.remoteUser, required this.chatService, required this.messagesController, super.key,
  });
  final String remoteUserId;
  final User remoteUser;
  final ChatService chatService;
  final ScrollController messagesController;

  @override
  State<MessageListWidget> createState() => _MessageListWidgetState();
}

class _MessageListWidgetState extends State<MessageListWidget> {
  // Cache para mensagens processadas
  final Map<String, _ProcessedMessage> _messageCache = {};
  
  // Pre-processar mensagens para evitar processamento no build
  List<_ProcessedMessage> _processMessages(
    List<Message> messages,
    AppLocalizations i18n,
  ) {
    final processedMessages = <_ProcessedMessage>[];
    // Get current locale for timeago formatting
    final currentLocale = i18n.translate('lang');
    
    for (final message in messages) {
      final docId = message.id;
      
      // Verificar se já está em cache
      if (_messageCache.containsKey(docId)) {
        processedMessages.add(_messageCache[docId]!);
        continue;
      }
      
      // Formatar tempo uma única vez
      var messageTime = '';
      try {
        if (message.timestamp != null) {
          // Use current locale for time formatting
          messageTime = timeago.format(message.timestamp!, locale: currentLocale);
        }
      } catch (e) {
        // Ignore timestamp formatting errors
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
      
      final processedMessage = _ProcessedMessage(
        id: docId,
        message: message.text ?? '',
        isUserSender: isSender,
        time: messageTime,
        isRead: message.isRead ?? false,
        imageUrl: message.type == 'image' ? message.imageUrl : null,
        isSystem: message.type == 'system',
        type: message.type,
        params: message.params,
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
    
    return StreamBuilder<List<Message>>(
      stream: widget.chatService.getMessages(widget.remoteUserId),
      builder: (context, snapshot) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        debugPrint("🔄 MessageListWidget rebuild at $timestamp");
        debugPrint("   - hasData: ${snapshot.hasData}");
        debugPrint("   - connectionState: ${snapshot.connectionState}");
        debugPrint("   - hasError: ${snapshot.hasError}");
        if (snapshot.hasError) debugPrint("   - error: ${snapshot.error}");
        
        // Check data
        if (!snapshot.hasData) {
          debugPrint("⏳ No data yet, showing loading spinner");
          return const Center(child: MyCircularProgress());
        }
        
        final messageCount = snapshot.data!.length;
        final messageIds = snapshot.data!.map((m) {
          final text = m.text ?? '';
          final preview = text.length > 10 ? text.substring(0, 10) : text;
          return '${m.id}:$preview';
        }).join(', ');
        debugPrint("📋 Received $messageCount messages from stream");
        debugPrint("   - Message IDs: $messageIds");

        // Para chat estilo WhatsApp que inicia nas mensagens mais recentes:
        // - Mensagens vêm do Firestore em ordem ascending (msg1, msg2, msg3, msg4, msg5)
        // - .reversed.toList() inverte para (msg5, msg4, msg3, msg2, msg1)
        // - reverse: true no ListView faz a lista crescer de baixo para cima
        // - Resultado: mensagens mais recentes aparecem na parte inferior e o chat inicia lá
        final messages = snapshot.data!.reversed.toList();
        final processedMessages = _processMessages(messages, i18n);

        return ListView.builder(
          controller: widget.messagesController,
          // Usando BouncingScrollPhysics com configuração personalizada para efeito mais suave
          physics: const BouncingScrollPhysics(decelerationRate: ScrollDecelerationRate.fast),
          reverse: true, // ListView invertido: cresce de baixo para cima (mensagens novas embaixo)
          itemCount: processedMessages.length,
          itemBuilder: (context, index) {
            final processedMsg = processedMessages[index];
            
            // Usar RepaintBoundary para isolar repinturas
            return RepaintBoundary(
              key: ValueKey(processedMsg.id), // Key apropriada para performance
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
              ),
            );
          },
        );
      },
    );
  }
}
