import 'package:flutter/foundation.dart';

/// Global bus to provide immediate UI feedback when a push arrives,
/// even before Firestore updates unread_count/last_message.
///
/// Why: event chat (group) pushes are data-only and the summary doc can lag or
/// keep unread_count=0 (e.g. system messages), which makes the tile look like
/// nothing happened.
class ConversationActivityBus {
  ConversationActivityBus._();
  static final ConversationActivityBus instance = ConversationActivityBus._();

  /// conversationIds that were just "touched" by an incoming message.
  ///
  /// The UI can show a highlight/badge for a short time or until seen.
  final ValueNotifier<Set<String>> touchedConversationIds =
      ValueNotifier<Set<String>>(<String>{});

  void touch(String conversationId) {
    if (conversationId.isEmpty) return;
    final current = Set<String>.from(touchedConversationIds.value);
    if (current.add(conversationId)) {
      touchedConversationIds.value = current;
    }
  }

  void clear(String conversationId) {
    if (conversationId.isEmpty) return;
    final current = Set<String>.from(touchedConversationIds.value);
    if (current.remove(conversationId)) {
      touchedConversationIds.value = current;
    }
  }
}
