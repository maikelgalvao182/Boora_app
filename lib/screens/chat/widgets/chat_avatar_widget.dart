import 'package:flutter/material.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/features/conversations/utils/conversation_styles.dart';
import 'package:partiu/screens/chat/controllers/chat_app_bar_controller.dart';
import 'package:partiu/shared/widgets/event_emoji_avatar.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/features/events/state/event_store.dart';

/// Avatar do chat - evento ou usuário
class ChatAvatarWidget extends StatelessWidget {
  const ChatAvatarWidget({
    required this.user,
    required this.controller,
    this.conversationData,
    super.key,
  });

  final User user;
  final ChatAppBarController controller;
  final Map<String, dynamic>? conversationData;

  @override
  Widget build(BuildContext context) {
    if (controller.isEvent) {
      return ValueListenableBuilder<EventInfo?>(
        valueListenable: EventStore.instance.getEventNotifier(controller.eventId),
        builder: (context, eventInfo, _) {
          String emoji = eventInfo?.emoji ?? EventEmojiAvatar.defaultEmoji;
          String eventId = controller.eventId;

          // Fallback para dados da conversa se store estiver vazio
          if (eventInfo == null && conversationData != null) {
            final data = conversationData!;
            emoji = data['emoji'] ?? emoji;
            eventId = data['event_id']?.toString() ?? eventId;
          }

          return EventEmojiAvatar(
            emoji: emoji,
            eventId: eventId,
            size: ConversationStyles.avatarSizeChatAppBar,
            emojiSize: ConversationStyles.eventEmojiFontSizeChatAppBar,
          );
        },
      );
    }

    return StableAvatar(
      key: ValueKey(user.userId),
      userId: user.userId,
      size: ConversationStyles.avatarSizeChatAppBar,
      enableNavigation: false,
    );
  }
}
