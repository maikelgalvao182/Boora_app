import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// Socket.IO Service para comunicação em tempo real com WebSocket Service
/// Substitui Firestore Streams por WebSocket para reduzir complexidade
class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  static SocketService get instance => _instance;

  SocketService._internal() {
  }

  IO.Socket? _socket;
  bool _isConnected = false;
  String? _wsUrl;

  /// URL do WebSocket Service
  /// IMPORTANTE: Detecta automaticamente emulador Android vs iOS Simulator
  static String get _devUrl {
    if (Platform.isAndroid) {
      return 'ws://10.0.2.2:8080'; // ✅ Emulador Android
    }
    return 'ws://127.0.0.1:8080'; // ✅ iOS Simulator
  }
  
  static const String _prodUrl = 'wss://partiu-websocket-13564294004.us-central1.run.app';

  bool get isConnected => _isConnected;

  /// Aguarda até a conexão estar estabelecida (timeout: 5 segundos)
  Future<bool> waitForConnection({Duration timeout = const Duration(seconds: 5)}) async {
    if (_isConnected) return true;
    
    final startTime = DateTime.now();
    while (!_isConnected && DateTime.now().difference(startTime) < timeout) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    return _isConnected;
  }

  /// Conecta ao WebSocket Service
  Future<void> connect({bool useProduction = true}) async {
    if (_isConnected) {
      return;
    }

    _wsUrl = useProduction ? _prodUrl : _devUrl;
    
    try {
      // Pega token do Firebase Auth
      var user = FirebaseAuth.instance.currentUser;
      
      if (user == null) {
        
        // Tenta aguardar até 2 segundos pelo FirebaseAuth carregar
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          user = FirebaseAuth.instance.currentUser;
          
          if (user != null) {
            break;
          }
        }
        
        if (user == null) {
          return;
        }
      }

      final token = await user.getIdToken();


      // Configura Socket.IO forçando WebSocket puro
      _socket = IO.io(
        _wsUrl,
        IO.OptionBuilder()
            .setTransports(['websocket']) // APENAS WebSocket, sem polling
            .disableAutoConnect() // Controle manual
            .enableReconnection()
            .setReconnectionDelay(2000)
            .setReconnectionDelayMax(5000)
            .setReconnectionAttempts(3)
            .setAuth({'token': token})
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            .enableForceNew() // Força nova conexão
            // Configurações adicionais
            .setTimeout(10000) // 10s timeout
            .build(),
      );

      // Re-aplica listeners persistentes
      _eventHandlers.forEach((event, handlers) {
        for (final handler in handlers) {
          // 🔥 FIX: Socket.IO pode enviar 2 params (eventName, data) em alguns wrappers
          // Mas a maioria envia só (data), então usamos callback flexível
          _socket!.on(event, (data) {
            print('[SocketService] Event received: $event');
            handler(data);
          });
        }
      });
      print('✅ Attached ${_eventHandlers.length} pending event listeners types');

      // 🔥 DEBUG: Log TODOS os eventos recebidos do WebSocket
      _socket!.onAny((event, data) {
        print('🔥 WS EVENT RECEIVED: $event');
      });

      // Listeners de conexão
      _socket!.onConnect((_) {
        _isConnected = true;
        print('✅ WebSocket connected to $_wsUrl');
        
        // 🔥 AUTO-SUBSCRIBE: Subscrever IMEDIATAMENTE após conectar
        // ⚠️ IMPORTANTE: NÃO recarrega dados aqui - apenas subscreve para eventos futuros
        Future.delayed(const Duration(milliseconds: 500), () {
          subscribeToApplications();
        });
      });

      _socket!.onDisconnect((reason) {
        _isConnected = false;
        
        // 🔥 REGRA CRÍTICA: Desconexão NÃO deve limpar nenhum estado da UI
        // O WebSocket é apenas para eventos incrementais (novos/updates)
        // A lista de dados permanece intacta durante reconexões
        
        print('❌ WebSocket DISCONNECTED - Reason: $reason');
        print('   Common reasons:');
        print('   - "transport close": rede caiu ou timeout (Cloud Run restart)');
        print('   - "ping timeout": servidor não respondeu keep-alive');
        print('   - "server disconnect": backend encerrou conexão');
        print('   - "io server disconnect": servidor Socket.IO forçou desconexão');
        print('   - "io client disconnect": cliente desconectou manualmente');
        print('   - "authentication error": token inválido/expirado');
        print('⚠️ UI state mantido - aguardando reconexão...');
      });

      _socket!.onConnectError((error) {
        _isConnected = false;
        print('❌ WebSocket connection error: $error');
      });

      _socket!.onError((error) {
        print('❌ WebSocket error: $error');
      });

      // 🔥 NOVO: Monitorar tentativas de reconexão
      _socket!.onReconnect((attempt) {
        _isConnected = true;
        print('🔄 WebSocket reconnected successfully - Attempt: $attempt');
        print('   ℹ️ Estado da UI preservado - apenas resubscrevendo eventos');
        
        // 🔥 IMPORTANTE: NÃO recarrega dados aqui
        // Apenas garante que a subscrição está ativa para novos eventos
      });

      _socket!.onReconnectAttempt((attempt) {
        print('⚠️ WebSocket reconnection attempt #$attempt');
        // 🔥 IMPORTANTE: Obter novo token antes de reconectar
        _refreshTokenForReconnection();
      });

      _socket!.onReconnectError((error) {
        print('❌ WebSocket reconnection error: $error');
      });

      _socket!.onReconnectFailed((_) {
        print('❌ WebSocket reconnection FAILED after all attempts');
        _isConnected = false;
      });

      // Conecta manualmente
      _socket!.connect();
      print('🔌 Connecting to WebSocket: $_wsUrl');
      
      // 🚨 Timeout de diagnóstico: se após 5s não conectar, algo está errado
      Future.delayed(const Duration(seconds: 5), () {
        if (!_isConnected && _socket != null) {
          print('⏱️ WebSocket not connected after 5 seconds - check backend');
        }
      });
    } catch (e, stackTrace) {
      print('❌ Error connecting to WebSocket: $e\n$stackTrace');
    }
  }

  /// Desconecta do WebSocket
  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
    }
  }

  // Armazena listeners registrados para re-aplicar em reconexões ou inicialização tardia
  final Map<String, List<Function(dynamic)>> _eventHandlers = {};

  /// Escuta eventos do WebSocket
  void on(String event, Function(dynamic) handler) {
    // Adiciona à lista de handlers persistentes
    _eventHandlers.putIfAbsent(event, () => []).add(handler);

    // Se o socket já existir, registra imediatamente
    if (_socket != null) {
      _socket!.on(event, (data) {
        print('[SocketService] Event received: $event');
        handler(data);
      });
      print('✅ Listener registered immediately for: $event');
    } else {
      print('⚠️ Socket not ready, queuing listener for event: $event');
    }
  }

  /// Remove listener de um evento
  void off(String event) {
    _eventHandlers.remove(event);
    
    if (_socket == null) return;
    _socket!.off(event);
  }

  /// Envia evento para o WebSocket
  void emit(String event, [dynamic data]) {
    print('🔌 [SocketService] emit called: $event');
    
    if (_socket == null || !_isConnected) {
      print('⚠️ Emit aborted: socket null or not connected');
      return;
    }
    
    _socket!.emit(event, data);
    print('✅ Event emitted to server: $event');
  }

  /// Subscreve para receber atualizações de aplicações
  /// Envia automaticamente o vendorId do usuário autenticado
  void subscribeToApplications({String? announcementId}) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    
    if (userId == null) {
      print('⚠️ Cannot subscribe to applications: userId is null');
      return;
    }
    
    if (!_isConnected) {
      print('⚠️ Cannot subscribe to applications: not connected');
      return;
    }
    
    emit('applications:subscribe', {
      'vendorId': userId,
      if (announcementId != null) 'announcementId': announcementId,
    });
    print('✅ Subscribed to applications for vendorId: $userId');
  }

  /// Subscreve para receber atualizações de conversas
  void subscribeToConversations() {
    if (!_isConnected) {
      print('⚠️ Cannot subscribe to conversations: not connected');
      return;
    }
    
    emit('conversations:subscribe');
    print('✅ Subscribed to conversations');
  }

  /// Subscreve para receber mensagens de um chat específico
  void subscribeToMessages(String withUserId) {
    print('🔌 [SocketService] subscribeToMessages called');
    print('   - withUserId: $withUserId');
    print('   - connected: $_isConnected');
    
    if (!_isConnected) {
      print('⚠️ Not connected, subscription aborted');
      return;
    }
    
    emit('messages:subscribe', {'withUserId': withUserId});
    print('✅ Subscribed to messages with user: $withUserId');
  }

  /// Cancela subscrição de mensagens de um chat
  void unsubscribeFromMessages(String withUserId) {
    if (!_isConnected) {
      print('⚠️ Cannot unsubscribe from messages: not connected');
      return;
    }
    
    emit('messages:unsubscribe', {'withUserId': withUserId});
    print('🔕 Unsubscribed from messages with user: $withUserId');
  }

  /// Listener helper para snapshot inicial de conversas
  void onConversationsSnapshot(
    void Function(Map<String, dynamic>) handler,
  ) {
    on('conversations:snapshot', (data) {
      if (data is Map<String, dynamic>) {
        handler(data);
      }
    });
  }

  /// Listener helper para updates incrementais de conversas
  void onConversationsUpdated(
    void Function(Map<String, dynamic>) handler,
  ) {
    on('conversations:updated', (data) {
      if (data is Map<String, dynamic>) {
        handler(data);
      }
    });
  }

  /// Listener helper para contador de conversas não lidas
  void onConversationsUnreadCount(
    void Function(int) handler,
  ) {
    on('conversations:unread_count', (data) {
      if (data is Map<String, dynamic>) {
        final count = (data['unreadCount'] as num?)?.toInt() ?? 0;
        handler(count);
      }
    });
  }

  /// Listener helper para snapshot inicial de mensagens
  void onMessagesSnapshot(
    void Function(String withUserId, List<Map<String, dynamic>> messages) handler,
  ) {
    on('messages:snapshot', (data) {
      print('🔌 [SocketService] Received messages:snapshot event');
      
      if (data is Map<String, dynamic>) {
        final withUserId = data['withUserId'] as String?;
        final messages = (data['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        print('   - withUserId: $withUserId, messages count: ${messages.length}');
        
        if (withUserId != null) {
          handler(withUserId, messages);
        }
      } else {
        print('   ⚠️ Data is not Map<String, dynamic>: $data');
      }
    });
  }

  /// Listener helper para nova mensagem
  void onNewMessage(
    void Function(Map<String, dynamic> data) handler,
  ) {
    on('messages:new', (data) {
      print('🔌 [SocketService] Received messages:new event');
      
      if (data is Map<String, dynamic>) {
        print('✅ Processing new message event');
        handler(data);
      } else {
        print('   ⚠️ Data is not Map<String, dynamic>: $data');
      }
    });
  }

  /// Listener helper para mensagem atualizada
  void onMessageUpdated(
    void Function(String messageId, Map<String, dynamic> updates) handler,
  ) {
    on('messages:updated', (data) {
      if (data is Map<String, dynamic>) {
        final messageId = data['messageId'] as String?;
        final updates = data['updates'] as Map<String, dynamic>?;
        if (messageId != null && updates != null) {
          handler(messageId, updates);
        }
      }
    });
  }

  /// 🔥 NOVO: Atualiza token Firebase antes de reconectar
  /// Evita erro de autenticação quando token expira
  Future<void> _refreshTokenForReconnection() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ Cannot refresh token: user is null');
        return;
      }

      // Força refresh do token (true = forçar novo token)
      final newToken = await user.getIdToken(true);
      
      if (_socket != null && newToken != null) {
        // Atualiza auth no socket existente
        _socket!.auth = {'token': newToken};
        print('✅ Token refreshed for reconnection');
      }
    } catch (e, stackTrace) {
      print('❌ Error refreshing token for reconnection: $e\n$stackTrace');
    }
  }

  /// Dispose (usado no logout)
  void dispose() {
    disconnect();
  }
}
