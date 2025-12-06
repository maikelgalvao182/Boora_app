import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:partiu/screens/chat/chat_screen_refactored.dart';
import 'package:partiu/core/models/user.dart';

/// Ultra-simplified conversation navigation service
class ConversationNavigationService {
  const ConversationNavigationService();

  /// Handle conversation tap - navigate to chat
  Future<void> handleConversationTap({
    required BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
    required Map<String, dynamic> data,
  }) async {
    try {
      // 1. Verificar se é chat de evento
      final isEventChat = data['is_event_chat'] == true;
      final eventId = data['event_id'] as String?;
      
      // Get user ID from data
      final otherUserId = (data['user_id'] ?? doc?.id ?? '').toString();
      if (otherUserId.isEmpty) return;

      // Create user object
      final user = _createUserFromConversationData(data, otherUserId);

      Navigator.push(
        context, 
        MaterialPageRoute(
          builder: (_) => ChatScreenRefactored(
            user: user,
            isEvent: isEventChat,
            eventId: eventId,
          )
        )
      );

      // Mark as read in background after navigation starts
      if (doc != null) {
        _markAsReadInBackground(doc);
      }
    } catch (e) {
      // Ignore navigation errors
      debugPrint('Error navigating to chat: $e');
    }
  }

  /// Create user object from conversation data to avoid async fetch
  User _createUserFromConversationData(Map<String, dynamic> data, String userId) {
    // 🔍 DEBUG: Log dos dados recebidos
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🔍 _createUserFromConversationData:');
    debugPrint('   - userId: "$userId"');
    debugPrint('   - is_event_chat: ${data['is_event_chat']}');
    debugPrint('   - event_id: ${data['event_id']}');
    debugPrint('   - fullname: ${data['fullname']}');
    debugPrint('   - user_profile_photo: ${data['user_profile_photo']}');
    debugPrint('   - data keys: ${data.keys.toList()}');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    // Para chats de eventos, os dados já vêm corretos do backend
    // Backend salva como: fullname (activityText) e user_profile_photo (emoji)
    final userName = data['fullname'] ?? 'Unknown User';
    final userPhoto = data['user_profile_photo'] ?? '';
    
    debugPrint('✅ User criado: userName="$userName", userPhoto="$userPhoto"');
    
    // ✅ CORRIGIDO: Usar campos corretos do SessionManager/User model
    // Seguindo o padrão de: sessionManager._userToMap() e User.fromDocument()
    return User.fromDocument({
      'userId': userId,              // ✅ userId (não user_id)
      'fullName': userName,          // ✅ fullName (não fullname)
      'profilePhotoUrl': userPhoto,  // ✅ profilePhotoUrl (não user_profile_photo)
      'gender': '',
      'birthDay': 1,
      'birthMonth': 1,
      'birthYear': 2000,
      'jobTitle': '',
      'bio': '',
      'country': '',
      'locality': '',
      'latitude': 0.0,
      'longitude': 0.0,
      'status': 'active',
      'level': '',
      'isVerified': false,
      'registrationDate': DateTime.now().toIso8601String(),
      'lastLoginDate': DateTime.now().toIso8601String(),
      'totalLikes': 0,
      'totalVisits': 0,
      'isOnline': false,
    });
  }

  /// Background task to mark message as read (non-blocking)
  void _markAsReadInBackground(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    // Use microtask to execute after current frame
    Future.microtask(() {
      doc.reference.update({
        'message_read': true,
        'unread_count': 0,
      }).catchError((e) {
        // Silent fail - not critical for navigation
      });
    });
  }
}