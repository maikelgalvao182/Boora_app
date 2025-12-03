import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/features/conversations/services/conversation_data_processor.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/conversations/utils/conversation_styles.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/event_emoji_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

class ConversationTile extends StatelessWidget {

  const ConversationTile({
    required this.conversationId,
    required this.rawData,
    required this.isVipEffective,
    required this.isLast,
    required this.onTap,
    required this.chatService,
    super.key,
  });
  final String conversationId;
  final Map<String, dynamic> rawData;
  final bool isVipEffective;
  final bool isLast;
  final VoidCallback onTap;
  final ChatService chatService;

  @override
  Widget build(BuildContext context) {
    // [OK] Debug: Log raw data from Firestore
    
    // Log all photo-related fields
    final photoFields = [
      'profileImageURL',
      'user_profile_photo',
      'photo_url',
      'user_photo_link',
      'user_photo',
      'profile_photo',
      'profile_photo_url',
      'avatar_url',
      'avatar',
      'photo',
      'image_url',
      'profile_image_url',
    ];
    
    for (final field in photoFields) {
      if (rawData.containsKey(field)) {
      }
    }
    
    final i18n = AppLocalizations.of(context);
    final viewModel = context.read<ConversationsViewModel>();

    final notifier = viewModel.getDisplayDataNotifier(
      conversationId: conversationId,
      data: rawData,
      isVipEffective: isVipEffective,
      i18n: i18n,
    );

    return ValueListenableBuilder<ConversationDisplayData>(
      valueListenable: notifier,
      builder: (context, displayData, _) {
        return _buildTileContent(context, displayData, i18n);
      },
    );
  }

  Widget _buildTileContent(BuildContext context, ConversationDisplayData displayData, AppLocalizations i18n) {
    // Verificar se é chat de evento
    final isEventChat = rawData['is_event_chat'] == true || rawData['event_id'] != null;
    
    // Leading: Avatar ou Emoji do evento
    final Widget leading;
    if (isEventChat) {
      // Buscar emoji da coleção Connections
      leading = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: chatService.getConversationSummary(displayData.otherUserId),
        builder: (context, snap) {
          String emoji = EventEmojiAvatar.defaultEmoji;
          String eventId = rawData['event_id']?.toString() ?? '';
          
          if (snap.hasData && snap.data!.data() != null) {
            final data = snap.data!.data()!;
            emoji = data['emoji'] ?? EventEmojiAvatar.defaultEmoji;
            eventId = data['event_id']?.toString() ?? eventId;
          }
          
          return EventEmojiAvatar(
            emoji: emoji,
            eventId: eventId,
            size: ConversationStyles.avatarSize,
            emojiSize: ConversationStyles.eventEmojiFontSize,
          );
        },
      );
    } else {
      // Avatar normal para conversas 1-1
      leading = SizedBox(
        width: ConversationStyles.avatarSize,
        height: ConversationStyles.avatarSize,
        child: StableAvatar(
          key: ValueKey('conversation_avatar_${displayData.otherUserId}'),
          userId: displayData.otherUserId,
          size: ConversationStyles.avatarSize,
        ),
      );
    }

    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      visualDensity: VisualDensity.standard,
      dense: false,
      tileColor: displayData.hasUnreadMessage 
          ? GlimpseColors.lightTextField
          : null,
      leading: leading,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: chatService.getConversationSummary(displayData.otherUserId),
              builder: (context, snap) {
                String displayName = 'Usuário';
                if (snap.hasData && snap.data!.data() != null) {
                  final data = snap.data!.data()!;
                  displayName = data['activityText'] ?? data['user_fullname'] ?? 'Usuário';
                }
                return ConversationStyles.buildEventNameText(
                  name: displayName,
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // 🔥 Time-ago reativo usando StreamBuilder (igual ao chat_app_bar_widget.dart)
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: chatService.getConversationSummary(displayData.otherUserId),
            builder: (context, snap) {
              var timeAgoText = '';
              if (snap.hasData && snap.data!.data() != null) {
                final data = snap.data!.data()!;
                // Use same timestamp selection as chat_app_bar_widget.dart
                final timestampValue = data['last_message_timestamp']
                    ?? data['last_message_at']
                    ?? data['lastMessageAt']
                    ?? data[TIMESTAMP]
                    ?? data['timestamp'];
                
                // Formata usando TimeAgoHelper centralizado
                timeAgoText = TimeAgoHelper.format(
                  timestamp: timestampValue,
                  locale: i18n.translate('lang'),
                );
              }
              
              if (timeAgoText.isEmpty) return const SizedBox.shrink();
              
              return Text(
                timeAgoText,
                style: ConversationStyles.timeLabel(),
              );
            },
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              // 🔥 Preview reativo usando StreamBuilder (igual ao time-ago)
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: chatService.getConversationSummary(displayData.otherUserId),
                builder: (context, snap) {
                  String lastMessageText = '';
                  String? messageType;
                  
                  if (snap.hasData && snap.data!.data() != null) {
                    final data = snap.data!.data()!;
                    // Busca tipo da mensagem
                    messageType = data[MESSAGE_TYPE]?.toString();
                    
                    // Se for imagem, mostra texto internacionalizado
                    if (messageType == 'image') {
                      lastMessageText = i18n.translate('you_received_an_image');
                    } else {
                      // Busca última mensagem com múltiplos fallbacks
                      final rawMessage = (data['last_message']
                          ?? data['lastMessage']
                          ?? data[LAST_MESSAGE]
                          ?? '').toString();
                      
                      // Verifica se é uma mensagem de welcome automática
                      if (rawMessage == 'welcome_bride_short' || rawMessage == 'welcome_vendor_short') {
                        // Busca o nome do remetente para usar na tradução
                        final senderName = data['sender_name']?.toString() ?? 
                                         data['senderName']?.toString() ?? 
                                         displayData.displayName;
                        // Traduz e substitui o placeholder {name}
                        final translatedMessage = i18n.translate(rawMessage);
                        lastMessageText = translatedMessage.replaceAll('{name}', senderName);
                      } else {
                        lastMessageText = rawMessage;
                      }
                    }
                  }
                  
                  // Se não há dados do stream, usa fallback do displayData
                  if (lastMessageText.isEmpty) {
                    lastMessageText = displayData.lastMessage;
                  }
                  
                  // Trunca a mensagem se exceder 30 caracteres
                  if (lastMessageText.length > 40) {
                    lastMessageText = '${lastMessageText.substring(0, 30)}...';
                  }
                  
                  return MarkdownBody(
                    data: lastMessageText,
                    styleSheet: MarkdownStyleSheet(
                      p: ConversationStyles.subtitle().copyWith(
                        height: ConversationStyles.markdownLineHeight,
                      ),
                      strong: ConversationStyles.subtitle().copyWith(
                        fontWeight: ConversationStyles.markdownBoldWeight,
                        height: ConversationStyles.markdownLineHeight,
                      ),
                      em: ConversationStyles.subtitle().copyWith(
                        fontStyle: FontStyle.italic,
                        height: ConversationStyles.markdownLineHeight,
                      ),
                      // Remove espaçamento extra de parágrafos
                      blockSpacing: ConversationStyles.markdownBlockSpacing,
                      listIndent: ConversationStyles.markdownListIndent,
                      pPadding: ConversationStyles.zeroPadding,
                    ),
                    extensionSet: md.ExtensionSet.gitHubFlavored,
                  );
                },
              ),
            ),
            if (displayData.hasUnreadMessage) ...[
              const SizedBox(width: 8),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: GlimpseColors.actionColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: null,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );

    return RepaintBoundary(
      child: Column(
        children: [
          tile,
          if (!isLast)
            Divider(
              height: ConversationStyles.dividerHeight,
              color: ConversationStyles.dividerColor(),
            ),
        ],
      ),
    );
  }
}
