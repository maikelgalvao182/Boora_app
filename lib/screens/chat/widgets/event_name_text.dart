import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/features/conversations/utils/conversation_styles.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';

/// Nome do evento
class EventNameText extends StatelessWidget {
  const EventNameText({
    required this.user,
    required this.chatService,
    super.key,
  });

  final User user;
  final ChatService chatService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: chatService.getConversationSummary(user.userId),
      builder: (context, snap) {
        String eventName = 'Evento';
        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data()!;
          eventName = data['activityText'] ?? 'Evento';
        }
        return ConversationStyles.buildEventNameText(name: eventName);
      },
    );
  }
}
