import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:flutter/material.dart';

/// Controlador de notificações simples inspirado no padrão Chatter.
/// - Lista única por filtro (source of truth)
/// - Paginação por lastDocument
/// - ValueNotifiers granular por filtro
/// - SEM dependências de i18n (labels são responsabilidade da View)
class SimplifiedNotificationController extends ChangeNotifier {

  SimplifiedNotificationController({
    required INotificationsRepository repository,
  }) : _repository = repository;
  final INotificationsRepository _repository;

  // Cache por filtro
  final Map<String?, List<DocumentSnapshot<Map<String, dynamic>>>> _notificationsByFilter = {};
  final Map<String?, DocumentSnapshot<Map<String, dynamic>>?> _lastDocumentByFilter = {};
  final Map<String?, bool> _hasMoreByFilter = {};
  final Map<String?, bool> _isFirstLoadByFilter = {};

  // Notificadores específicos por filtro
  final Map<String?, ValueNotifier<int>> _filterUpdateNotifiers = {};

  // Notificador específico para o índice do filtro selecionado
  final ValueNotifier<int> _selectedFilterIndexNotifier = ValueNotifier<int>(0);

  // Estado global
  static const int _pageSize = 20;
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
  List<DocumentSnapshot<Map<String, dynamic>>> get notifications =>
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

  // Detecta quando chegou perto do fim e carrega mais
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

  List<DocumentSnapshot<Map<String, dynamic>>> getNotificationsForFilter(String? filterKey) {
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
  String? mapFilterIndexToKey(int index) {
    switch (index) {
      case 0: return null; // All
      case 1: return 'message'; // Messages
      case 2: return 'activity'; // Activities (todos os tipos activity_*)
      case 3: return 'activity_join_request'; // Requests
      case 4: return 'profile_views_aggregated'; // Social
      case 5: return 'alert'; // System
      default: return null;
    }
  }

  // Keys de tradução para filtros (a View deve traduzir)
  static const List<String> filterLabelKeys = [
    'notif_filter_all',
    'notif_filter_messages',
    'notif_filter_activities',
    'notif_filter_requests',
    'notif_filter_social',
    'notif_filter_system',
  ];

  /// Inicializa o controller com status VIP e carrega dados iniciais
  Future<void> initialize(bool isVip) async {
    updateVipStatus(isVip);
    _selectedFilterIndex = 0;
    _selectedFilterKey = mapFilterIndexToKey(0);
    await fetchNotifications(shouldRefresh: true, filterKey: _selectedFilterKey);
  }

  // ---------------------------------------------------------------------------
  // FETCH DE NOTIFICAÇÕES
  // ---------------------------------------------------------------------------
  Future<void> fetchNotifications({
    bool shouldRefresh = false,
    String? filterKey,
  }) async {
    final key = filterKey ?? _selectedFilterKey;
    
    if (_isLoading) return;
    
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

      if (shouldRefresh) {
        _notificationsByFilter[key] = result.docs;
      } else {
        _notificationsByFilter[key] = [
          ...(_notificationsByFilter[key] ?? []),
          ...result.docs,
        ];
      }

      if (result.docs.isNotEmpty) {
        _lastDocumentByFilter[key] = result.docs.last;
      }

      _hasMoreByFilter[key] = result.docs.length >= _pageSize;

      // Marca como carregado para este filtro específico
      if (_isFirstLoadByFilter[key] ?? true) {
        _isFirstLoadByFilter[key] = false;
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
      }

      _notifyFilterUpdate(_selectedFilterKey);
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------------
  Future<void> markAsRead(String notificationId) async {
    try {
      await _repository.readNotification(notificationId);
    } catch (_) {
      // silencioso
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
