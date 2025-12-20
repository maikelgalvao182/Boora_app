import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:partiu/models/user_model.dart' as core_user_model;
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/toast_messages.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/repositories/chat_repository.dart';
import 'package:partiu/dialogs/common_dialogs.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/screens/chat/models/message.dart';
import 'package:partiu/screens/chat/models/reply_snapshot.dart';
import 'package:partiu/screens/chat/models/user_model.dart' as chat_user_model;
import 'package:partiu/screens/chat/viewmodels/chat_view_model.dart';
import 'package:partiu/core/services/image_compress_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:flutter/material.dart';

class ChatService {
  factory ChatService() => _instance;
  ChatService._internal();
  // B1.1: Singleton pattern para evitar múltiplas instâncias
  static final ChatService _instance = ChatService._internal();

  final ChatViewModel _viewModel = ChatViewModel(chatRepository: ChatRepository());
  // LEGACY REMOVED: StreamCacheService replaced by ConversationCacheService
  // final StreamCacheService _streamCache = StreamCacheService();
  // B2: Image compression service para otimizar upload de imagens
  final ImageCompressService _imageCompressor = const ImageCompressService();

  /// Get cached messages stream with A2 optimizations
  Stream<List<Message>> getMessages(String userId) {
    if (userId.isEmpty) return const Stream.empty();
    // Retorna stream de mensagens já parseadas vindas do WebSocket através do ViewModel
    return _viewModel.getMessages(userId);
  }

  /// Stream do resumo da conversa pelo ID do documento
  /// Para chat 1-1: usar otherUserId
  /// Para chat de evento: usar "event_${eventId}"
  Stream<DocumentSnapshot<Map<String, dynamic>>> getConversationSummaryById(String conversationId) {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty || conversationId.isEmpty) {
      return const Stream.empty();
    }
    return FirebaseFirestore.instance
      .collection(C_CONNECTIONS)
      .doc(currentUserId)
      .collection(C_CONVERSATIONS)
      .doc(conversationId)
      .snapshots();
  }

  /// Stream do resumo da conversa (LEGACY - usar getConversationSummaryById)
  /// Mantido para compatibilidade com código existente
  Stream<DocumentSnapshot<Map<String, dynamic>>> getConversationSummary(String otherUserId) {
    return getConversationSummaryById(otherUserId);
  }

  /// Get cached user updates stream with A2 optimizations  
  Stream<chat_user_model.UserModel> getUserUpdates(String userId) {
    if (userId.isEmpty) return const Stream.empty();
    // LEGACY REMOVED: Using direct Firestore instead of StreamCacheService
    // return _streamCache.getUserPresenceStream(userId);
    
    // Direct Firestore stream as fallback
    return FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .snapshots()
        .map((doc) => chat_user_model.UserModel.fromMap(doc.data() ?? {}, doc.id));
  }

  /// Get conversation updates stream
  Stream<DocumentSnapshot<Map<String, dynamic>>> getConversationUpdates(String userId) {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty || userId.isEmpty) {
      return const Stream.empty();
    }
    // Subscribe to the conversation summary under Connections/{currentUserId}/Conversations/{otherUserId}
    return FirebaseFirestore.instance
      .collection(C_CONNECTIONS)
      .doc(currentUserId)
      .collection(C_CONVERSATIONS)
      .doc(userId)
      .snapshots();
  }

  /// Alias for getConversationUpdates (compatibility)
  Stream<DocumentSnapshot<Map<String, dynamic>>> getConversationStream(String userId) {
  return getConversationUpdates(userId);
  }  /// Block a remote user profile
  Future<void> blockProfile({
    required BuildContext context,
    required String blockedUserId,
    required AppLocalizations i18n,
    required ProgressDialog progressDialog,
  }) async {
    confirmDialog(
      context,
      positiveText: i18n.translate('BLOCK'),
      message: i18n.translate('this_profile_will_be_blocked_and_you_cant_receive_messages'),
      negativeAction: () => Navigator.of(context).pop(),
      positiveAction: () async {
        // Hide confirm dialog
        Navigator.of(context).pop();

        // Show processing dialog
        progressDialog.show(i18n.translate('processing'));

        // Block profile
        await _viewModel.blockUser(blockedUserId: blockedUserId);

        // Hide progress dialog
        progressDialog.hide();

        // Show success toast
        ToastService.showSuccess(
        message: i18n.translate('user_has_been_blocked',
      ),
        );
      },
    );
  }

  /// Unblock a remote user profile
  Future<void> unblockProfile({
    required BuildContext context,
    required String blockedUserId,
    required AppLocalizations i18n,
    required ProgressDialog progressDialog,
  }) async {
    confirmDialog(
      context,
      positiveText: i18n.translate('UNBLOCK'),
      message: i18n.translate('this_profile_will_be_removed_from_the_blocked_users_list'),
      negativeAction: () => Navigator.of(context).pop(),
      positiveAction: () async {
        // Hide confirm dialog
        Navigator.of(context).pop();

        // Show processing dialog
        progressDialog.show(i18n.translate('processing'));

        // Unblock profile
        await _viewModel.unblockUser(blockedUserId: blockedUserId);

        // Hide progress dialog
        progressDialog.hide();

        // Show success toast
        ToastService.showSuccess(
        message: i18n.translate('user_has_been_unblocked',
      ),
        );
      },
    );
  }

  /// Delete chat conversation directly without confirmation dialog
  Future<void> deleteChat(String userId) async {
    await _viewModel.deleteChat(userId);
  }

  /// Confirm and delete chat conversation
  Future<void> confirmDeleteChat({
    required BuildContext context,
    required String userId,
    required AppLocalizations i18n,
    required ProgressDialog progressDialog,
  }) async {
    errorDialog(
      context,
      title: i18n.translate('delete_conversation'),
      message: i18n.translate('are_you_sure_you_want_to_delete_conversation'),
      positiveText: i18n.translate('DELETE'),
      negativeAction: () => Navigator.of(context).pop(),
      positiveAction: () async {
        // Close the confirm dialog
        Navigator.of(context).pop();

        // Show processing dialog
        progressDialog.show(i18n.translate('processing'));

        /// Delete chat
        await _viewModel.deleteChat(userId);

        // Hide progress
        await progressDialog.hide();
        
        // Close chat screen first (para garantir que estamos no contexto correto)
        if (context.mounted) {
          Navigator.of(context).pop();
          
          // Buscar traduções
          final title = i18n.translate('delete_conversation');
          final subtitle = i18n.translate('conversation_deleted_successfully');
          
          // Show success toast após fechar a tela
          ToastService.showSuccess(
            message: subtitle.isNotEmpty ? subtitle : 'A conversa foi excluída com sucesso',
          );
        }
      },
    );
  }

  /// Send text message
  Future<void> sendTextMessage({
    required BuildContext context,
    required String text,
    required User receiver,
    required AppLocalizations i18n,
    required Function(bool) setIsSending,
    ReplySnapshot? replySnapshot, // 🆕 Dados de reply
  }) async {
    if (text.trim().isEmpty) return;

    setIsSending(true);

    try {
      await _viewModel.sendTextMessage(
        text: text,
        receiver: receiver,
        replySnapshot: replySnapshot, // 🆕 Passar para ViewModel
        onError: (error) {
          ToastService.showError(
            message: error,
          );
        },
      );
    } catch (e) {
      ToastService.showError(
        message: i18n.translate('an_error_has_occurred',
      ),
      );
    } finally {
      setIsSending(false);
    }
  }

  /// Send image message
  Future<void> sendImageMessage({
    required BuildContext context,
    required File imageFile,
    required User receiver,
    required AppLocalizations i18n,
    required ProgressDialog progressDialog,
    required Function(bool) setIsSending,
    ReplySnapshot? replySnapshot, // 🆕 Dados de reply
  }) async {
    setIsSending(true);
    // Show processing dialog
    progressDialog.show(i18n.translate('sending'));

    File? compressedFile;
    try {
      // B2: Compress image before upload to reduce bandwidth and storage
      compressedFile = await _imageCompressor.compressFileToTempFile(
        imageFile,
      );
      
      // Send image message with compressed file
      await _viewModel.sendImageMessage(
        imageFile: compressedFile,
        receiver: receiver,
        replySnapshot: replySnapshot, // 🆕 Passar para ViewModel
        onError: (error) {
          ToastService.showError(
            message: error,
          );
        },
      );
    } catch (e) {
      ToastService.showError(
        message: i18n.translate('an_error_has_occurred',
      ),
      );
    } finally {
      // Cleanup: Remove compressed temp file if different from original
      if (compressedFile != null && 
          compressedFile.path != imageFile.path &&
          await compressedFile.exists()) {
        try {
          await compressedFile.delete();
        } catch (e) {
          // Ignore temp file deletion errors
        }
      }
      // Hide progress dialog
      progressDialog.hide();
      setIsSending(false);
    }
  }

  /// Check blocked user status
  void checkBlockedUserStatus({
    required String remoteUserId,
    required String localUserId,
  }) {
    _viewModel.checkBlockedUserStatus(
      remoteUserId: remoteUserId,
      localUserId: localUserId,
    );
  }

  /// Set remote user
  void setRemoteUser(User user) {
    _viewModel.setRemoteUser(user);
  }

  /// Check if remote user is blocked
  bool get isRemoteUserBlocked => _viewModel.isRemoteUserBlocked;
}
