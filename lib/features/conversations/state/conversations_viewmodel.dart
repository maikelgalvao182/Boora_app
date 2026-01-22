import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/common/utils/app_logger.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/conversations/models/conversation_item.dart';
import 'package:partiu/features/conversations/services/conversation_cache_service.dart';
import 'package:partiu/features/conversations/services/conversation_data_processor.dart';
import 'package:partiu/features/conversations/services/conversation_navigation_service.dart';
import 'package:partiu/features/conversations/services/conversation_pagination_service.dart';
import 'package:partiu/features/conversations/services/conversation_state_service.dart';
import 'package:partiu/features/conversations/state/conversation_activity_bus.dart';
import 'package:partiu/features/conversations/state/optimistic_removal_bus.dart';
import 'package:partiu/core/services/auth_state_service.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/core/services/socket_service.dart';
import 'package:partiu/core/services/subscription_monitoring_service.dart';
import 'package:partiu/core/services/global_cache_service.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// ViewModel responsável por coordenar conversas
/// Usa services dedicados para cache local e paginação
/// + GlobalCacheService para cache enterprise com TTL
class ConversationsViewModel extends ChangeNotifier {
  ConversationsViewModel() {
    _initialize();
  }
  
  // Services
  late final ConversationNavigationService _navigationService;
  late final ConversationStateService _stateService;
  late final ConversationCacheService _cacheService;
  late final ConversationPaginationService _paginationService;
  final SocketService _socket = SocketService.instance;
  final GlobalCacheService _globalCache = GlobalCacheService.instance;
  
  // WebSocket-backed state (ainda não usado na UI)
  List<ConversationItem> _wsConversations = <ConversationItem>[];
  String _searchQuery = '';
  int _wsUnreadCount = 0;
  
  // ✅ Stream do Firestore para atualizações em tempo real
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSubscription;

  StreamSubscription<User?>? _authSubscription;

  VoidCallback? _activityBusListener;
  
  // ValueNotifier para badge de conversas não lidas (apenas visíveis)
  final ValueNotifier<int> visibleUnreadCount = ValueNotifier<int>(0);
  
  // UI state
  bool _isProcessingPayment = false;
  bool _isRefreshing = false;
  bool _initialized = false;
  bool _firestoreStarted = false;
  bool _hasReceivedFirstSnapshot = false;
  final ScrollController _scrollController = ScrollController();
  
  // Blocked users integration
  Timer? _searchDebounce;

  // Getters - delegate to services where appropriate
  ConversationNavigationService get navigationService => _navigationService;
  ConversationStateService get stateService => _stateService;
  ScrollController get scrollController => _scrollController;
  bool get hasReceivedFirstSnapshot {
    _log('🔍 hasReceivedFirstSnapshot: $_hasReceivedFirstSnapshot');
    return _hasReceivedFirstSnapshot;
  }
  List<ConversationItem> get wsConversations => _wsConversations;
  List<ConversationItem> get filteredWsConversations {
    _log('🔍 filteredWsConversations: _wsConversations=${_wsConversations.length}, query="$_searchQuery"');
    final q = _searchQuery;
    if (q.isEmpty) return _wsConversations;

    final qLower = q.toLowerCase();
    return _wsConversations.where((c) {
      final name = c.userFullname.toLowerCase();
      return name.contains(qLower);
    }).toList(growable: false);
  }
  int get wsUnreadCount => _wsUnreadCount;
  
  // Pagination getters - delegate to PaginationService
  String get query => _paginationService.query;
  bool get hasQuery => _paginationService.hasQuery;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get filteredDocs => _paginationService.filteredDocs;
  bool get isLoadingMore => _paginationService.isLoadingMore;
  bool get hasMore => _paginationService.hasMore;
  int get pageSize => _paginationService.pageSize;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? get lastDocs => _paginationService.lastDocs;
  Set<String> get blockedIds => _paginationService.blockedIds;
  
  // UI state getters
  bool get isProcessingPayment => _isProcessingPayment;
  bool get isRefreshing => _isRefreshing;
  
  /// Getter para calcular isVipEffective (lógica VIP)
  bool get isVipEffective {
    return CHAT_VIP_GATING_ENABLED
        ? (SubscriptionMonitoringService.instance.hasVipAccess || !NOTIFICATIONS_REQUIRE_VIP_SUBSCRIPTION)
        : true; // VIP gating desativado para chat
  }
  
  /// Helper para logs padronizados em debug
  void _log(String msg) {
    if (kDebugMode) {
      AppLogger.debug('🔍 [ConversationsVM] $msg');
    }
  }
  
  /// Inicializa o ViewModel e todos os services
  void _initialize() {
    if (_initialized) return;
    _initialized = true;

    _log('🔬 [ConversationsVM] initialize() chamado');
    // Initialize services
    _cacheService = ConversationCacheService();
    _paginationService = ConversationPaginationService();
    
    // Listen to pagination changes and notify listeners
    _paginationService.addListener(_onPaginationChanged);
    
    // Initialize stream
    final isGuest = AuthStateService.instance.isGuest;
    _log('🔬 [ConversationsVM] stream começou - isGuest: $isGuest');
    
    // Streams de Firestore para a lista principal foram substituídos
    // por WebSocket (wsConversations). Firestore continua sendo usado
    // apenas para paginação via fetchConversationsPage.
    
    _navigationService = const ConversationNavigationService();
    _stateService = const ConversationStateService();
    
    _initBlockedUsersFiltering();
    
    // ✅ Iniciar stream do Firestore IMEDIATAMENTE (independente do WebSocket)
    // 🔥 ESCUTAR AUTH para garantir que o stream só inicie quando o usuário estiver logado
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _log('✅ Auth detectado, iniciando Firestore stream');
        _initFirestoreStreamSafely();
        return;
      }

      _log('🚪 Auth null detectado, cancelando Firestore stream');
      _handleLoggedOut();
    });
    
    _initWebSocketListeners();
    
    // Listen to global removal bus for instant UI updates
    ConversationRemovalBus.instance.hiddenUserIds.addListener(_onRemovalBusChanged);

    // Also reflect recent push activity in the bottom-nav badge count.
    _activityBusListener = () {
      _updateVisibleUnreadCount();
    };
    ConversationActivityBus.instance.touchedConversationIds.addListener(_activityBusListener!);
    _log('🟢 [ConversationsViewModel] _initialize concluído');
  }

  /// Inicializa o stream do Firestore de forma segura (apenas uma vez)
  void _initFirestoreStreamSafely() {
    if (_firestoreStarted) return;
    _firestoreStarted = true;

    _initFirestoreStream();
  }

  /// Inicializa listeners do WebSocket para conversas (paralelo ao Firestore)
  void _initWebSocketListeners() {
    if (AuthStateService.instance.isGuest) {
      return;
    }

    Future.microtask(() async {
      try {
        if (!_socket.isConnected) {
          await _socket.connect();
        }

        // ⚠️ WebSocket listeners desativados para evitar conflito com Firestore Stream
        // O Firestore Stream (_initFirestoreStream) é a fonte da verdade para a lista de conversas.
        // O WebSocket estava sobrescrevendo a lista com dados potencialmente desatualizados.
        
        /*
        // Carrega a primeira página das conversas antigas via Firestore
        // para evitar skeleton fixo enquanto o WebSocket não responde.
        await _loadInitialFromFirestore();

        _socket.subscribeToConversations();
        _socket.onConversationsSnapshot(_handleWsSnapshot);
        _socket.onConversationsUpdated(_handleWsUpdated);
        */
        
        _socket.onConversationsUnreadCount((unreadCount) {
          _wsUnreadCount = unreadCount;
          notifyListeners();
        });
      } catch (_) {
        // Falhas de WebSocket não devem afetar a UI atual baseada em Firestore
      }
    });
  }
  
  /// ✅ Inicializa stream do Firestore para atualizações em tempo real
  /// Funciona como fallback quando o WebSocket não emite eventos
  void _initFirestoreStream() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _log('⚠️ _initFirestoreStream: Usuário não autenticado');
      return;
    }
    
    _log('🔄 _initFirestoreStream: Iniciando stream para userId=$userId');
    _log('🔄 _initFirestoreStream: Path = Connections/$userId/Conversations');
    
    _firestoreSubscription?.cancel();
    _firestoreSubscription = FirebaseFirestore.instance
        .collection('Connections')
        .doc(userId)
        .collection('Conversations')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots(includeMetadataChanges: false) // ✅ Remover metadata changes para evitar eventos duplicados
        .listen(
      (snapshot) {
        _log('🔄 Firestore stream: ${snapshot.docs.length} conversas recebidas (source: ${snapshot.metadata.isFromCache ? "cache" : "server"})');
        
        // 🔥 Log de mudanças de documentos (added, modified, removed)
        for (final change in snapshot.docChanges) {
          _log('📝 Doc ${change.type.name}: ${change.doc.id}');
        }
        
        _handleFirestoreSnapshot(snapshot);
      },
      onError: (error) {
        _handleFirestoreStreamError(error);
      },
    );
    
    _log('✅ _initFirestoreStream: Stream listener configurado');
  }

  void _handleLoggedOut() {
    _stopFirestoreStream();
    _firestoreStarted = false;
    _hasReceivedFirstSnapshot = false;

    // Evita UI “presa” em dados antigos após logout.
    _wsConversations = <ConversationItem>[];
    visibleUnreadCount.value = 0;
    notifyListeners();
  }

  void _stopFirestoreStream() {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
  }

  void _handleFirestoreStreamError(Object error) {
    final isPermissionDenied = error is FirebaseException && error.code == 'permission-denied';
    final isLoggedOut = FirebaseAuth.instance.currentUser == null;

    if (isPermissionDenied && isLoggedOut) {
      _log('⚠️ Firestore stream permission-denied após logout (ignorando)');
      _handleLoggedOut();
      return;
    }

    _log('❌ Firestore stream error: $error');
  }
  
  /// ✅ Processa snapshot do Firestore e atualiza a lista de conversas
  void _handleFirestoreSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _log('📥 [Firestore Stream] Snapshot recebido com ${snapshot.docs.length} documentos');
    _log('📥 [Firestore Stream] Metadata - hasPendingWrites: ${snapshot.metadata.hasPendingWrites}, isFromCache: ${snapshot.metadata.isFromCache}');
    
    // 🔥 Limpar cache para garantir dados em tempo real
    _cacheService.clearAll();
    _log('🗑️ Cache limpo para garantir dados em tempo real');
    
    final items = <ConversationItem>[];
    
    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        final otherUserId = (data[USER_ID] ?? doc.id).toString();
        final rawName = (data['activityText'] ?? data['fullName'] ?? data['other_user_name'] ?? data['otherUserName'] ?? '').toString();
        final name = _sanitizeText(rawName);
        final photo = _extractPhotoUrl(data);
        final rawLastMessage = (data[LAST_MESSAGE] ?? '').toString();
        final lastMessage = _sanitizeText(rawLastMessage);

        DateTime? ts;
        final rawTs = data[TIMESTAMP];
        if (rawTs is Timestamp) {
          ts = rawTs.toDate();
        } else if (rawTs is int) {
          ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
        }

        final unreadFlag = data[MESSAGE_READ];
        final isRead = unreadFlag == true || unreadFlag == 1;
        // ✅ FIX: Converter unread_count de forma segura (pode vir como num de FieldValue.increment)
        final rawUnreadCount = data['unread_count'];
        final unreadCount = (rawUnreadCount is num) 
            ? rawUnreadCount.toInt() 
            : (isRead ? 0 : 1);
        
        final isEventChat = data['is_event_chat'] == true;
        final eventId = data['event_id'] as String?;
        final emoji = data['emoji'] as String?;
        
        _log('   📄 Doc ${doc.id}: isEventChat=$isEventChat, eventId=$eventId, name=$name, emoji=$emoji');
        // DEBUG: Log detalhado para chats de evento
        if (isEventChat) {
          _log('   🔵 EVENT CHAT DEBUG: rawUnreadCount=$rawUnreadCount (${rawUnreadCount?.runtimeType}), unreadCount=$unreadCount, unreadFlag=$unreadFlag (${unreadFlag?.runtimeType}), isRead=$isRead');
        }

        items.add(ConversationItem(
          id: doc.id,
          userId: otherUserId,
          userFullname: name,
          userPhotoUrl: photo,
          lastMessage: lastMessage,
          lastMessageAt: ts,
          isRead: isRead,
          unreadCount: unreadCount,
          isEventChat: isEventChat,
          eventId: eventId,
          emoji: emoji,
        ));
      } catch (e) {
        _log('⚠️ Erro ao processar conversa ${doc.id}: $e');
      }
    }
    
    // 🚫 Filtrar conversas de usuários bloqueados
    final currentUserId = AppState.currentUserId;
    if (currentUserId != null) {
      final filteredItems = items.where((conv) {
        final isBlocked = BlockService().isBlockedCached(currentUserId, conv.userId);
        if (isBlocked) {
          _log('   🚫 Conversa ${conv.id} bloqueada (userId: ${conv.userId})');
        }
        return !isBlocked;
      }).toList();
      
      _log('📊 [Firestore Stream] Total: ${items.length}, Bloqueados: ${items.length - filteredItems.length}, Visíveis: ${filteredItems.length}');
      _log('📊 [Firestore Stream] Chats de evento: ${filteredItems.where((c) => c.isEventChat).length}');
      _log('📊 [Firestore Stream] Chats 1-1: ${filteredItems.where((c) => !c.isEventChat).length}');
      
      _wsConversations = filteredItems;
    } else {
      _log('⚠️ [Firestore Stream] currentUserId é null, não filtrando bloqueados');
      _wsConversations = items;
    }
    
    _hasReceivedFirstSnapshot = true;
    _updateVisibleUnreadCount();
    notifyListeners();
    
    _log('✅ Firestore stream processado: ${_wsConversations.length} conversas');
  }

  void _handleWsSnapshot(Map<String, dynamic> data) {
    final rawList = data['conversations'];
    if (rawList is! List) return;

    final items = <ConversationItem>[];
    for (final entry in rawList) {
      if (entry is Map<String, dynamic>) {
        try {
          items.add(ConversationItem.fromJson(entry));
        } catch (_) {
          // Ignora itens mal formatados
        }
      }
    }

    // 🚫 Filtrar conversas de usuários bloqueados
    final currentUserId = AppState.currentUserId;
    if (currentUserId != null) {
      _log('🔍 Filtrando ${items.length} conversas. CurrentUserId: $currentUserId');
      final blockedIds = BlockService().getAllBlockedIds(currentUserId);
      _log('🔍 IDs bloqueados: $blockedIds');
      
      final filteredItems = items.where((conv) {
        final isBlocked = BlockService().isBlockedCached(currentUserId, conv.userId);
        if (isBlocked) {
          _log('🚫 Conversa com ${conv.userId} (${conv.userFullname}) BLOQUEADA');
        }
        return !isBlocked;
      }).toList();
      
      _log('✅ ${items.length - filteredItems.length} conversas filtradas');
      _wsConversations = filteredItems;
    } else {
      _wsConversations = items;
    }
    
    _hasReceivedFirstSnapshot = true;
    notifyListeners();
  }

  void _handleWsUpdated(Map<String, dynamic> data) {
    final convMap = data['conversation'];
    if (convMap is! Map<String, dynamic>) return;

    ConversationItem item;
    try {
      item = ConversationItem.fromJson(convMap);
    } catch (_) {
      return;
    }

    final type = (data['type'] as String?) ?? 'upsert';
    final list = List<ConversationItem>.from(_wsConversations);
    final index = list.indexWhere((c) => c.id == item.id);

    if (type == 'delete') {
      if (index >= 0) {
        list.removeAt(index);
      }
    } else {
      if (index >= 0) {
        list[index] = item;
      } else {
        list.insert(0, item);
      }
    }

    // 🚫 Filtrar conversas de usuários bloqueados
    final currentUserId = AppState.currentUserId;
    final filteredList = currentUserId != null
        ? list.where((conv) => !BlockService().isBlockedCached(currentUserId, conv.userId)).toList()
        : list;

    _wsConversations = filteredList;
    _updateVisibleUnreadCount(); // Atualiza contador de não lidas visíveis
    notifyListeners();
  }

  /// Atualiza o contador de conversas não lidas VISÍVEIS
  /// Usa a mesma lógica da UI para consistência
  void _updateVisibleUnreadCount() {
    final visible = filteredWsConversations;
    final touchedIds = ConversationActivityBus.instance.touchedConversationIds.value;
    final unread = visible.where((c) {
      final isUnreadByFirestore = !c.isRead || c.unreadCount > 0;
      final isTouched = touchedIds.contains(c.id);
      return isUnreadByFirestore || isTouched;
    }).length;
    visibleUnreadCount.value = unread;
    _log('📊 Conversas não lidas visíveis: $unread de ${visible.length}');
  }

  /// Carrega conversas existentes diretamente do Firestore (uma vez),
  /// convertendo-as para ConversationItem para preencher a lista inicial.
  /// 
  /// ✅ Pode ser chamado externamente pelo AppInitializer para pré-carregar conversas
  /// ✅ Usa GlobalCache para carregamento instantâneo
  Future<void> preloadConversations() async {
    // 🔵 STEP 1: Tentar buscar do cache global primeiro
    final cached = _globalCache.get<List<ConversationItem>>(CacheKeys.conversations);
    
    if (cached != null && cached.isNotEmpty) {
      _log('🗂️ [Conversations] Cache HIT - ${cached.length} conversas');
      _wsConversations = cached;
      _updateVisibleUnreadCount();
      _hasReceivedFirstSnapshot = true;
      notifyListeners();
      
      // Atualização silenciosa em background
      _silentRefreshConversations();
      return;
    }
    
    _log('🗂️ [Conversations] Cache MISS - carregando do Firestore');
    await _loadInitialFromFirestore();
  }

  Future<void> _loadInitialFromFirestore() async {
    _log('📥 _loadInitialFromFirestore: INICIANDO');
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        _log('⚠️ _loadInitialFromFirestore: Usuário não autenticado');
        return;
      }
      
      _log('📥 _loadInitialFromFirestore: Buscando conversas do Firestore');
      final snapshot = await FirebaseFirestore.instance
          .collection('Connections')
          .doc(userId)
          .collection('Conversations')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();
      _log('📥 _loadInitialFromFirestore: Snapshot recebido com ${snapshot.docs.length} docs');
      final items = <ConversationItem>[];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final otherUserId = (data[USER_ID] ?? doc.id).toString();
          // ✅ FIX: Check activityText first (for event chats), then fullname variants
          final rawName = (data['activityText'] ?? data['fullName'] ?? data['other_user_name'] ?? data['otherUserName'] ?? '').toString();
          final name = _sanitizeText(rawName);
          // ✅ FIX: Extract photo with same logic as ConversationDataProcessor
          final photo = _extractPhotoUrl(data);
          final rawLastMessage = (data[LAST_MESSAGE] ?? '').toString();
          final lastMessage = _sanitizeText(rawLastMessage);

          DateTime? ts;
          final rawTs = data[TIMESTAMP];
          if (rawTs is Timestamp) {
            ts = rawTs.toDate();
          } else if (rawTs is int) {
            ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
          }

          final unreadFlag = data[MESSAGE_READ];
          final unreadCount = (data['unread_count'] as num?)?.toInt() ?? (data['unreadCount'] as num?)?.toInt() ?? 0;
          final isRead = (unreadFlag is bool)
              ? unreadFlag
              : unreadCount == 0;

          final isEventChat = data['is_event_chat'] == true;
          final eventId = data['event_id']?.toString();
          final emoji = data['emoji'] as String?;

          items.add(
            ConversationItem(
              id: doc.id,
              userId: otherUserId,
              userFullname: name.isNotEmpty ? name : 'Unknown',
              userPhotoUrl: photo,
              lastMessage: lastMessage,
              lastMessageType: data[MESSAGE_TYPE]?.toString(),
              lastMessageAt: ts,
              unreadCount: unreadCount,
              isRead: isRead,
              isEventChat: isEventChat,
              eventId: eventId,
              emoji: emoji,
            ),
          );
        } catch (e) {
          _log('⚠️ Erro ao processar conversa ${doc.id}: $e');
          // Continua para próxima conversa
        }
      }

      _log('📥 _loadInitialFromFirestore: Processados ${items.length} items');
      if (items.isNotEmpty && _wsConversations.isEmpty) {
        // 🚫 Filtrar conversas de usuários bloqueados
        final currentUserId = AppState.currentUserId;
        final filteredItems = currentUserId != null
            ? items.where((conv) => !BlockService().isBlockedCached(currentUserId, conv.userId)).toList()
            : items;
        
        _wsConversations = filteredItems;
        _updateVisibleUnreadCount(); // Atualiza contador
        _log('📥 _loadInitialFromFirestore: _wsConversations atualizado com ${filteredItems.length} items (${items.length - filteredItems.length} bloqueados removidos)');
        
        // 🔵 STEP 2: Salvar no cache global (TTL: 3 minutos)
        if (filteredItems.isNotEmpty) {
          _globalCache.set(
            CacheKeys.conversations,
            filteredItems,
            ttl: const Duration(minutes: 3),
          );
          _log('🗂️ [Conversations] Cache SAVED - ${filteredItems.length} conversas');
        }
      }
    } catch (e, stack) {
      _log('❌ _loadInitialFromFirestore: ERRO - $e');
      _log('❌ Stack: $stack');
    } finally {
      // Garante que o skeleton não fique travado em casos
      // onde não há conversas (lista vazia) ou em erro silencioso.
      if (!_hasReceivedFirstSnapshot) {
        _hasReceivedFirstSnapshot = true;
        _log('📥 _loadInitialFromFirestore: FINALIZANDO - _hasReceivedFirstSnapshot = true');
        notifyListeners();
      }
    }
  }

  /// Atualização silenciosa em background (não mostra loading)
  Future<void> _silentRefreshConversations() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      _log('🔄 [Conversations] Silent refresh iniciado');
      
      final snapshot = await FirebaseFirestore.instance
          .collection('Connections')
          .doc(userId)
          .collection('Conversations')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      final items = <ConversationItem>[];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final otherUserId = (data[USER_ID] ?? doc.id).toString();
          final rawName = (data['activityText'] ?? data['fullName'] ?? data['other_user_name'] ?? data['otherUserName'] ?? '').toString();
          final name = _sanitizeText(rawName);
          final photo = _extractPhotoUrl(data);
          final rawLastMessage = (data[LAST_MESSAGE] ?? '').toString();
          final lastMessage = _sanitizeText(rawLastMessage);

          DateTime? ts;
          final rawTs = data[TIMESTAMP];
          if (rawTs is Timestamp) {
            ts = rawTs.toDate();
          } else if (rawTs is int) {
            ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
          }

          final unreadFlag = data[MESSAGE_READ];
          final unreadCount = (data['unread_count'] as num?)?.toInt() ?? (data['unreadCount'] as num?)?.toInt() ?? 0;
          final isRead = (unreadFlag is bool) ? unreadFlag : unreadCount == 0;
          final isEventChat = data['is_event_chat'] == true;
          final eventId = data['event_id']?.toString();
          final emoji = data['emoji'] as String?;

          items.add(
            ConversationItem(
              id: doc.id,
              userId: otherUserId,
              userFullname: name.isNotEmpty ? name : 'Unknown',
              userPhotoUrl: photo,
              lastMessage: lastMessage,
              lastMessageType: data[MESSAGE_TYPE]?.toString(),
              lastMessageAt: ts,
              unreadCount: unreadCount,
              isRead: isRead,
              isEventChat: isEventChat,
              eventId: eventId,
              emoji: emoji,
            ),
          );
        } catch (_) {
          // Continua para próxima conversa
        }
      }

      // Filtrar bloqueados
      final currentUserId = AppState.currentUserId;
      final filteredItems = currentUserId != null
          ? items.where((conv) => !BlockService().isBlockedCached(currentUserId, conv.userId)).toList()
          : items;

      // Comparar com cache atual
      final hasChanges = filteredItems.length != _wsConversations.length ||
          (filteredItems.isNotEmpty && 
           _wsConversations.isNotEmpty && 
           (filteredItems.first.id != _wsConversations.first.id ||
            filteredItems.first.lastMessage != _wsConversations.first.lastMessage));

      if (hasChanges) {
        _log('🔄 [Conversations] Mudanças detectadas - atualizando');
        _wsConversations = filteredItems;
        _updateVisibleUnreadCount();
        
        // Atualizar cache
        _globalCache.set(
          CacheKeys.conversations,
          filteredItems,
          ttl: const Duration(minutes: 3),
        );
        
        notifyListeners();
      } else {
        _log('🔄 [Conversations] Nenhuma mudança detectada');
      }
    } catch (e) {
      _log('⚠️ [Conversations] Erro no silent refresh: $e');
      // Não exibe erro ao usuário
    }
  }
  /// Extract photo URL with fallback chain (same logic as ConversationDataProcessor)
  String _extractPhotoUrl(Map<String, dynamic> data) {
    final candidates = <dynamic>[
      data['photoUrl'],
    ];

    for (final candidate in candidates) {
      if (candidate is String) {
        final trimmed = candidate.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }
    return '';
  }

  /// Remove caracteres inválidos UTF-16 (emojis problemáticos)
  String _sanitizeText(String text) {
    if (text.isEmpty) return text;
    
    // Remove caracteres surrogates órfãos e outros problemas UTF-16
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      
      // High surrogate (0xD800-0xDBFF) deve ser seguido por low surrogate
      if (code >= 0xD800 && code <= 0xDBFF) {
        if (i + 1 < text.length) {
          final nextCode = text.codeUnitAt(i + 1);
          // Verifica se o próximo é low surrogate (0xDC00-0xDFFF)
          if (nextCode >= 0xDC00 && nextCode <= 0xDFFF) {
            buffer.write(text[i]);
            buffer.write(text[i + 1]);
            i++; // Pula o próximo
            continue;
          }
        }
        // High surrogate órfão - substitui por espaço
        buffer.write(' ');
      }
      // Low surrogate órfão (0xDC00-0xDFFF) - substitui por espaço
      else if (code >= 0xDC00 && code <= 0xDFFF) {
        buffer.write(' ');
      }
      // Caractere normal
      else {
        buffer.write(text[i]);
      }
    }
    
    return buffer.toString().trim();
  }

  /// Listen to pagination service changes
  void _onPaginationChanged() {
    _log('🟢 [ConversationsViewModel] _onPaginationChanged');
    notifyListeners();
  }

  /// Setup blocked users filtering
  void _initBlockedUsersFiltering() {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      _log('⚠️ Blocked users filtering não inicializado (usuário não autenticado)');
      return;
    }
    
    // ⬅️ ESCUTA BlockService via ChangeNotifier (REATIVO INSTANTÂNEO)
    BlockService.instance.addListener(_onBlockedUsersChanged);
    
    // Carrega IDs iniciais
    final initialBlockedIds = BlockService().getAllBlockedIds(currentUserId);
    _paginationService.updateBlockedIds(initialBlockedIds);
    _log('🚫 Blocked IDs iniciais: ${initialBlockedIds.length}');
  }
  
  /// Callback quando BlockService muda (via ChangeNotifier)
  void _onBlockedUsersChanged() {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) return;
    
    final blockedIds = BlockService().getAllBlockedIds(currentUserId);
    _paginationService.updateBlockedIds(blockedIds);
    _log('🚫 Blocked IDs atualizados via ChangeNotifier: ${blockedIds.length}');
    
    // 🔥 Re-filtrar conversas quando bloqueios mudam
    _refilterConversations();
  }
  
  /// Re-filtra conversas removendo usuários bloqueados
  /// Chamado automaticamente quando bloqueios mudam
  void _refilterConversations() {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) return;
    
    final beforeCount = _wsConversations.length;
    _log('🔍 Re-filtrando $beforeCount conversas após mudança de bloqueio');
    
    final blockedIds = BlockService().getAllBlockedIds(currentUserId);
    _log('🔍 IDs bloqueados: $blockedIds');
    
    _wsConversations = _wsConversations
        .where((conv) {
          final isBlocked = BlockService().isBlockedCached(currentUserId, conv.userId);
          if (isBlocked) {
            _log('🚫 Removendo conversa com ${conv.userId} (${conv.userFullname})');
          }
          return !isBlocked;
        })
        .toList();
    
    final afterCount = _wsConversations.length;
    final removedCount = beforeCount - afterCount;
    
    if (removedCount > 0) {
      _log('🚫 $removedCount conversas removidas (usuários bloqueados)');
      _updateVisibleUnreadCount();
      notifyListeners();
    } else {
      _log('ℹ️ Nenhuma conversa foi removida');
    }
  }

  /// Handle removal bus changes
  void _onRemovalBusChanged() {
    final ids = ConversationRemovalBus.instance.hiddenUserIds.value;
    if (ids.isEmpty) return;
    _paginationService.addOptimisticHiddenUserIds(ids);
  }

  /// Update search query
  void updateQuery(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      final normalized = q.trim();
      _searchQuery = normalized;
      _paginationService.updateQuery(normalized);
      _updateVisibleUnreadCount(); // Atualiza contador quando filtro muda
      notifyListeners();
    });
  }

  /// Apply first page from stream
  void applyFirstPage(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {int? limit}) {
    _log('🟡 [ConversationsViewModel] applyFirstPage - docs.length: ${docs.length}, limit: $limit');
    _paginationService.applyFirstPage(docs, limit: limit);
    _cacheService.clearAll();
  }

  /// Safe version for calling during build
  void applyFirstPageSafe(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {int? limit}) {
    _log('🟡 [ConversationsViewModel] applyFirstPageSafe - docs.length: ${docs.length}, limit: $limit');
    _paginationService.applyFirstPageSafe(docs, limit: limit);
  }

  /// Append next page results
  void appendPage(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _paginationService.appendPage(snapshot);
  }

  /// Reset pagination
  void resetPagination() {
    _paginationService.resetPagination();
    _cacheService.clearAll();
  }

  /// Load more pages
  Future<void> loadMore(Future<QuerySnapshot<Map<String, dynamic>>> Function({required DocumentSnapshot<Map<String, dynamic>> startAfter, int limit}) fetchPage) async {
    try {
      await _paginationService.loadMore(fetchPage);
    } catch (e) {
      rethrow;
    }
  }

  /// Get display data - delegates to cache service
  Future<ConversationDisplayData> getDisplayData({
    required String conversationId,
    required Map<String, dynamic> data,
    required bool isVipEffective,
    required AppLocalizations i18n,
  }) {
    return _cacheService.getDisplayData(
      conversationId: conversationId,
      data: data,
      isVipEffective: isVipEffective,
      i18n: i18n,
    );
  }

  /// Get display data future - delegates to cache service
  Future<ConversationDisplayData> getDisplayDataFuture({
    required String conversationId,
    required Map<String, dynamic> data,
    required bool isVipEffective,
    required AppLocalizations i18n,
  }) {
    return _cacheService.getDisplayDataFuture(
      conversationId: conversationId,
      data: data,
      isVipEffective: isVipEffective,
      i18n: i18n,
    );
  }

  /// Get display data notifier - delegates to cache service
  ValueNotifier<ConversationDisplayData> getDisplayDataNotifier({
    required String conversationId,
    required Map<String, dynamic> data,
    required bool isVipEffective,
    required AppLocalizations i18n,
  }) {
    return _cacheService.getDisplayDataNotifier(
      conversationId: conversationId,
      data: data,
      isVipEffective: isVipEffective,
      i18n: i18n,
    );
  }

  /// Optimistically remove conversation by userId
  void optimisticRemoveByUserId(String userId) {
    _paginationService.optimisticRemoveByUserId(userId);
  }

  /// Optimistically mark conversation as read
  void markAsRead(String conversationId) {
    final index = _wsConversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final old = _wsConversations[index];
      if (!old.isRead || old.unreadCount > 0) {
        _wsConversations[index] = old.copyWith(
          isRead: true,
          unreadCount: 0,
        );
        _updateVisibleUnreadCount();
        notifyListeners();
      }
    }
  }

  /// Set processing payment state
  void setIsProcessingPayment(bool v) {
    _isProcessingPayment = v;
    notifyListeners();
  }

  /// Set refreshing state
  void setIsRefreshing(bool v) {
    _isRefreshing = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _authSubscription?.cancel();
    _firestoreSubscription?.cancel(); // ✅ Cancelar stream do Firestore
    BlockService.instance.removeListener(_onBlockedUsersChanged);
    if (_activityBusListener != null) {
      ConversationActivityBus.instance.touchedConversationIds.removeListener(_activityBusListener!);
      _activityBusListener = null;
    }
    _paginationService.removeListener(_onPaginationChanged);
    _paginationService.dispose();
    _cacheService.dispose();
    _scrollController.dispose();
    ConversationRemovalBus.instance.hiddenUserIds.removeListener(_onRemovalBusChanged);
    _socket.off('conversations:snapshot');
    _socket.off('conversations:updated');
    _socket.off('conversations:unread_count');
    super.dispose();
  }
}
