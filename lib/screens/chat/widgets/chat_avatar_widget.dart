import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/features/conversations/utils/conversation_styles.dart';
import 'package:partiu/screens/chat/controllers/chat_app_bar_controller.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/shared/widgets/event_emoji_avatar.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

/// Avatar do chat - evento ou usuário
class ChatAvatarWidget extends StatelessWidget {
  const ChatAvatarWidget({
    required this.user,
    required this.chatService,
    required this.controller,
    super.key,
  });

  final User user;
  final ChatService chatService;
  final ChatAppBarController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isEvent) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: chatService.getConversationSummary(user.userId),
        builder: (context, snap) {
          String emoji = EventEmojiAvatar.defaultEmoji;
          String eventId = controller.eventId;
          
          if (snap.hasData && snap.data!.data() != null) {
            final data = snap.data!.data()!;
            emoji = data['emoji'] ?? EventEmojiAvatar.defaultEmoji;
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
      size: 40,
      enableNavigation: false,
    );
  }
}
