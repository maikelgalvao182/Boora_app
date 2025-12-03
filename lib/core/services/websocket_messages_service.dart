import 'dart:async';
import 'package:partiu/screens/chat/models/message.dart';
import 'package:partiu/core/services/socket_service.dart';

/// Serviço WebSocket REESCRITO com arquitetura correta, segura e escalável.
class WebSocketMessagesService {
  static final WebSocketMessagesService _instance =
      WebSocketMessagesService._internal();

  factory WebSocketMessagesService() => _instance;
  static WebSocketMessagesService get instance => _instance;

  WebSocketMessagesService._internal() {
    _registerGlobalListeners();
  }

  final SocketService _socket = SocketService.instance;

  /// StreamControllers por chatId
  final Map<String, StreamController<List<Message>>> _streams = {};

  /// Cache imutável de mensagens por chatId
  final Map<String, List<Message>> _cache = {};

  /// Controle de assinaturas ativas por chatId
  final Set<String> _activeChats = {};

  /// ---------------------------------------------------------
  ///              LISTENERS GLOBAIS (UMA VEZ SÓ)
  /// ---------------------------------------------------------
  void _registerGlobalListeners() {
    print("🎧 Registering GLOBAL WebSocket listeners");

    _socket.onMessagesSnapshot(_handleSnapshot);
    print("   ✅ onMessagesSnapshot listener registered");
    
    _socket.onNewMessage(_handleNewMessage);
    print("   ✅ onNewMessage listener registered");
    
    _socket.onMessageUpdated(_handleMessageUpdated);
    print("   ✅ onMessageUpdated listener registered");
  }

  /// ---------------------------------------------------------
  ///                   HANDLERS GLOBAIS
  /// ---------------------------------------------------------

  void _handleSnapshot(String chatId, List<dynamic> dataList) {
    if (!_activeChats.contains(chatId)) return;

    print("📸 Snapshot ($chatId): ${dataList.length} messages");

    final messages = dataList.map((data) {
      return Message(
        id: data['id'] ?? '',
        text: data['message_text'],
        imageUrl: data['message_img_link'],
        senderId: data['sender_id'] ?? data['senderId'], // Don't fallback to empty string
        receiverId: data['receiver_id'] ?? data['receiverId'],
        userId: data['user_id'] ?? '',
        type: data['message_type'] ?? 'text',
        timestamp: _parseTimestamp(data['timestamp']),
        isRead: data['message_read'] ?? false,
        params: data['message_params'],
      );
    }).toList();

    // Ordena sempre
    messages.sort((a, b) {
      final t1 = a.timestamp ?? DateTime(1970);
      final t2 = b.timestamp ?? DateTime(1970);
      return t1.compareTo(t2);
    });

    _cache[chatId] = List.unmodifiable(messages);
    print("📦 Cache updated for $chatId (${messages.length} messages)");

    if (_streams[chatId] != null) {
      _streams[chatId]!.add(_cache[chatId]!);
      print("📤 Snapshot stream updated for $chatId (${messages.length} messages)");
    } else {
      print("⚠️ No stream found for snapshot $chatId");
    }
  }

  void _handleNewMessage(Map<String, dynamic> data) {
    print("📩 New Message Event received");
    
    final messageData = data['message'];
    if (messageData == null) {
      print("❌ No message data in event");
      return;
    }

    final senderId = data['senderId'];
    final receiverId = data['receiverId'];
    
    print("   - senderId: $senderId");
    print("   - receiverId: $receiverId");

    // 🔥 FIX CRÍTICO: chatId é sempre o remoteUserId (outro usuário)
    // Então precisamos verificar se chatId corresponde ao senderId OU receiverId
    var foundMatch = false;
    for (final chatId in _activeChats) {
      // chatId deve ser senderId OU receiverId (o outro usuário no chat)
      if (chatId == senderId || chatId == receiverId) {
        print("   ✅ Found matching chat: $chatId");
        _addMessageToChat(chatId, messageData);
        foundMatch = true;
        break;
      }
    }
    
    if (!foundMatch) {
      print("   ⚠️ No matching chat found for senderId: $senderId, receiverId: $receiverId");
      print("   ⚠️ Active chats: $_activeChats");
    }
  }

  void _addMessageToChat(String chatId, Map<String, dynamic> raw) {
    final msg = Message(
      id: raw['id'] ?? '',
      text: raw['message_text'],
      imageUrl: raw['message_img_link'],
      senderId: raw['sender_id'] ?? raw['senderId'], // Don't fallback to empty string
      receiverId: raw['receiver_id'] ?? raw['receiverId'],
      userId: raw['user_id'] ?? '',
      type: raw['message_type'] ?? 'text',
      timestamp: _parseTimestamp(raw['timestamp']),
      isRead: raw['message_read'] ?? false,
      params: raw['message_params'],
    );

    final prev = _cache[chatId] ?? const [];

    final updated = [...prev, msg];
    updated.sort((a, b) {
      final t1 = a.timestamp ?? DateTime(1970);
      final t2 = b.timestamp ?? DateTime(1970);
      return t1.compareTo(t2);
    });

    _cache[chatId] = List.unmodifiable(updated);
    
    if (_streams[chatId] != null) {
      _streams[chatId]!.add(_cache[chatId]!);
      print("📤 Stream updated for $chatId (${updated.length} messages)");
    } else {
      print("⚠️ Stream for $chatId is null!");
    }

    print("💬 New message added to $chatId");
  }

  void _handleMessageUpdated(String messageId, Map<String, dynamic> updates) {
    for (final chatId in _activeChats) {
      final list = _cache[chatId];
      if (list == null) continue;

      final index = list.indexWhere((m) => m.id == messageId);
      if (index == -1) continue;

      print("🔄 Updating message $messageId in $chatId");

      final old = list[index];
      final updated = old.copyWith(
        text: updates['message_text'],
        imageUrl: updates['message_img_link'],
        isRead: updates['message_read'],
        params: updates['message_params'],
      );

      final newList = [...list];
      newList[index] = updated;

      _cache[chatId] = List.unmodifiable(newList);
      _streams[chatId]?.add(newList);

      break;
    }
  }

  /// ---------------------------------------------------------
  ///                      API PÚBLICA
  /// ---------------------------------------------------------

  /// Retorna stream de mensagens de um chat
  Stream<List<Message>> getMessagesStream(String chatId) {
    if (_streams.containsKey(chatId)) {
      return _streams[chatId]!.stream;
    }

    final controller = StreamController<List<Message>>.broadcast(
      onListen: () {
        print("📱 Stream listener attached for $chatId");
        _subscribe(chatId);
      },
      onCancel: () {
        print("📱 Stream listener cancelled for $chatId");
        _unsubscribe(chatId);
      },
    );

    print("📡 StreamController created for $chatId");
    _streams[chatId] = controller;
    return controller.stream;
  }

  Future<void> _subscribe(String chatId) async {
    if (_activeChats.contains(chatId)) {
      print("⚠️ Already subscribed to chat: $chatId");
      return;
    }

    print("🔔 Subscribing to chat: $chatId");
    print("   - Socket connected: ${_socket.isConnected}");

    final connected = await _socket.waitForConnection();
    print("   - Wait for connection result: $connected");
    
    if (!connected) {
      print("   ❌ Failed to connect to WebSocket");
      return;
    }
    
    _socket.subscribeToMessages(chatId);
    print("   ✅ Subscription request sent to WebSocket");

    _activeChats.add(chatId);
    print("   ✅ Added to active chats: $_activeChats");

    // Se já existia um cache antigo, emite primeiro
    if (_cache.containsKey(chatId)) {
      _streams[chatId]?.add(_cache[chatId]!);
    }
  }

  void _unsubscribe(String chatId) {
    if (!_activeChats.contains(chatId)) return;

    print("🔕 Unsubscribing from chat: $chatId");

    _activeChats.remove(chatId);
    _socket.unsubscribeFromMessages(chatId);
    _cache.remove(chatId);
  }

  void dispose() {
    print("🧹 Disposing WebSocketMessagesService");

    for (final c in _streams.values) {
      c.close();
    }

    _activeChats.clear();
    _cache.clear();
    _streams.clear();
  }

  DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    if (timestamp is String) return DateTime.tryParse(timestamp);
    if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (timestamp is Map) {
      // Handle Firestore timestamp object { "_seconds": ..., "_nanoseconds": ... }
      final seconds = timestamp['_seconds'] ?? timestamp['seconds'];
      final nanoseconds = timestamp['_nanoseconds'] ?? timestamp['nanoseconds'] ?? 0;
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000 + (nanoseconds as int) ~/ 1000000);
      }
    }
    return null;
  }
}
