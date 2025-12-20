import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/repositories/chat_repository_interface.dart';
import 'package:partiu/screens/chat/models/message.dart';
import 'package:partiu/screens/chat/models/reply_snapshot.dart';
import 'package:flutter/material.dart';

/// ViewModel para a tela de chat
class ChatViewModel extends ChangeNotifier {
  
  ChatViewModel({required IChatRepository chatRepository})
      : _chatRepository = chatRepository;
  final IChatRepository _chatRepository;
  
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isRemoteUserBlocked = false;
  bool _isLocalUserBlocked = false;
  User? _remoteUser;
  
  // Getters
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  bool get isRemoteUserBlocked => _isRemoteUserBlocked;
  bool get isLocalUserBlocked => _isLocalUserBlocked;
  User? get remoteUser => _remoteUser;
  
  // Setters
  void setRemoteUser(User user) {
    _remoteUser = user;
    notifyListeners();
  }
  
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  void _setErrorMessage(String message) {
    _errorMessage = message;
    notifyListeners();
  }
  
  void _setRemoteUserBlocked(bool blocked) {
    _isRemoteUserBlocked = blocked;
    notifyListeners();
  }
  
  void _setLocalUserBlocked(bool blocked) {
    _isLocalUserBlocked = blocked;
    notifyListeners();
  }
  
  /// Obtém as mensagens entre o usuário atual e outro usuário
  Stream<List<Message>> getMessages(String withUserId) {
    return _chatRepository.getMessages(withUserId);
  }
  
  /// Obtém atualizações do usuário remoto
  Stream<DocumentSnapshot<Map<String, dynamic>>> getUserUpdates(String userId) {
    return _chatRepository.getUserUpdates(userId);
  }
  
  /// Envia uma mensagem de texto
  Future<void> sendTextMessage({
    required String text,
    required User receiver,
    required Function(String) onError,
    ReplySnapshot? replySnapshot, // 🆕 Dados de reply
  }) async {
    if (text.trim().isEmpty) return;
    
    _setLoading(true);
    try {
      await _chatRepository.sendTextMessage(
        text: text,
        receiver: receiver,
        replySnapshot: replySnapshot, // 🆕 Passar para repository
      );
    } catch (e) {
      _setErrorMessage(e.toString());
      onError(e.toString());
    } finally {
      _setLoading(false);
    }
  }
  
  /// Envia uma mensagem com imagem
  Future<void> sendImageMessage({
    required File imageFile,
    required User receiver,
    required Function(String) onError,
    ReplySnapshot? replySnapshot, // 🆕 Dados de reply
  }) async {
    _setLoading(true);
    try {
      await _chatRepository.sendImageMessage(
        imageFile: imageFile,
        receiver: receiver,
        replySnapshot: replySnapshot, // 🆕 Passar para repository
      );
    } catch (e) {
      _setErrorMessage(e.toString());
      onError(e.toString());
    } finally {
      _setLoading(false);
    }
  }
  
  /// Verifica o status de bloqueio do usuário
  Future<void> checkBlockedUserStatus({
    required String remoteUserId,
    required String localUserId,
  }) async {
    try {
      // Verifica se o usuário remoto está bloqueado pelo usuário local
      final isRemoteBlocked = await _chatRepository.isUserBlocked(
        blockedUserId: remoteUserId,
        blockedByUserId: localUserId,
      );
      _setRemoteUserBlocked(isRemoteBlocked);
      
      // Verifica se o usuário local está bloqueado pelo usuário remoto
      final isLocalBlocked = await _chatRepository.isUserBlocked(
        blockedUserId: localUserId,
        blockedByUserId: remoteUserId,
      );
      _setLocalUserBlocked(isLocalBlocked);
    } catch (e) {
      _setErrorMessage(e.toString());
    }
  }
  
  /// Bloqueia um usuário
  Future<bool> blockUser({
    required String blockedUserId,
  }) async {
    _setLoading(true);
    try {
      final result = await _chatRepository.blockUser(
        blockedUserId: blockedUserId,
      );
      _setRemoteUserBlocked(true);
      return result;
    } catch (e) {
      _setErrorMessage(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }
  
  /// Desbloqueia um usuário
  Future<void> unblockUser({
    required String blockedUserId,
  }) async {
    _setLoading(true);
    try {
      await _chatRepository.unblockUser(
        blockedUserId: blockedUserId,
      );
      _setRemoteUserBlocked(false);
    } catch (e) {
      _setErrorMessage(e.toString());
    } finally {
      _setLoading(false);
    }
  }
  
  /// Deleta o chat com um usuário
  Future<void> deleteChat(String withUserId, {bool isDoubleDel = false}) async {
    _setLoading(true);
    try {
      await _chatRepository.deleteChat(withUserId, isDoubleDel: isDoubleDel);
    } catch (e) {
      _setErrorMessage(e.toString());
    } finally {
      _setLoading(false);
    }
  }
  
  /// Deleta o match com um usuário - DEPRECATED: Matches functionality removed
  Future<void> deleteMatch(String matchedUserId) async {
    _setLoading(true);
    try {
      // Match functionality removed in migration
      // Deleta o chat
      await deleteChat(matchedUserId);
    } catch (e) {
      _setErrorMessage(e.toString());
    } finally {
      _setLoading(false);
    }
  }
}
