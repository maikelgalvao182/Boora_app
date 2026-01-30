import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/people_filter.dart';
import 'package:partiu/features/home/data/models/user_ranking_model.dart';

/// State holder para ranking de pessoas
/// 
/// Segue o mesmo padrão do WeddingDiscoveryState:
/// - Lista master imutável (fonte de verdade)
/// - Filtro local reativo
/// - Zero requery, zero streams
/// - Filtragem instantânea
/// - 🔥 BLINDAGEM: preserva dados durante refresh
class PeopleRankingState extends ChangeNotifier {
  /// Lista master — FONTE DE VERDADE (nunca limpa durante refresh)
  final List<UserRankingModel> master;

  /// Filtro ativo
  PeopleFilter filter = const PeopleFilter();
  
  /// 🛡️ BLINDAGEM: dados anteriores para manter UI estável durante refresh
  List<UserRankingModel> _previousDisplayedRankings = [];
  Set<String> _previousVisibleIds = {};
  List<String> _previousStates = [];
  List<String> _previousCities = [];
  
  /// 🔒 Flag para detectar se estamos em refresh (proteção contra limpeza)
  bool _isRefreshing = false;

  PeopleRankingState(this.master) {
    // Inicializar dados anteriores
    _updatePreviousData();
  }

  // ---------------------------------------------
  // Métodos para mudar filtros
  // ---------------------------------------------
  
  /// Atualiza filtro de estado e reseta cidade
  void setStateFilter(String? state) {
    filter = PeopleFilter(state: state, city: null);
    _resetPagination();
    notifyListeners();
  }

  /// Atualiza filtro de cidade
  void setCityFilter(String? city) {
    filter = filter.copyWith(city: city);
    _resetPagination();
    notifyListeners();
  }

  /// Limpa todos os filtros
  void clearFilters() {
    filter = const PeopleFilter();
    _resetPagination();
    notifyListeners();
  }
  
  /// Atualiza lista master de forma SEGURA (nunca limpa durante refresh)
  /// 🔥 REGRA DE OURO: Durante refresh, NENHUM estado derivado pode ser resetado
  void updateMaster(List<UserRankingModel> newMaster, {bool isRefreshing = false}) {
    debugPrint('🔄 [PeopleRankingState] updateMaster called');
    debugPrint('   - newMaster.length: ${newMaster.length}');
    debugPrint('   - isRefreshing: $isRefreshing');
    debugPrint('   - current master.length: ${master.length}');
    
    // 🛡️ BLINDAGEM: Proteger contra limpeza indevida durante refresh
    if (isRefreshing && master.isNotEmpty) {
      debugPrint('   🛡️ BLINDAGEM ATIVA - preservando dados durante refresh');
      _isRefreshing = true;
      
      // Salvar estado atual ANTES de qualquer mudança
      _updatePreviousData();
    }
    
    // 🔥 CORREÇÃO CIRÚRGICA: Usar replaceRange ao invés de clear() + addAll()
    // Isso evita frames intermediários com lista vazia
    if (master.length != newMaster.length) {
      master.clear();
      master.addAll(newMaster);
    } else {
      // Se mesmo tamanho, substitua item por item (mais suave)
      for (int i = 0; i < newMaster.length; i++) {
        master[i] = newMaster[i];
      }
    }
    
    debugPrint('   - APÓS UPDATE master.length: ${master.length}');
    
    // Resetar paginação apenas se não estiver em refresh
    if (!isRefreshing) {
      _normalizeFilters();
      _resetPagination();
    }
    
    notifyListeners();
    
    // Limpar flag de refresh após notificar
    if (isRefreshing) {
      _isRefreshing = false;
    }
  }

  void _normalizeFilters() {
    // Limpar filtros inválidos para evitar colapso de lista
    if (filter.state != null && !availableStates.contains(filter.state)) {
      filter = const PeopleFilter();
      return;
    }

    if (filter.city != null && !availableCities.contains(filter.city)) {
      filter = filter.copyWith(city: null);
    }
  }

  // ---------------------------------------------
  // Lista filtrada reativa
  // ---------------------------------------------
  
  /// Retorna lista filtrada baseado no filtro atual
  List<UserRankingModel> get filteredItems {
    var list = master;

    // Filtro por estado
    if (filter.state != null && filter.state!.isNotEmpty) {
      list = list.where((u) => u.state == filter.state).toList();
    }

    // Filtro por cidade
    if (filter.city != null && filter.city!.isNotEmpty) {
      list = list.where((u) => u.locality == filter.city).toList();
    }

    return list;
  }

  /// IDs dos items visíveis (para usar com Visibility) com BLINDAGEM
  Set<String> get visibleIds {
    final current = filteredItems.map((e) => e.userId).toSet();
    
    // 🛡️ BLINDAGEM: Durante refresh, usar dados anteriores se conjunto atual estiver vazio
    if (_isRefreshing && current.isEmpty && _previousVisibleIds.isNotEmpty) {
      debugPrint('🛡️ [visibleIds] BLINDAGEM ATIVA - usando dados anteriores durante refresh');
      return _previousVisibleIds;
    }
    
    return current;
  }
  
  // ---------------------------------------------
  // 🚀 Paginação local (para InfiniteListView)
  // ---------------------------------------------
  
  int _displayedCount = 30;
  
  /// Rankings exibidos (paginados) com BLINDAGEM durante refresh
  List<UserRankingModel> get displayedRankings {
    // 🛡️ BLINDAGEM: Durante refresh, usar dados anteriores se lista atual estiver vazia
    final filtered = filteredItems;
    final current = filtered.take(_displayedCount).toList();
    
    // 🔥 PROTEÇÃO: Nunca retornar lista vazia durante refresh se havia dados antes
    if (_isRefreshing && current.isEmpty && _previousDisplayedRankings.isNotEmpty) {
      debugPrint('🛡️ [displayedRankings] BLINDAGEM ATIVA - usando dados anteriores durante refresh');
      return _previousDisplayedRankings;
    }
    
    return current;
  }
  
  /// Se tem mais rankings para carregar
  bool get hasMore => _displayedCount < filteredItems.length;
  
  /// Carrega mais rankings (paginação local - dados já em memória)
  void loadMore() {
    if (!hasMore) return;
    
    final filtered = filteredItems;
    final newCount = (_displayedCount + 30).clamp(0, filtered.length);
    
    debugPrint('📄 [PeopleRankingState] LoadMore: $_displayedCount -> $newCount');
    _displayedCount = newCount;
    notifyListeners();
  }
  
  /// Reset paginação (chamado ao mudar filtros)
  void _resetPagination() {
    _displayedCount = 30;
  }
  
  /// 🛡️ Atualiza dados anteriores para blindagem durante refresh
  void _updatePreviousData() {
    _previousDisplayedRankings = List.from(displayedRankings);
    _previousVisibleIds = Set.from(visibleIds);
    _previousStates = List.from(availableStates);
    _previousCities = List.from(availableCities);
    debugPrint('🛡️ [PeopleRankingState] Dados anteriores atualizados para blindagem');
  }

  // ---------------------------------------------
  // Opções únicas do filtro
  // ---------------------------------------------
  
  /// Estados disponíveis na lista master com BLINDAGEM
  List<String> get availableStates {
    final current = master
        .map((u) => u.state)
        .where((e) => e != null && e.isNotEmpty)
        .toSet()
        .cast<String>()
        .toList()
      ..sort();
    
    // 🛡️ BLINDAGEM: Durante refresh, usar dados anteriores se lista atual estiver vazia
    if (_isRefreshing && current.isEmpty && _previousStates.isNotEmpty) {
      debugPrint('🛡️ [availableStates] BLINDAGEM ATIVA - usando dados anteriores durante refresh');
      return _previousStates;
    }
    
    return current;
  }

  /// Cidades disponíveis baseado no estado selecionado com BLINDAGEM
  List<String> get availableCities {
    List<String> current;
    
    // Se nenhum estado selecionado, mostrar todas as cidades
    if (filter.state == null || filter.state!.isEmpty) {
      current = master
          .map((u) => u.locality)
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
    } else {
      // Se estado selecionado, mostrar apenas cidades daquele estado
      current = master
          .where((u) => u.state == filter.state)
          .map((u) => u.locality)
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
    }
    
    // 🛡️ BLINDAGEM: Durante refresh, usar dados anteriores se lista atual estiver vazia
    if (_isRefreshing && current.isEmpty && _previousCities.isNotEmpty) {
      debugPrint('🛡️ [availableCities] BLINDAGEM ATIVA - usando dados anteriores durante refresh');
      return _previousCities;
    }
    
    return current;
  }
}
