import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/push_types.dart';

class PushPreferencesService {
  static Future<void> setEnabled(
    PushType type,
    bool enabled,
  ) async {
    final userId = AppState.currentUserId;
    if (userId == null || userId.isEmpty) return;

    await FirebaseFirestore.instance
        .collection("Users")
        .doc(userId)
        .update({
      "advancedSettings.push_preferences.${key(type)}": enabled,
    });
  }

  static bool isEnabled(
    PushType type,
    Map<String, dynamic>? prefs,
  ) {
    return prefs?[key(type)] ?? true; // default ON
  }

  static String key(PushType type) {
    switch (type) {
      case PushType.global:
        return "global";
      case PushType.chatEvent:
        return "chat_event";
    }
  }
}
