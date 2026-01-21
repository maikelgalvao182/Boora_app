import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/features/conversations/services/conversation_data_processor.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/conversations/utils/conversation_styles.dart';
import 'package:partiu/features/events/state/event_store.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/event_emoji_avatar.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
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
    this.showAvatarLoadingOverlay = false,
    super.key,
  });
  final String conversationId;
  final Map<String, dynamic> rawData;
  final bool isVipEffective;
  final bool isLast;
  final VoidCallback onTap;
  final ChatService chatService;
  final bool showAvatarLoadingOverlay;

  @override
  Widget build(BuildContext context) {
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
        // 🔥 UMA ÚNICA STREAM compartilhada por todo o tile
        // ✅ FIX: Usar conversationId (não otherUserId) para escutar o documento correto
        // - Chat 1-1: conversationId = otherUserId
        // - Chat evento: conversationId = "event_${eventId}"
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: chatService.getConversationSummaryById(conversationId),
          builder: (context, snap) {
            // Extrair dados frescos do snapshot
            final data = snap.data?.data();

            bool isPlaceholderName(String value) {
              final normalized = value.trim().toLowerCase();
              return normalized.isEmpty ||
                  normalized == 'unknown user' ||
                  normalized == 'unknow user' ||
                  normalized == 'usuário' ||
                  normalized == 'usuario';
            }

            String cleanName(dynamic value) {
              if (value == null) return '';
              final text = value.toString().trim();
              if (isPlaceholderName(text)) return '';
              return text;
            }

            // Calcular estado derivado UMA VEZ
            final unreadCount = data?['unread_count'] as int? ?? 0;
            final messageRead = data?['message_read'] as bool? ?? true;
            final hasUnread = unreadCount > 0 || !messageRead;

            final isEventChat =
                data?['is_event_chat'] == true ||
                data?['event_id'] != null ||
                rawData['is_event_chat'] == true ||
                rawData['event_id'] != null;

            String extractOtherUserName(Map<String, dynamic>? src) {
              if (src == null) return '';
              final candidates = <dynamic>[
                src['other_user_name'],
                src['otherUserName'],
                src['userFullname'],
                src['user_fullname'],
              ];
              for (final c in candidates) {
                final cleaned = cleanName(c);
                if (cleaned.isNotEmpty) return cleaned;
              }
              return '';
            }

            // ⚠️ 1:1: NÃO usar fullname/activityText do summary (pode refletir sender da última msg).
            // Use UserStore no build do title e deixe aqui apenas um fallback seguro.
            final otherNameFromSnap = extractOtherUserName(data);
            final otherNameFromRaw = extractOtherUserName(rawData);

            final displayName = isEventChat
              ? (cleanName(data?['activityText']).isNotEmpty
                ? cleanName(data?['activityText'])
                : (cleanName(rawData['activityText']).isNotEmpty
                  ? cleanName(rawData['activityText'])
                  : cleanName(displayData.fullName)))
              : (otherNameFromSnap.isNotEmpty
                ? otherNameFromSnap
                : (otherNameFromRaw.isNotEmpty
                    ? otherNameFromRaw
                    : (isPlaceholderName(displayData.fullName) ? '' : cleanName(displayData.fullName))));

            final emoji = data?['emoji']?.toString() ?? 
                         rawData['emoji']?.toString() ?? 
                         EventEmojiAvatar.defaultEmoji;

            final eventId = data?['event_id']?.toString() ?? 
                           rawData['event_id']?.toString() ?? 
                           '';

            final timestampValue = data?['last_message_timestamp'] ??
                                  data?['last_message_at'] ??
                                  data?['lastMessageAt'] ??
                                  data?[TIMESTAMP] ??
                                  data?['timestamp'];

            final messageType = data?[MESSAGE_TYPE]?.toString();

            String lastMessageText;
            if (messageType == 'image') {
              lastMessageText = i18n.translate('you_received_an_image');
            } else {
              final rawMessage = (data?['last_message'] ??
                                 data?['lastMessage'] ??
                                 data?[LAST_MESSAGE] ??
                                 '').toString();

              if (rawMessage == 'welcome_bride_short' || rawMessage == 'welcome_vendor_short') {
                final senderName = data?['sender_name']?.toString() ??
                                  data?['senderName']?.toString() ??
                                  displayName;
                final translatedMessage = i18n.translate(rawMessage);
                lastMessageText = translatedMessage.replaceAll('{name}', senderName);
              } else {
                lastMessageText = rawMessage.isEmpty ? displayData.lastMessage : rawMessage;
              }
            }

            // Truncar mensagem se necessário
            if (lastMessageText.length > 40) {
              lastMessageText = '${lastMessageText.substring(0, 30)}...';
            }

            // Formatar timestamp
            final timeAgoText = TimeAgoHelper.format(
              context,
              timestamp: timestampValue,
            );

            if (eventId.isNotEmpty) {
              return ValueListenableBuilder<EventInfo?>(
                valueListenable: EventStore.instance.getEventNotifier(eventId),
                builder: (context, eventInfo, _) {
                  // Se tiver dados no store, usa eles (são mais recentes/reativos)
                  // Se não, usa os dados do snapshot/rawData
                  final effectiveDisplayName = eventInfo?.name ?? displayName;
                  final effectiveEmoji = eventInfo?.emoji ?? emoji;

                  // Se o store estiver vazio mas temos dados, podemos inicializar?
                  // Melhor não fazer side-effects no build.
                  // O GroupInfoController ou quem carrega o evento deve popular o store.

                  return _buildTileContent(
                    context,
                    displayData,
                    i18n,
                    hasUnread: hasUnread,
                    displayName: effectiveDisplayName,
                    lastMessage: lastMessageText,
                    timeAgo: timeAgoText,
                    emoji: effectiveEmoji,
                    eventId: eventId,
                  );
                },
              );
            }

            return _buildTileContent(
              context,
              displayData,
              i18n,
              hasUnread: hasUnread,
              displayName: displayName,
              lastMessage: lastMessageText,
              timeAgo: timeAgoText,
              emoji: emoji,
              eventId: eventId,
            );
          },
        );
      },
    );
  }

  Widget _buildTileContent(
    BuildContext context,
    ConversationDisplayData displayData,
    AppLocalizations i18n, {
    required bool hasUnread,
    required String displayName,
    required String lastMessage,
    required String timeAgo,
    String? emoji,
    String? eventId,
  }) {
    // Verificar se é chat de evento
    final isEventChat = rawData['is_event_chat'] == true || rawData['event_id'] != null;

    String truncateName(String value) {
      final text = value.trim();
      const maxLen = 28;
      if (text.length <= maxLen) return text;

      // 28 caracteres no total, incluindo "..."
      const ellipsis = '...';
      final cut = (maxLen - ellipsis.length).clamp(0, text.length);
      return '${text.substring(0, cut).trimRight()}$ellipsis';
    }

    bool isPlaceholderName(String value) {
      final normalized = value.trim().toLowerCase();
      return normalized.isEmpty ||
          normalized == 'unknown user' ||
          normalized == 'unknow user' ||
          normalized == 'usuário' ||
          normalized == 'usuario';
    }

    // Leading: Avatar ou Emoji do evento (SEM badge - será adicionado externamente)
    final Widget leading;
    if (isEventChat) {
      leading = EventEmojiAvatar(
        emoji: emoji ?? EventEmojiAvatar.defaultEmoji,
        eventId: eventId ?? '',
        size: ConversationStyles.avatarSize,
        emojiSize: ConversationStyles.eventEmojiFontSize,
      );
    } else {
      leading = StableAvatar(
        key: ValueKey('conversation_avatar_${displayData.otherUserId}'),
        userId: displayData.otherUserId,
        size: ConversationStyles.avatarSize,
      );
    }

    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      visualDensity: VisualDensity.standard,
      dense: false,
      tileColor: hasUnread 
          ? GlimpseColors.lightTextField
          : null,
      leading: leading,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            // ✅ 1:1: sempre resolver via UserStore (evita alternar com sender)
            child: (!isEventChat && displayData.otherUserId.isNotEmpty)
                ? ValueListenableBuilder<String?>(
                    valueListenable:
                        UserStore.instance.getNameNotifier(displayData.otherUserId),
                    builder: (context, name, _) {
                      final resolved = (name ?? '').trim();
                      final effective = (!isPlaceholderName(resolved) && resolved.isNotEmpty)
                          ? resolved
                          : (isPlaceholderName(displayName) ? '' : displayName);

                      return ConversationStyles.buildEventNameText(
                        name: effective.isNotEmpty ? truncateName(effective) : '',
                      );
                    },
                  )
                : ConversationStyles.buildEventNameText(
                    name: isPlaceholderName(displayName) ? '' : truncateName(displayName),
                  ),
          ),
          const SizedBox(width: 8),
          if (timeAgo.isNotEmpty)
            Text(
              timeAgo,
              style: ConversationStyles.timeLabel(),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2.0),
        child: MarkdownBody(
          data: lastMessage,
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
            blockSpacing: ConversationStyles.markdownBlockSpacing,
            listIndent: ConversationStyles.markdownListIndent,
            pPadding: ConversationStyles.zeroPadding,
          ),
          extensionSet: md.ExtensionSet.gitHubFlavored,
        ),
      ),
      trailing: null,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );

    // 🔥 Stack externo para badge (evita clipping do ListTile.leading)
    return RepaintBoundary(
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              tile,
              if (showAvatarLoadingOverlay)
                Positioned(
                  left: 16,
                  top: 8,
                  child: IgnorePointer(
                    child: Container(
                      width: ConversationStyles.avatarSize,
                      height: ConversationStyles.avatarSize,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x59000000),
                      ),
                      alignment: Alignment.center,
                      child: const CupertinoActivityIndicator(
                        radius: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              // Badge posicionado absolutamente sobre o avatar
              if (hasUnread)
                Positioned(
                  left: 16 + ConversationStyles.avatarSize - 16,
                  top: 8,
                  child: _UnreadBadge(),
                ),
            ],
          ),
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

/// Badge de mensagem não lida (ponto vermelho)
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: GlimpseColors.actionColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 2,
        ),
      ),
    );
  }
}
