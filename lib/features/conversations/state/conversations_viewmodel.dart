import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/conversations/models/conversation_item.dart';
import 'package:partiu/features/conversations/services/conversation_cache_service.dart';
import 'package:partiu/features/conversations/services/conversation_data_processor.dart';
import 'package:partiu/features/conversations/services/conversation_navigation_service.dart';
import 'package:partiu/features/conversations/services/conversation_pagination_service.dart';
import 'package:partiu/features/conversations/services/conversation_state_service.dart';
import 'package:partiu/features/conversations/state/optimistic_removal_bus.dart';
import 'package:partiu/core/services/auth_state_service.dart';
import 'package:partiu/core/services/blocked_users_filter_service.dart';
import 'package:partiu/core/services/socket_service.dart';
import 'package:partiu/core/services/subscription_monitoring_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// ViewModel responsável por coordenar conversas
/// Usa services dedicados para cache e paginação, mantendo apenas coordenação e estado global
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
  
  // WebSocket-backed state (ainda não usado na UI)
  List<ConversationItem> _wsConversations = <ConversationItem>[];
  String _searchQuery = '';
  int _wsUnreadCount = 0;
  
  // UI state
  bool _isProcessingPayment = false;
  bool _isRefreshing = false;
  bool _initialized = false;
  bool _hasReceivedFirstSnapshot = false;
  final ScrollController _scrollController = ScrollController();
  
  // Blocked users integration
  StreamSubscription<Set<String>>? _blockedSub;
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
      print('🔍 [ConversationsVM] $msg');
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
    _initWebSocketListeners();
    
    // Listen to global removal bus for instant UI updates
    ConversationRemovalBus.instance.hiddenUserIds.addListener(_onRemovalBusChanged);
    _log('🟢 [ConversationsViewModel] _initialize concluído');
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

        // Carrega a primeira página das conversas antigas via Firestore
        // para evitar skeleton fixo enquanto o WebSocket não responde.
        await _loadInitialFromFirestore();

        _socket.subscribeToConversations();
        _socket.onConversationsSnapshot(_handleWsSnapshot);
        _socket.onConversationsUpdated(_handleWsUpdated);
        _socket.onConversationsUnreadCount((unreadCount) {
          _wsUnreadCount = unreadCount;
          notifyListeners();
        });
      } catch (_) {
        // Falhas de WebSocket não devem afetar a UI atual baseada em Firestore
      }
    });
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

    _wsConversations = items;
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

    _wsConversations = list;
    notifyListeners();
  }

  /// Carrega conversas existentes diretamente do Firestore (uma vez),
  /// convertendo-as para ConversationItem para preencher a lista inicial.
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
          final rawName = (data[fullname] ?? data['other_user_name'] ?? data['otherUserName'] ?? '').toString();
          final name = _sanitizeText(rawName);
          final photo = (data[USER_PROFILE_PHOTO] ?? data['other_user_photo'] ?? data['otherUserPhoto']) as String?;
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
            ),
          );
        } catch (e) {
          _log('⚠️ Erro ao processar conversa ${doc.id}: $e');
          // Continua para próxima conversa
        }
      }

      _log('📥 _loadInitialFromFirestore: Processados ${items.length} items');
      if (items.isNotEmpty && _wsConversations.isEmpty) {
        _wsConversations = items;
        _log('📥 _loadInitialFromFirestore: _wsConversations atualizado com ${items.length} items');
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
    _blockedSub = BlockedUsersFilterService().blockedIdsStream.listen((blockedIds) {
      _paginationService.updateBlockedIds(blockedIds);
    });
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
    _blockedSub?.cancel();
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
