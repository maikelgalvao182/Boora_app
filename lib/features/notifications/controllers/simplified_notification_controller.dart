import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/features/notifications/models/notification_cache_item.dart';
import 'package:partiu/features/notifications/services/notification_persistent_cache_repository.dart';
import 'package:flutter/material.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/services/global_cache_service.dart';
import 'package:partiu/shared/stores/user_store.dart';

/// Controlador de notificações simples inspirado no padrão Chatter.
/// - Lista única por filtro (source of truth)
/// - Paginação por lastDocument
/// - ValueNotifiers granular por filtro
/// - Cache global com TTL para performance
/// - SEM dependências de i18n (labels são responsabilidade da View)
class SimplifiedNotificationController extends ChangeNotifier {
  
  /// Singleton Instance
  static final SimplifiedNotificationController instance = SimplifiedNotificationController(
    repository: NotificationsRepository(),
  );

  SimplifiedNotificationController({
    required INotificationsRepository repository,
  }) : _repository = repository;
  final INotificationsRepository _repository;
  final GlobalCacheService _cache = GlobalCacheService.instance;
  final NotificationPersistentCacheRepository _persistentCache =
      NotificationPersistentCacheRepository();

  // Cache por filtro (mantido em memória durante sessão)
  final Map<String?, List<NotificationCacheItem>> _notificationsByFilter = {};
  final Map<String?, DocumentSnapshot<Map<String, dynamic>>?> _lastDocumentByFilter = {};
  final Map<String?, bool> _hasMoreByFilter = {};
  final Map<String?, bool> _isFirstLoadByFilter = {};
  
  // 🆕 Set de IDs de notificações marcadas como lidas localmente
  final Set<String> _locallyReadNotifications = {};

  // Notificadores específicos por filtro
  final Map<String?, ValueNotifier<int>> _filterUpdateNotifiers = {};

  // Notificador específico para o índice do filtro selecionado
  final ValueNotifier<int> _selectedFilterIndexNotifier = ValueNotifier<int>(0);

  // Estado global
  static const int _pageSize = 20;
  static const int _maxLocallyReadCacheSize = 100; // Limite para evitar memory leak
  bool _isLoading = false;

  // Estado de UI
  String? _selectedFilterKey;
  int _selectedFilterIndex = 0;
  String? _errorMessage;

  // Gerenciamento de ScrollControllers por filtro
  final Map<int, ScrollController> _scrollControllers = {};
  final Map<int, bool> _isLoadingMore = {};

  // Estado de VIP (cache)
  bool _isVipEffective = false;

  // Getters do filtro atual
  List<NotificationCacheItem> get notifications =>
      _notificationsByFilter[_selectedFilterKey] ?? [];

  bool get hasMore => _hasMoreByFilter[_selectedFilterKey] ?? true;

  // Getters públicos
  bool get isLoading => _isLoading;
  bool get isFirstLoad => _isFirstLoadByFilter[_selectedFilterKey] ?? true;
  String? get errorMessage => _errorMessage;
  String? get selectedFilterKey => _selectedFilterKey;
  int get selectedFilterIndex => _selectedFilterIndex;
  ValueNotifier<int> get selectedFilterIndexNotifier => _selectedFilterIndexNotifier;
  bool get isVipEffective => _isVipEffective;
  
  // 🆕 Verifica se uma notificação foi marcada como lida localmente
  bool isNotificationLocallyRead(String notificationId) => 
      _locallyReadNotifications.contains(notificationId);
  
  // 🆕 Alias para compatibilidade com UI
  bool isNotificationRead(String notificationId) => 
      _locallyReadNotifications.contains(notificationId);
  
  // 🚀 Getters para paginação com InfiniteListView
  bool get isLoadingMore => _isLoadingMore[_selectedFilterIndex] ?? false;
  bool get exhausted => !hasMore;

  // Atualiza status VIP
  void updateVipStatus(bool isVip) {
    _isVipEffective = isVip;
  }

  // Retorna ou cria ScrollController para um filtro específico
  ScrollController getScrollController(int filterIndex) {
    if (!_scrollControllers.containsKey(filterIndex)) {
      final controller = ScrollController();
      controller.addListener(() => _onScrollUpdate(filterIndex));
      _scrollControllers[filterIndex] = controller;
      _isLoadingMore[filterIndex] = false;
    }
    return _scrollControllers[filterIndex]!;
  }

  // 🚀 Método público para loadMore (usado pelo InfiniteListView)
  Future<void> loadMore() async {
    final key = _selectedFilterKey;
    final filterIndex = _selectedFilterIndex;
    
    if (_isLoadingMore[filterIndex] ?? false) return;
    if (!hasMoreForFilter(key)) return;
    if (_isLoading) return;
    
    _isLoadingMore[filterIndex] = true;
    notifyListeners();
    
    await fetchNotifications(filterKey: key);
    
    _isLoadingMore[filterIndex] = false;
    notifyListeners();
  }
  
  // Detecta quando chegou perto do fim e carrega mais (DEPRECATED - InfiniteListView faz isso agora)
  void _onScrollUpdate(int filterIndex) {
    final key = mapFilterIndexToKey(filterIndex);
    if (_isLoadingMore[filterIndex] ?? false) return;
    if (!hasMoreForFilter(key)) return;
    if (_isLoading) return;

    final scrollController = _scrollControllers[filterIndex];
    if (scrollController == null) return;

    // Verifica se está perto do fim (80%)
    if (scrollController.position.pixels >= scrollController.position.maxScrollExtent * 0.8) {
      _isLoadingMore[filterIndex] = true;
      fetchNotifications(filterKey: key).then((_) {
        _isLoadingMore[filterIndex] = false;
      });
    }
  }

  // ---- NOTIFIERS POR FILTRO ----
  ValueNotifier<int> getFilterNotifier(String? filterKey) {
    return _filterUpdateNotifiers.putIfAbsent(
      filterKey,
      () => ValueNotifier<int>(0),
    );
  }

  List<NotificationCacheItem> getNotificationsForFilter(String? filterKey) {
    return _notificationsByFilter[filterKey] ?? [];
  }

  bool hasMoreForFilter(String? filterKey) {
    return _hasMoreByFilter[filterKey] ?? true;
  }

  bool isFirstLoadForFilter(String? filterKey) {
    return _isFirstLoadByFilter[filterKey] ?? true;
  }

  // Mapeamento público para a View usar
  // Cada índice corresponde a um tipo de notificação ou grupo
  // IMPORTANTE: Apenas categorias com triggers IMPLEMENTADOS
  // NOTA: Chat (1x1 e grupo) usa apenas push notifications, não salva in-app
  String? mapFilterIndexToKey(int index) {
    switch (index) {
      case 0: return null; // Todas
      case 1: return 'activity'; // Atividades (todos os tipos activity_*)
      case 2: return 'profile_views_aggregated'; // Visualizações de Perfil
      case 3: return 'reviews'; // Avaliações
      case 4: return 'new_follower'; // Novos seguidores
      default: return null;
    }
  }

  // Keys de tradução para filtros (a View deve traduzir)
  // Correspondem exatamente aos triggers implementados
  // NOTA: Chat (1x1 e grupo) usa apenas push notifications, não aparece aqui
  static const List<String> filterLabelKeys = [
    'notif_filter_all',
    'notif_filter_activities',
    'notif_filter_profile_views',
    'notif_filter_reviews',
    'notif_filter_followers',
  ];

  /// Inicializa o controller com status VIP e carrega dados iniciais
  Future<void> initialize(bool isVip) async {
    updateVipStatus(isVip);
    
    // Se já temos dados carregados, fazemos apenas um refresh silencioso
    // Isso evita o "piscar" do loading e usa o estado mantido em memória (Singleton)
    if (_notificationsByFilter[_selectedFilterKey]?.isNotEmpty ?? false) {
      _silentRefresh(_selectedFilterKey);
      return;
    }

    _selectedFilterIndex = 0;
    _selectedFilterKey = mapFilterIndexToKey(0);
    await fetchNotifications(shouldRefresh: true, filterKey: _selectedFilterKey);
  }

  // ---------------------------------------------------------------------------
  // FETCH DE NOTIFICAÇÕES COM CACHE GLOBAL
  // ---------------------------------------------------------------------------
  Future<void> fetchNotifications({
    bool shouldRefresh = false,
    String? filterKey,
  }) async {
    final key = filterKey ?? _selectedFilterKey;
    
    if (_isLoading) return;
    
    // 🧊 STEP 0: Cache persistente (Hive) para cold start
    if (!shouldRefresh) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        final persisted = await _persistentCache.getCached(userId, key);
        if (persisted != null && persisted.isNotEmpty) {
          print('🧊 [NotificationController] Hive cache HIT para filtro: $key');
          _notificationsByFilter[key] = persisted;
          _isFirstLoadByFilter[key] = false;
          _notifyFilterUpdate(key);
          notifyListeners();

          // Atualização silenciosa em background
          _silentRefresh(key);
          return;
        }
      }

      // 🔵 STEP 1: Tentar buscar do cache global primeiro
      final cacheKey = CacheKeys.notificationsFilter(key);
      final cached = _cache.get<List<NotificationCacheItem>>(cacheKey);
      
      if (cached != null && cached.isNotEmpty) {
        print('🗂️ [NotificationController] Cache HIT para filtro: $key');
        _notificationsByFilter[key] = cached;
        _isFirstLoadByFilter[key] = false;
        _notifyFilterUpdate(key);
        notifyListeners();
        
        // Atualização silenciosa em background
        _silentRefresh(key);
        return;
      }
      print('🗂️ [NotificationController] Cache MISS para filtro: $key');
    }
    
    // Verifica hasMore específico do filtro
    final hasMore = _hasMoreByFilter[key] ?? true;
    if (!hasMore && !shouldRefresh) return;

    _isLoading = true;
    _errorMessage = null;

    _notifyFilterUpdate(key);

    if (!shouldRefresh) {
      notifyListeners();
    }

    try {
      if (shouldRefresh) {
        _lastDocumentByFilter[key] = null;
        _hasMoreByFilter[key] = true;
      }

      final result = await _repository.getNotificationsPaginated(
        lastDocument: _lastDocumentByFilter[key],
        filterKey: key,
      );

      // 🚫 Filtrar notificações de usuários bloqueados
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final filteredDocs = currentUserId != null
          ? result.docs.where((doc) {
              final senderId = doc.data()?['n_sender_id'] as String?;
              if (senderId == null || senderId.isEmpty) return true;
              return !BlockService().isBlockedCached(currentUserId, senderId);
            }).toList()
          : result.docs;

      final newItems = filteredDocs.map(NotificationCacheItem.fromDocument).toList();

      if (shouldRefresh) {
        _notificationsByFilter[key] = newItems;
      } else {
        _notificationsByFilter[key] = [
          ...(_notificationsByFilter[key] ?? []),
          ...newItems,
        ];
      }
      
      // ✅ PRELOAD: Carregar avatares dos remetentes antes da UI renderizar
      for (final doc in filteredDocs) {
        final data = doc.data();
        if (data == null) continue;
        final senderId = data['n_sender_id'] as String?;
        final senderPhotoUrl = data['n_sender_photo_url'] as String?;
        if (senderId != null && senderId.isNotEmpty && 
            senderPhotoUrl != null && senderPhotoUrl.isNotEmpty) {
          UserStore.instance.preloadAvatar(senderId, senderPhotoUrl);
        }
      }

      if (filteredDocs.isNotEmpty) {
        _lastDocumentByFilter[key] = filteredDocs.last;
      }

      _hasMoreByFilter[key] = result.docs.length >= _pageSize;

      // Marca como carregado para este filtro específico
      if (_isFirstLoadByFilter[key] ?? true) {
        _isFirstLoadByFilter[key] = false;
      }

      // 🔵 STEP 2: Salvar no cache global (TTL: 5 minutos)
      if (_notificationsByFilter[key]?.isNotEmpty ?? false) {
        final cacheKey = CacheKeys.notificationsFilter(key);
        _cache.set(
          cacheKey,
          _notificationsByFilter[key]!,
          ttl: const Duration(minutes: 5),
        );

        final userId = FirebaseAuth.instance.currentUser?.uid;
        if (userId != null) {
          await _persistentCache.cacheNotifications(
            userId,
            key,
            _notificationsByFilter[key]!,
          );
        }
        print('🗂️ [NotificationController] Cache SAVED para filtro: $key');
      }

      _notifyFilterUpdate(key);
    } catch (e) {
      _errorMessage = e.toString();
      _notifyFilterUpdate(key);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Atualização silenciosa em background (não mostra loading)
  Future<void> _silentRefresh(String? filterKey) async {
    final key = filterKey ?? _selectedFilterKey;
    
    try {
      print('🔄 [NotificationController] Silent refresh para filtro: $key');
      
      final result = await _repository.getNotificationsPaginated(
        lastDocument: null, // Sempre busca do início
        filterKey: key,
      );

      // Filtrar bloqueados
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final filteredDocs = currentUserId != null
          ? result.docs.where((doc) {
              final senderId = doc.data()?['n_sender_id'] as String?;
              if (senderId == null || senderId.isEmpty) return true;
              return !BlockService().isBlockedCached(currentUserId, senderId);
            }).toList()
          : result.docs;

        // Comparar com cache atual
        final currentList = _notificationsByFilter[key] ?? [];
        final newItems = filteredDocs.map(NotificationCacheItem.fromDocument).toList();
        final hasChanges = newItems.length != currentList.length ||
          (newItems.isNotEmpty && 
           currentList.isNotEmpty && 
           newItems.first.id != currentList.first.id);

      if (hasChanges) {
        print('🔄 [NotificationController] Dados atualizados detectados');
        _notificationsByFilter[key] = newItems;
        
        // 🧹 Limpar Set de lidos localmente - os dados do servidor já têm o estado correto
        _locallyReadNotifications.clear();
        
        if (filteredDocs.isNotEmpty) {
          _lastDocumentByFilter[key] = filteredDocs.last;
        }

        // Atualizar cache
        final cacheKey = CacheKeys.notificationsFilter(key);
        _cache.set(
          cacheKey,
          _notificationsByFilter[key]!,
          ttl: const Duration(minutes: 5),
        );

        if (currentUserId != null) {
          await _persistentCache.cacheNotifications(
            currentUserId,
            key,
            _notificationsByFilter[key]!,
          );
        }

        _notifyFilterUpdate(key);
        notifyListeners();
      } else {
        print('🔄 [NotificationController] Nenhuma mudança detectada');
      }
    } catch (e) {
      print('⚠️ [NotificationController] Erro no silent refresh: $e');
      // Não exibe erro ao usuário - silent refresh falhou mas UI continua ok
    }
  }

  // ---------------------------------------------------------------------------
  // FILTROS
  // ---------------------------------------------------------------------------
  Future<void> setFilter(int index) async {
    _selectedFilterIndex = index;
    _selectedFilterIndexNotifier.value = index;
    final key = mapFilterIndexToKey(index);
    _selectedFilterKey = key;

    // Verifica se já temos dados para o filtro alvo
    final hasData = _notificationsByFilter[key]?.isNotEmpty ?? false;
    final isFirstLoad = _isFirstLoadByFilter[key] ?? true;

    if ((!hasData || isFirstLoad) && !_isLoading) {
      await fetchNotifications(shouldRefresh: true, filterKey: key);
      return;
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------------
  Future<void> deleteAllNotifications() async {
    try {
      _isLoading = true;
      notifyListeners();

      await _repository.deleteUserNotifications();

      _notificationsByFilter.clear();
      _lastDocumentByFilter.clear();
      _hasMoreByFilter.clear();
      _isFirstLoadByFilter.clear();

      // 🔵 Limpar todo o cache de notificações
      for (int i = 0; i < 4; i++) {
        final key = mapFilterIndexToKey(i);
        final cacheKey = CacheKeys.notificationsFilter(key);
        _cache.remove(cacheKey);
      }
      print('🗂️ [NotificationController] Cache limpo após delete all');

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        for (int i = 0; i < 4; i++) {
          final key = mapFilterIndexToKey(i);
          await _persistentCache.clearFilter(userId, key);
        }
      }

      for (final notifier in _filterUpdateNotifiers.values) {
        notifier.value++;
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    try {
      await _repository.deleteNotification(notificationId);

      final list = _notificationsByFilter[_selectedFilterKey];
      if (list != null) {
        list.removeWhere((doc) => doc.id == notificationId);
        _notificationsByFilter[_selectedFilterKey] = list;
        
        // 🔵 Atualizar cache após remoção individual
        if (list.isNotEmpty) {
          final cacheKey = CacheKeys.notificationsFilter(_selectedFilterKey);
          _cache.set(
            cacheKey,
            list,
            ttl: const Duration(minutes: 5),
          );
          final userId = FirebaseAuth.instance.currentUser?.uid;
          if (userId != null) {
            await _persistentCache.cacheNotifications(
              userId,
              _selectedFilterKey,
              list,
            );
          }
        }
      }

      _notifyFilterUpdate(_selectedFilterKey);
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // READ - Optimistic UI Pattern com Rollback
  // ---------------------------------------------------------------------------
  Future<void> markAsRead(String notificationId) async {
    // 🚀 Optimistic UI: Atualiza UI imediatamente
    _locallyReadNotifications.add(notificationId);
    
    // Limitar tamanho do Set para evitar memory leak
    if (_locallyReadNotifications.length > _maxLocallyReadCacheSize) {
      // Remove os primeiros itens (mais antigos)
      final toRemove = _locallyReadNotifications.take(
        _locallyReadNotifications.length - _maxLocallyReadCacheSize,
      ).toList();
      _locallyReadNotifications.removeAll(toRemove);
    }
    
    // Notifica UI para rebuild imediato
    _notifyFilterUpdate(_selectedFilterKey);
    _notifyFilterUpdate(null); // Também notifica "all"
    notifyListeners();
    
    try {
      // Persiste no Firestore
      await _repository.readNotification(notificationId);
    } catch (e) {
      // ⚠️ Rollback: Se falhar, reverte o estado local
      _locallyReadNotifications.remove(notificationId);
      _notifyFilterUpdate(_selectedFilterKey);
      _notifyFilterUpdate(null);
      notifyListeners();
      debugPrint('⚠️ [NotificationController] Rollback markAsRead: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // NOTIFIER INTERNO
  // ---------------------------------------------------------------------------
  void _notifyFilterUpdate(String? filterKey) {
    final notifier = _filterUpdateNotifiers.putIfAbsent(
      filterKey,
      () => ValueNotifier<int>(0),
    );
    notifier.value++;
  }

  @override
  void dispose() {
    _selectedFilterIndexNotifier.dispose();
    for (final notifier in _filterUpdateNotifiers.values) {
      notifier.dispose();
    }
    _filterUpdateNotifiers.clear();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    _scrollControllers.clear();
    super.dispose();
  }
}
