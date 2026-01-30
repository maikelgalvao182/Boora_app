import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:partiu/screens/chat/services/chat_analytics_service.dart';

/// Service responsável por gerenciar paginação de conversas
/// Controla docs, filtragem, estado de loading e paginação
class ConversationPaginationService extends ChangeNotifier {
  // Aggregated docs across pages (first page from stream, next via fetch)
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtered = const [];

  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _pageSize = 20;
  DocumentSnapshot<Map<String, dynamic>>? _lastVisible;
  
  // ✅ INSTRUMENTAÇÃO: Analytics service
  final ChatAnalyticsService _analytics = ChatAnalyticsService.instance;

  // Doc cache from last update
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _lastDocs;

  // Blocked users to filter out
  Set<String> _blockedIds = {};

  // Optimistic UI: hide conversations for these userIds immediately
  final Set<String> _optimisticHiddenUserIds = {};

  // Current search query
  String _query = '';

  // Getters
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get filteredDocs =>
      _filtered;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  int get pageSize => _pageSize;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? get lastDocs => _lastDocs;
  Set<String> get blockedIds => _blockedIds;
  String get query => _query;
  bool get hasQuery => _query.isNotEmpty;

  /// Update blocked user IDs
  void updateBlockedIds(Set<String> blockedIds) {
    _blockedIds = blockedIds;
    _recompute();
  }

  /// Update search query
  void updateQuery(String q) {
    final nq = q.trim().toLowerCase();
    if (nq == _query) return;
    _query = nq;
    _recompute();
  }

  /// Optimistically remove conversation by userId
  void optimisticRemoveByUserId(String userId) {
    if (userId.isEmpty) return;
    _optimisticHiddenUserIds.add(userId);
    _recompute();
  }

  /// Add hidden user IDs from external source
  void addOptimisticHiddenUserIds(Set<String> userIds) {
    if (userIds.isEmpty) return;
    _optimisticHiddenUserIds.addAll(userIds);
    _recompute();
  }

  /// Replace current docs with first page (usually from live stream)
  void applyFirstPage(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      {int? limit}) {
    // Apply optimistic hidden filter immediately
    final filteredDocs = _applyOptimisticFilter(docs);

    _docs
      ..clear()
      ..addAll(filteredDocs);
    _pageSize = limit ?? _pageSize;
    _hasMore = docs.length >= _pageSize;
    _lastVisible = docs.isNotEmpty ? docs.last : null;
    if (_docs.isNotEmpty) {
      _lastDocs =
          List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(_docs);
    }
    _recompute();
  }

  /// Safe version for calling during build - uses postFrameCallback
  void applyFirstPageSafe(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      {int? limit}) {
    // Check if docs structure changed (different IDs or count)
    final structureChanged = _lastDocs == null ||
        _lastDocs!.length != docs.length ||
        docs.isEmpty ||
        _lastDocs!.isEmpty ||
        _lastDocs!.first.id != docs.first.id ||
        _lastDocs!.last.id != docs.last.id;

    if (!structureChanged) {
      // Structure didn't change, skip recompute to avoid rebuild loops
      return;
    }

    // Structure changed: clear and rebuild
    final filteredDocs = _applyOptimisticFilter(docs);

    _docs
      ..clear()
      ..addAll(filteredDocs);
    _pageSize = limit ?? _pageSize;
    _hasMore = docs.length >= _pageSize;
    _lastVisible = docs.isNotEmpty ? docs.last : null;
    if (_docs.isNotEmpty) {
      _lastDocs =
          List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(_docs);
    }

    // Use postFrameCallback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recompute();
    });
  }

  /// Append next page results
  void appendPage(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.docs.isEmpty) {
      _hasMore = false;
      notifyListeners();
      return;
    }
    _docs.addAll(snapshot.docs);
    _lastVisible = snapshot.docs.last;
    _hasMore = snapshot.docs.length >= _pageSize;
    _recompute();
  }

  /// Reset pagination
  void resetPagination() {
    _docs.clear();
    _filtered = const [];
    _lastVisible = null;
    _hasMore = true;
    _isLoadingMore = false;
    // Keep optimistic hidden set; it's user intent
    notifyListeners();
  }

  /// Load more pages
  Future<void> loadMore(
      Future<QuerySnapshot<Map<String, dynamic>>> Function(
              {required DocumentSnapshot<Map<String, dynamic>> startAfter,
              int limit})
          fetchPage) async {
    if (_isLoadingMore || !_hasMore || _lastVisible == null) {
      return;
    }

    _isLoadingMore = true;
    notifyListeners();
    
    // ✅ INSTRUMENTAÇÃO: Medir tempo de paginação
    final stopwatch = Stopwatch()..start();
    
    try {
      final snapshot =
          await fetchPage(startAfter: _lastVisible!, limit: _pageSize);
      
      stopwatch.stop();
      
      // 📊 Log de paginação
      _analytics.logPaginationLoad(
        chatId: 'conversations_list',
        pageSize: _pageSize,
        docsLoaded: snapshot.docs.length,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      
      appendPage(snapshot);
    } catch (e) {
      stopwatch.stop();
      // Ignore load more errors
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Apply optimistic filter to remove hidden users
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyOptimisticFilter(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_optimisticHiddenUserIds.isEmpty) return docs;

    return docs.where((d) {
      final m = d.data();
      final otherUserId = (m['user_id'] ??
              m['other_user_id'] ??
              m['otherUserId'] ??
              '')
          .toString();
      return otherUserId.isEmpty ||
          !_optimisticHiddenUserIds.contains(otherUserId);
    }).toList();
  }

  /// Recompute filtered list based on query and blocked users
  void _recompute() {
    var result =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(_docs);

    // Apply blocked users filter
    if (_blockedIds.isNotEmpty) {
      result = result.where((d) {
        final otherUserId = (d.data()['user_id'] ?? '').toString();
        return otherUserId.isEmpty || !_blockedIds.contains(otherUserId);
      }).toList();
    }

    // Apply search query filter
    if (_query.isNotEmpty) {
      result = result.where((d) {
        final data = d.data();
        final fullName = (data['fullname'] ?? '').toString().toLowerCase();
        return fullName.contains(_query);
      }).toList();
    }

    _filtered = result;
    notifyListeners();
  }
}
