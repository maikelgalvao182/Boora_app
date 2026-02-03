import 'package:flutter/material.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/features/conversations/utils/conversation_styles.dart';
import 'package:partiu/features/events/state/event_store.dart';
import 'package:partiu/screens/chat/controllers/chat_app_bar_controller.dart';

/// Nome do evento
class EventNameText extends StatelessWidget {
  const EventNameText({
    required this.user,
    this.conversationData,
    this.controller,
    super.key,
  });

  final User user;
  final Map<String, dynamic>? conversationData;
  final ChatAppBarController? controller;

  @override
  Widget build(BuildContext context) {
    if (controller != null && controller!.isEvent) {
      return ValueListenableBuilder<EventInfo?>(
        valueListenable: EventStore.instance.getEventNotifier(controller!.eventId),
        builder: (context, eventInfo, _) {
          String eventName = eventInfo?.name ?? 'Evento';

          if (eventInfo == null && conversationData != null) {
            eventName = conversationData?['activityText'] ?? eventName;
          }

          return ConversationStyles.buildEventNameText(
            name: eventName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        },
      );
    }

    final eventName = conversationData?['activityText'] ?? 'Evento';
    return ConversationStyles.buildEventNameText(
      name: eventName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
