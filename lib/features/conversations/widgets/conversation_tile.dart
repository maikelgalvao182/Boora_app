import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/features/conversations/services/conversation_data_processor.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/conversations/state/conversation_activity_bus.dart';
import 'package:partiu/features/conversations/utils/conversation_styles.dart';
import 'package:partiu/features/events/state/event_store.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/event_emoji_avatar.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

class ConversationTile extends StatelessWidget {

  const ConversationTile({
    required this.conversationId,
    required this.rawData,
    required this.isVipEffective,
    required this.isLast,
    required this.onTap,
    this.showAvatarLoadingOverlay = false,
    super.key,
  });
  final String conversationId;
  final Map<String, dynamic> rawData;
  final bool isVipEffective;
  final bool isLast;
  final VoidCallback onTap;
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
        return ValueListenableBuilder<Set<String>>(
          valueListenable: ConversationActivityBus.instance.touchedConversationIds,
          builder: (context, touchedIds, __) {
        // 🔥 UMA ÚNICA STREAM compartilhada por todo o tile
        // ✅ FIX: Usar conversationId (não otherUserId) para escutar o documento correto
        // - Chat 1-1: conversationId = otherUserId
        // - Chat evento: conversationId = "event_${eventId}"
        
        // DEBUG: Log para identificar o problema de chat de grupo
        final isEventChatFromRaw = rawData['is_event_chat'] == true || rawData['event_id'] != null;
        if (isEventChatFromRaw) {
          debugPrint('🔵 [ConversationTile] EVENT CHAT - conversationId=$conversationId, eventId=${rawData['event_id']}');
        }
        
        final data = rawData;
        const showUpdatingIndicator = false;

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

            int toIntSafe(dynamic value) {
              if (value == null) return 0;
              if (value is int) return value;
              if (value is num) return value.toInt();
              if (value is String) return int.tryParse(value) ?? 0;
              return 0;
            }

            bool toBoolSafe(dynamic value, {required bool defaultValue}) {
              if (value == null) return defaultValue;
              if (value is bool) return value;
              if (value is int) return value != 0;
              if (value is String) {
                final v = value.trim().toLowerCase();
                if (v.isEmpty) return defaultValue;
                if (['1', 'true', 'yes', 'y'].contains(v)) return true;
                if (['0', 'false', 'no', 'n'].contains(v)) return false;
              }
              return defaultValue;
            }

            // Calcular estado derivado UMA VEZ
          final unreadCount = toIntSafe(data['unread_count'] ?? data['unreadCount']);

            // message_read pode vir como bool/int/string e em chaves diferentes.
            // Fallback: se unreadCount>0, consideramos como não lido.
      final messageRead = toBoolSafe(
        data['message_read'] ??
          data[MESSAGE_READ] ??
          data['isRead'],
                defaultValue: unreadCount == 0,
              );
            final hasUnread = unreadCount > 0 || !messageRead;

            // ✅ Padronização com 1x1: se chegou push e o backend ainda não refletiu
            // (unread_count permanece 0), ainda assim mostramos feedback visual.
            final hasActivityTouch = touchedIds.contains(conversationId);
            final showAttention = hasUnread || hasActivityTouch;

            final isEventChat =
                data['is_event_chat'] == true ||
                data['event_id'] != null ||
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
              ? (cleanName(data['activityText']).isNotEmpty
                ? cleanName(data['activityText'])
                : (cleanName(rawData['activityText']).isNotEmpty
                  ? cleanName(rawData['activityText'])
                  : cleanName(displayData.fullName)))
              : (otherNameFromSnap.isNotEmpty
                ? otherNameFromSnap
                : (otherNameFromRaw.isNotEmpty
                    ? otherNameFromRaw
                    : (isPlaceholderName(displayData.fullName) ? '' : cleanName(displayData.fullName))));

            final emoji = data['emoji']?.toString() ??
                         rawData['emoji']?.toString() ??
                         EventEmojiAvatar.defaultEmoji;

            final eventId = data['event_id']?.toString() ??
                           rawData['event_id']?.toString() ??
                           '';

            final dynamic timestampValue = data['last_message_timestamp'] ??
              data['last_message_at'] ??
              data['lastMessageAt'] ??
              data[TIMESTAMP] ??
              data['timestamp'] ??
              rawData[TIMESTAMP];

            final String? messageType = data[MESSAGE_TYPE]?.toString();

            String lastMessageText;
            if (messageType == 'image') {
              lastMessageText = i18n.translate('you_received_an_image');
            } else {
              final rawMessage = (data['last_message'] ??
                  data['lastMessage'] ??
                  data[LAST_MESSAGE] ??
                  rawData['last_message'] ??
                  rawData['lastMessage'] ??
                  rawData[LAST_MESSAGE] ??
                  '').toString();

              if (rawMessage == 'welcome_bride_short' || rawMessage == 'welcome_vendor_short') {
                final senderName = data['sender_name']?.toString() ??
                                  data['senderName']?.toString() ??
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
                    hasUnread: showAttention,
                    showUpdatingIndicator: showUpdatingIndicator,
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
              hasUnread: showAttention,
              showUpdatingIndicator: showUpdatingIndicator,
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
  required bool showUpdatingIndicator,
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
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
      visualDensity: VisualDensity.standard,
      dense: false,
      tileColor: hasUnread 
          ? GlimpseColors.primaryLight
          : null,
      leading: leading,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            // ✅ 1:1: sempre resolver via UserStore (evita alternar com sender)
            child: (!isEventChat && displayData.otherUserId.isNotEmpty)
                ? ReactiveUserNameWithBadge(
                    userId: displayData.otherUserId,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: ConversationStyles.eventNameFontSize,
                      fontWeight: ConversationStyles.eventNameFontWeight,
                      color: GlimpseColors.primaryColorLight,
                    ),
                    iconSize: ConversationStyles.verifiedIconSize,
                    spacing: ConversationStyles.verifiedIconSpacing,
                  )
                : ConversationStyles.buildEventNameText(
                    name: isPlaceholderName(displayName) ? '' : truncateName(displayName),
                  ),
          ),
          SizedBox(width: 8.w),
          if (timeAgo.isNotEmpty)
            Text(
              timeAgo,
              style: ConversationStyles.timeLabel(),
            ),
        ],
      ),
      subtitle: Padding(
        padding: EdgeInsets.only(top: 2.h),
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
      trailing: showUpdatingIndicator
          ? SizedBox(
              width: 18.w,
              height: 18.h,
              child: CupertinoActivityIndicator(radius: 8.r),
            )
          : null,
      onTap: () {
        HapticFeedback.lightImpact();
  ConversationActivityBus.instance.clear(conversationId);
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
                  left: 16.w,
                  top: 8.h,
                  child: IgnorePointer(
                    child: Container(
                      width: ConversationStyles.avatarSize,
                      height: ConversationStyles.avatarSize,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x59000000),
                      ),
                      alignment: Alignment.center,
                      child: CupertinoActivityIndicator(
                        radius: 10.r,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              // Badge posicionado absolutamente sobre o avatar
              if (hasUnread)
                Positioned(
                  left: 16.w + ConversationStyles.avatarSize - 16.w,
                  top: 8.h,
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
      width: 12.w,
      height: 12.h,
      decoration: BoxDecoration(
        color: GlimpseColors.actionColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 2.w,
        ),
      ),
    );
  }
}
