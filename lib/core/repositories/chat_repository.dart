import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/repositories/chat_repository_interface.dart';
import 'package:partiu/screens/chat/models/message.dart';
import 'package:partiu/core/services/image_compress_service.dart';
import 'package:partiu/core/services/block_service.dart';

/// Implementação do repositório de chat
class ChatRepository implements IChatRepository {

  ChatRepository();
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  Stream<List<Message>> getMessages(String withUserId) {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty || withUserId.isEmpty) {
      return const Stream.empty();
    }

    // 🎯 EVENTO: Usa EventChats/{eventId}/Messages
    if (withUserId.startsWith('event_')) {
      final eventId = withUserId.replaceFirst('event_', '');
      return _firestore
          .collection('EventChats')
          .doc(eventId)
          .collection('Messages')
          .orderBy(TIMESTAMP, descending: false)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
        print('🔍 [REPO DEBUG] Snapshot docs: ${snapshot.docs.length}');
        if (snapshot.docs.isNotEmpty) {
          final lastDocs = snapshot.docs.length > 3 ? snapshot.docs.sublist(snapshot.docs.length - 3) : snapshot.docs;
          print('🔍 [REPO DEBUG] Last 3 docs IDs: ${lastDocs.map((d) => d.id).toList()}');
        }
        return snapshot.docs
            .map((doc) => Message.fromDocument(doc.data(), doc.id))
            .where((m) => m != null)
            .cast<Message>()
            .toList();
      });
    }

    // 👤 USUÁRIO: Usa Messages/{userId}/{partnerId}
    return _firestore
        .collection(C_MESSAGES)
        .doc(currentUserId)
        .collection(withUserId)
        .orderBy(TIMESTAMP, descending: false)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      print('🔍 [REPO DEBUG] Snapshot docs: ${snapshot.docs.length}');
      return snapshot.docs
          .map((doc) => Message.fromDocument(doc.data(), doc.id))
          .where((m) => m != null)
          .cast<Message>()
          .toList();
    });
  }

  @override
  Future<void> saveMessage({
    required String type,
    required String senderId,
    required String receiverId,
    required String fromUserId,
    required String userPhotoLink,
    required String userFullName,
    required String textMsg,
    required String imgLink,
    required bool isRead,
  }) async {
    // 🔍 DIAGNOSTIC LOGS
    print('🔍 [CHAT DEBUG] ===== SAVE MESSAGE OPERATION =====');
    print('🔍 [CHAT DEBUG] Type: $type');
    print('🔍 [CHAT DEBUG] Sender ID: $senderId');
    print('🔍 [CHAT DEBUG] Receiver ID: $receiverId');
    print('🔍 [CHAT DEBUG] Is Event Chat: ${receiverId.startsWith("event_")}');
    print('🔍 [CHAT DEBUG] Message: ${textMsg.substring(0, textMsg.length < 50 ? textMsg.length : 50)}...');
    
    final timestamp = FieldValue.serverTimestamp();
    
    // 🎯 EVENTO: Usa EventChats/{eventId}/Messages (GRUPO)
    if (receiverId.startsWith('event_')) {
      final eventId = receiverId.replaceFirst('event_', '');
      print('🔍 [CHAT DEBUG] 🎯 Using EventChats architecture');
      print('🔍 [CHAT DEBUG] Event ID: $eventId');
      
      // Para mensagens de imagem, usar texto descritivo se textMsg estiver vazio
      final displayText = textMsg.isEmpty && type == 'image' ? '📷 Imagem' : textMsg;
      
      // ✅ APENAS cria a mensagem - Cloud Function atualiza as conversações
      final messageRef = _firestore
          .collection('EventChats')
          .doc(eventId)
          .collection('Messages')
          .doc();
      
      print('🔍 [CHAT DEBUG] Message Path: EventChats/$eventId/Messages/${messageRef.id}');
      
      await messageRef.set({
        'sender_id': senderId,
        'receiver_id': null, // ✅ Event Chat: receiver_id must be null
        'user_id': senderId, // Compatibilidade com modelo Message
        'sender_name': userFullName,
        'sender_photo_url': userPhotoLink,
        'message': displayText, // ✅ Campo principal
        'message_text': displayText, // Compatibilidade
        'message_type': type,
        'message_img_link': imgLink,
        'timestamp': timestamp,
        'message_read': false, // Event messages não usam message_read individual
        'readBy': [senderId], // Marca como lido pelo sender no array
      });
      
      print('✅ [CHAT DEBUG] EventChat message created - Cloud Function will update conversations');
      return;
    }
    
    // 👤 USUÁRIO: Usa Messages/{userId}/{partnerId} (1:1)
    print('🔍 [CHAT DEBUG] 👤 Using Messages/Connections architecture (1:1)');
    
    final batch = _firestore.batch();

    // Mensagem no documento do sender
    final senderMsgRef = _firestore
        .collection(C_MESSAGES)
        .doc(senderId)
        .collection(receiverId)
        .doc();
    
    print('🔍 [CHAT DEBUG] Sender Message Path: Messages/$senderId/$receiverId/${senderMsgRef.id}');

    // Para mensagens de imagem, usar texto descritivo se textMsg estiver vazio
    final displayText = textMsg.isEmpty && type == 'image' ? '📷 Imagem' : textMsg;

    batch.set(senderMsgRef, {
      'sender_id': senderId,
      'receiver_id': receiverId,
      'user_id': senderId, // ID do dono da subcoleção
      'message_type': type,
      'message': displayText, // ✅ Campo principal
      'message_text': displayText, // Compatibilidade
      'message_img_link': imgLink,
      'timestamp': timestamp,
      'message_read': true, // Sender marca como lido
    });

    // Mensagem no documento do receiver
    final receiverMsgRef = _firestore
        .collection(C_MESSAGES)
        .doc(receiverId)
        .collection(senderId)
        .doc();
    
    print('🔍 [CHAT DEBUG] Receiver Message Path: Messages/$receiverId/$senderId/${receiverMsgRef.id}');

    batch.set(receiverMsgRef, {
      'sender_id': senderId,
      'receiver_id': receiverId,
      'user_id': receiverId, // ID do dono da subcoleção
      'message_type': type,
      'message': displayText, // ✅ Campo principal (usa displayText definido acima)
      'message_text': displayText, // Compatibilidade
      'message_img_link': imgLink,
      'timestamp': timestamp,
      'message_read': isRead, // Receiver usa o parâmetro isRead
    });

    // Atualiza conversa do sender
    final senderConvRef = _firestore
        .collection(C_CONNECTIONS)
        .doc(senderId)
        .collection(C_CONVERSATIONS)
        .doc(receiverId);
    
    print('🔍 [CHAT DEBUG] Sender Conversation Path: Connections/$senderId/conversations/$receiverId');

    batch.set(senderConvRef, {
      USER_ID: receiverId,
      USER_PROFILE_PHOTO: userPhotoLink,
      fullname: userFullName,
      MESSAGE_TYPE: type,
      LAST_MESSAGE: displayText, // ✅ Usa displayText para mostrar "📷 Imagem" se for imagem
      MESSAGE_READ: true,
      TIMESTAMP: timestamp,
    }, SetOptions(merge: true));

    // Atualiza conversa do receiver
    final receiverConvRef = _firestore
        .collection(C_CONNECTIONS)
        .doc(receiverId)
        .collection(C_CONVERSATIONS)
        .doc(senderId);
    
    print('🔍 [CHAT DEBUG] Receiver Conversation Path: Connections/$receiverId/conversations/$senderId');

    final currentUser = AppState.currentUser.value;
    batch.set(receiverConvRef, {
      USER_ID: senderId,
      USER_PROFILE_PHOTO: currentUser?.photoUrl ?? '',
      fullname: currentUser?.userFullname ?? '',
      MESSAGE_TYPE: type,
      LAST_MESSAGE: displayText, // ✅ Usa displayText para mostrar "📷 Imagem" se for imagem
      MESSAGE_READ: isRead,
      'unread_count': FieldValue.increment(1),
      TIMESTAMP: timestamp,
    }, SetOptions(merge: true));

    try {
      print('🔍 [CHAT DEBUG] Committing batch write with 4 operations (1:1)...');
      await batch.commit();
      print('✅ [CHAT DEBUG] 1:1 batch commit successful!');
    } catch (e) {
      print('❌ [CHAT DEBUG] 1:1 batch commit FAILED!');
      print('❌ [CHAT DEBUG] Error Type: ${e.runtimeType}');
      print('❌ [CHAT DEBUG] Error Message: $e');
      print('❌ [CHAT DEBUG] ===== END ERROR DIAGNOSTIC =====');
      rethrow;
    }
  }

  @override
  Future<void> sendTextMessage({
    required String text,
    required User receiver,
  }) async {
    try {
      print('🔍 [CHAT DEBUG] ===== SEND TEXT MESSAGE =====');
      
      final currentUserId = AppState.currentUserId;
      print('🔍 [CHAT DEBUG] Current User ID: $currentUserId');
      
      if (currentUserId == null) {
        print('❌ [CHAT DEBUG] ERRO: Usuário não autenticado!');
        throw Exception('Usuário não autenticado');
      }

      print('🔍 [CHAT DEBUG] Receiver User ID: ${receiver.userId}');
      print('🔍 [CHAT DEBUG] Receiver Full Name: ${receiver.userFullname}');
      print('🔍 [CHAT DEBUG] Is Event Chat: ${receiver.userId.startsWith("event_")}');

      final currentUser = AppState.currentUser.value;
      print('🔍 [CHAT DEBUG] Current User Full Name: ${currentUser?.userFullname}');
      print('🔍 [CHAT DEBUG] Current User Photo: ${currentUser?.photoUrl}');
      
      if (currentUser == null) {
        print('❌ [CHAT DEBUG] ERRO: Dados do usuário não disponíveis!');
        throw Exception('Dados do usuário não disponíveis');
      }

      print('🔍 [CHAT DEBUG] Calling saveMessage...');
      
      // Salva a mensagem
      await saveMessage(
        type: 'text',
        senderId: currentUserId,
        receiverId: receiver.userId,
        fromUserId: currentUserId,
        userPhotoLink: currentUser.photoUrl ?? '',
        userFullName: currentUser.userFullname ?? '',
        textMsg: text,
        imgLink: '',
        isRead: false,
      );
      
      print('✅ [CHAT DEBUG] sendTextMessage completed successfully!');
    } catch (e) {
      print('❌ [CHAT DEBUG] sendTextMessage FAILED: $e');
      rethrow;
    }
  }

  @override
  Future<void> sendImageMessage({
    required File imageFile,
    required User receiver,
  }) async {
    try {
      print('🖼️ [CHAT DEBUG] ===== SEND IMAGE MESSAGE =====');
      
      final currentUserId = AppState.currentUserId;
      print('🖼️ [CHAT DEBUG] Current User ID: $currentUserId');
      
      if (currentUserId == null) {
        print('❌ [CHAT DEBUG] ERRO: Usuário não autenticado!');
        throw Exception('Usuário não autenticado');
      }

      print('🖼️ [CHAT DEBUG] Receiver User ID: ${receiver.userId}');
      print('🖼️ [CHAT DEBUG] Is Event Chat: ${receiver.userId.startsWith("event_")}');
      print('🖼️ [CHAT DEBUG] Image file path: ${imageFile.path}');
      print('🖼️ [CHAT DEBUG] Image file size: ${await imageFile.length()} bytes');

      // Comprimir e fazer upload para Firebase Storage
      print('🖼️ [CHAT DEBUG] Starting image compression...');
      const compressor = ImageCompressService();
      final compressed = await compressor.compressFileToTempFile(imageFile);
      print('🖼️ [CHAT DEBUG] Image compressed: ${compressed.path}');
      print('🖼️ [CHAT DEBUG] Compressed size: ${await compressed.length()} bytes');
      
      final fileName = 'chat_${currentUserId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('chat_images').child(fileName);
      
      print('🖼️ [CHAT DEBUG] Starting upload to Storage: $fileName');
      await ref.putFile(compressed);
      print('🖼️ [CHAT DEBUG] Upload complete, getting download URL...');
      
      final imageUrl = await ref.getDownloadURL();
      print('🖼️ [CHAT DEBUG] Download URL obtained: $imageUrl');
      
      // Limpar arquivo temporário comprimido
      try {
        if (compressed.path != imageFile.path && await compressed.exists()) {
          await compressed.delete();
          print('🖼️ [CHAT DEBUG] Temporary file cleaned');
        }
      } catch (e) {
        print('⚠️ [CHAT DEBUG] Failed to clean temp file: $e');
      }

      final currentUser = AppState.currentUser.value;
      print('🖼️ [CHAT DEBUG] Current User Full Name: ${currentUser?.userFullname}');
      
      if (currentUser == null) {
        print('❌ [CHAT DEBUG] ERRO: Dados do usuário não disponíveis!');
        throw Exception('Dados do usuário não disponíveis');
      }

      print('🖼️ [CHAT DEBUG] Calling saveMessage with image...');
      
      // Salva a mensagem
      await saveMessage(
        type: 'image',
        senderId: currentUserId,
        receiverId: receiver.userId,
        fromUserId: currentUserId,
        userPhotoLink: currentUser.photoUrl ?? '',
        userFullName: currentUser.userFullname ?? '',
        textMsg: '',
        imgLink: imageUrl,
        isRead: false,
      );
      
      print('✅ [CHAT DEBUG] sendImageMessage completed successfully!');
    } catch (e, stackTrace) {
      print('❌ [CHAT DEBUG] sendImageMessage FAILED: $e');
      print('❌ [CHAT DEBUG] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<bool> isUserBlocked({
    required String blockedUserId,
    required String blockedByUserId,
  }) async {
    // 🆕 Usar BlockService com cache (instantâneo)
    return BlockService().isBlockedCached(blockedByUserId, blockedUserId);
  }

  @override
  Future<bool> blockUser({
    required String blockedUserId,
  }) async {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) return false;

    // 🆕 Usar novo BlockService
    await BlockService().blockUser(currentUserId, blockedUserId);
    
    return true;
  }

  @override
  Future<void> unblockUser({
    required String blockedUserId,
  }) async {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) return;

    // 🆕 Usar novo BlockService
    await BlockService().unblockUser(currentUserId, blockedUserId);
  }

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> getUserUpdates(String userId) {
    if (userId.isEmpty) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .snapshots();
  }

  @override
  Future<void> deleteChat(String withUserId, {bool isDoubleDel = false}) async {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) return;

    final batch = _firestore.batch();

    // Deleta mensagens
    final messagesSnapshot = await _firestore
        .collection(C_MESSAGES)
        .doc(currentUserId)
        .collection(withUserId)
        .get();

    for (final doc in messagesSnapshot.docs) {
      batch.delete(doc.reference);
    }

    // Deleta conversa
    final convRef = _firestore
        .collection(C_CONNECTIONS)
        .doc(currentUserId)
        .collection(C_CONVERSATIONS)
        .doc(withUserId);

    batch.delete(convRef);

    // Se isDoubleDel, deleta também do outro usuário
    if (isDoubleDel) {
      final otherMessagesSnapshot = await _firestore
          .collection(C_MESSAGES)
          .doc(withUserId)
          .collection(currentUserId)
          .get();

      for (final doc in otherMessagesSnapshot.docs) {
        batch.delete(doc.reference);
      }

      final otherConvRef = _firestore
          .collection(C_CONNECTIONS)
          .doc(withUserId)
          .collection(C_CONVERSATIONS)
          .doc(currentUserId);

      batch.delete(otherConvRef);
    }

    await batch.commit();
  }
}
