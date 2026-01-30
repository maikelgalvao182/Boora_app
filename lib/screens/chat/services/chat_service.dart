import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:partiu/models/user_model.dart' as core_user_model;
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
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
  /// 
  /// ⚠️ DEPRECATED: Usar getConversationOnce() para reduzir custos
  /// Stream mantido apenas para casos que realmente precisam de realtime
  @Deprecated('Use getConversationOnce() instead to reduce Firestore reads')
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

  /// ✅ OTIMIZADO: Busca metadata da conversa com get() único
  /// Usar em vez de stream quando não precisa de realtime
  Future<Map<String, dynamic>?> getConversationOnce(String conversationId) async {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty || conversationId.isEmpty) {
      return null;
    }
    try {
      final doc = await FirebaseFirestore.instance
        .collection(C_CONNECTIONS)
        .doc(currentUserId)
        .collection(C_CONVERSATIONS)
        .doc(conversationId)
        .get();
      return doc.data();
    } catch (e) {
      debugPrint('❌ [ChatService] getConversationOnce error: $e');
      return null;
    }
  }

  /// Stream do resumo da conversa (LEGACY - usar getConversationSummaryById)
  /// Mantido para compatibilidade com código existente
  Stream<DocumentSnapshot<Map<String, dynamic>>> getConversationSummary(String otherUserId) {
    return getConversationSummaryById(otherUserId);
  }

  /// ⚠️ DEPRECATED: Stream de presença é caro - usar getUserOnce() com polling
  @Deprecated('Use getUserOnce() instead to reduce Firestore reads')
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

  // ✅ Cache em memória para presença (evita reads repetidos)
  static final Map<String, _CachedPresence> _presenceCache = {};
  static const Duration _presenceTtl = Duration(seconds: 60); // TTL de 60s

  /// ✅ OTIMIZADO: Busca presença do usuário com cache em memória
  /// TTL de 60 segundos - ideal para tela de chat aberta
  Future<chat_user_model.UserModel?> getUserOnce(String userId, {bool forceRefresh = false}) async {
    if (userId.isEmpty) return null;
    
    // Verifica cache
    final cached = _presenceCache[userId];
    if (!forceRefresh && cached != null && !cached.isExpired) {
      debugPrint('✅ [ChatService] getUserOnce: cache hit for $userId');
      return cached.user;
    }
    
    try {
      debugPrint('🔄 [ChatService] getUserOnce: fetching $userId from Firestore');
      final doc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .get();
      
      if (!doc.exists) return null;
      
      final user = chat_user_model.UserModel.fromMap(doc.data() ?? {}, doc.id);
      
      // Atualiza cache
      _presenceCache[userId] = _CachedPresence(user: user, fetchedAt: DateTime.now());
      
      return user;
    } catch (e) {
      debugPrint('❌ [ChatService] getUserOnce error: $e');
      return cached?.user; // Retorna cache stale se disponível
    }
  }
  
  /// Limpa cache de presença (chamar no dispose se necessário)
  void clearPresenceCache() {
    _presenceCache.clear();
  }

  /// ⚠️ DEPRECATED: Usar getConversationOnce() para reduzir custos
  @Deprecated('Use getConversationOnce() instead to reduce Firestore reads')
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

  /// ⚠️ DEPRECATED: Usar getConversationOnce() para reduzir custos
  @Deprecated('Use getConversationOnce() instead to reduce Firestore reads')
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
          final subtitle = i18n.translate('conversation_deleted_successfully');
          
          // Show success toast após fechar a tela
          ToastService.showSuccess(
            message: subtitle,
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

/// ✅ Classe auxiliar para cache de presença com TTL
class _CachedPresence {
  _CachedPresence({required this.user, required this.fetchedAt});
  
  final chat_user_model.UserModel user;
  final DateTime fetchedAt;
  
  bool get isExpired => DateTime.now().difference(fetchedAt) > ChatService._presenceTtl;
}
