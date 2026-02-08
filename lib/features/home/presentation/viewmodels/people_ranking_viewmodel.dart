import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/user_ranking_model.dart';
import 'package:partiu/features/home/data/models/ranking_filters_model.dart';
import 'package:partiu/features/home/data/services/people_ranking_cache_service.dart';
import 'package:partiu/features/home/data/services/people_ranking_service.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/core/services/global_cache_service.dart';
import 'package:partiu/core/services/analytics_service.dart';
import 'package:partiu/core/services/user_status_service.dart';
import 'package:partiu/common/state/app_state.dart';

/// Estados de carregamento
enum LoadState {
  idle,        // nunca carregou
  loading,     // carregando (inclusive pull-to-refresh)
  loaded,      // carregou com sucesso
  error,       // erro no carregamento
}

/// ViewModel para gerenciar estado do ranking de pessoas
/// 
/// Responsabilidades:
/// - Carregar ranking de pessoas baseado em reviews
/// - Gerenciar estado de loading e erros
/// - Filtrar por cidade
/// - Fornecer dados limpos para a UI
class PeopleRankingViewModel extends ChangeNotifier {
  static const int _rankingLimit = 50;
  static const int _stateCitiesLimit = 1000;

  final PeopleRankingService _peopleRankingService;
  final GlobalCacheService _cache = GlobalCacheService.instance;
  final PeopleRankingCacheService _persistentCache = PeopleRankingCacheService();
  
  // Instância compartilhada (opcional - para acesso global)
  static PeopleRankingViewModel? _instance;
  static PeopleRankingViewModel? get instance => _instance;
  static set instance(PeopleRankingViewModel? value) => _instance = value;

  // Estado
  LoadState _loadState = LoadState.idle;
  String? _error;
  int _requestId = 0; // 🔒 Serialização de requests para evitar concorrência
  bool _isRefreshing = false; // 🔄 Flag para refresh explícito (pull-to-refresh)
  bool _initialized = false; // 🔒 Garantir que initialize() só rode uma vez

  // Dados
  List<UserRankingModel> _peopleRankings = [];
  List<String> _availableStates = [];
  List<String> _availableCities = [];
  RankingFilters? _rankingFilters;
  
  // Cache de cidades por estado para não reprocessar
  Map<String, List<String>> _citiesByState = {};

  // Filtros
  String? _selectedState;
  String? _selectedCity;

  PeopleRankingViewModel({
    PeopleRankingService? peopleRankingService,
  }) : _peopleRankingService = peopleRankingService ?? PeopleRankingService();

  // Getters - Estado
  LoadState get loadState => _loadState;
  bool get isLoading => _loadState == LoadState.loading;
  /// Retorna true se estamos no carregamento inicial (antes de ter qualquer dado)
  /// Isso inclui estado `idle` (nunca carregou) E estado `loading` com lista vazia
  bool get isInitialLoading => 
      (_loadState == LoadState.idle || _loadState == LoadState.loading) && _peopleRankings.isEmpty;
  bool get hasLoadedOnce => _loadState == LoadState.loaded || _loadState == LoadState.error;
  bool get isRefreshing => _isRefreshing;
  bool get shouldShowEmptyState => _loadState == LoadState.loaded && _peopleRankings.isEmpty && !_isRefreshing;
  String? get error => _error;

  // Getters - Dados
  List<UserRankingModel> get peopleRankings => _peopleRankings;
  List<String> get availableStates => _availableStates;
  List<String> get availableCities => _availableCities;

  // Getters - Filtros
  String? get selectedState => _selectedState;
  String? get selectedCity => _selectedCity;

  /// Inicializa o ViewModel carregando rankings e filtros disponíveis
  ///
  /// [loadFilters] controla se estados/cidades devem ser carregados.
  /// Use false quando a UI deriva filtros da lista master local.
  Future<void> initialize({bool loadFilters = true}) async {
    // 🔒 REGRA 1: initialize() só pode rodar UMA VEZ
    if (_initialized) {
      if (_peopleRankings.isEmpty && _loadState == LoadState.idle && !_isRefreshing) {
        debugPrint('♻️ [PeopleRankingViewModel] initialize() reexecução segura (estado vazio)');
        if (loadFilters) {
          await Future.wait([
            loadPeopleRanking(),
            _loadAvailableStates(),
            _loadAvailableCities(),
          ]);
        } else {
          await loadPeopleRanking();
        }
        return;
      }

      debugPrint('🚫 [PeopleRankingViewModel] initialize() já executado - ignorando');
      return;
    }
    
    // 🔒 REGRA 1: Nunca rodar initialize durante refresh
    if (_isRefreshing) {
      debugPrint('🚫 [PeopleRankingViewModel] initialize() bloqueado durante refresh');
      return;
    }
    
    _initialized = true;
    debugPrint('🚀 [PeopleRankingViewModel] Inicializando (primeira vez)...');
    
    // ⬅️ ESCUTA BlockService via ChangeNotifier (REATIVO INSTANTÂNEO)
    BlockService.instance.addListener(_onBlockedUsersChanged);
    
    if (loadFilters) {
      await Future.wait([
        loadPeopleRanking(),
        _loadAvailableStates(),
        _loadAvailableCities(),
      ]);
    } else {
      await loadPeopleRanking();
    }
    debugPrint('✅ [PeopleRankingViewModel] Inicialização completa');
  }
  
  /// Callback quando BlockService muda (via ChangeNotifier)
  void _onBlockedUsersChanged() {
    debugPrint('🔄 Bloqueios mudaram - refiltrando ranking de pessoas...');
    _refilterPeopleRanking();
  }
  
  /// Re-filtra ranking removendo usuários bloqueados
  void _refilterPeopleRanking() {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) return;
    
    final beforeCount = _peopleRankings.length;
    final blockedIds = BlockService.instance.getAllBlockedIds(currentUserId);
    
    _peopleRankings = _peopleRankings
        .where((person) => !blockedIds.contains(person.userId))
        .toList();
    
    final afterCount = _peopleRankings.length;
    final removedCount = beforeCount - afterCount;
    
    if (removedCount > 0) {
      debugPrint('🚫 [PeopleRankingViewModel] $removedCount pessoas removidas do ranking');
      notifyListeners();
    }
  }

  /// Carrega ranking de pessoas com cache global
  Future<void> loadPeopleRanking() async {
    debugPrint('📊 [PeopleRankingViewModel] Iniciando loadPeopleRanking');
    debugPrint('   - selectedState: $_selectedState');
    debugPrint('   - selectedCity: $_selectedCity');
    
    // 🔒 Incrementa RequestId para detectar respostas antigas
    final requestId = ++_requestId;
    
    // 🔵 STEP 1: Tentar buscar do cache global primeiro
    final cacheKey = _buildCacheKey();
    final cached = _cache.get<List<UserRankingModel>>(cacheKey);
    
    // 🔒 REGRA 2: refresh() NÃO pode usar cache - sempre forçar network
    if (cached != null && cached.isNotEmpty && !_isRefreshing) {
      debugPrint('🗂️ [PeopleRanking] Cache HIT - ${cached.length} pessoas');
      
      // 🔍 Filtrar usuários inativos do cache (validação em tempo real)
      final beforeStatusFilter = cached.length;
      _peopleRankings = cached.where((person) {
        final isActive = UserStatusService.instance.isUserActiveCached(person.userId);
        // Se não está em cache, mantém na lista (será validado no próximo load)
        // Se está em cache e é inativo, remove
        return isActive == null || isActive == true;
      }).toList();
      final afterStatusFilter = _peopleRankings.length;
      if (beforeStatusFilter != afterStatusFilter) {
        debugPrint('🚫 ${beforeStatusFilter - afterStatusFilter} usuários inativos removidos do cache');
      }
      
      // 🔒 REGRA 3: loadState NÃO pode voltar para idle durante operação
      if (_loadState == LoadState.idle) {
        debugPrint('🟢 [LoadState] idle → loaded (cache hit)');
        _loadState = LoadState.loaded;
      }
      
      // 🔒 REGRA 4: Cache não notifica durante refresh
      if (!_isRefreshing) {
        notifyListeners();
      }
      
      // 🚫 OTIMIZAÇÃO: Silent refresh removido - TTL de 10 min é suficiente
      // Isso economiza ~30-60% dos requests por sessão
      _logRankingTelemetry(
        reason: 'cache_hit',
        cacheHit: true,
      );
      return;
    }

    debugPrint('📦 [PeopleRanking] Verificando Hive cache...');
    try {
      await _persistentCache.initialize().timeout(const Duration(seconds: 3));
      debugPrint('📦 [PeopleRanking] Hive inicializado');
    } catch (e) {
      debugPrint('⚠️ [PeopleRanking] Hive init timeout/error: $e - continuando sem cache');
    }
    
    debugPrint('📦 [PeopleRanking] Verificando cache persistente...');
    if (!_isRefreshing) {
      try {
        final persistent = _persistentCache.getCachedRanking(cacheKey);
        debugPrint('📦 [PeopleRanking] getCachedRanking retornou: ${persistent?.length ?? "null"}');
        if (persistent != null && persistent.isNotEmpty) {
          debugPrint('📦 [PeopleRanking] Hive cache HIT - ${persistent.length} pessoas');
          _peopleRankings = persistent;

          _cache.set(
            cacheKey,
            persistent,
            ttl: const Duration(minutes: 10),
          );

          if (_loadState == LoadState.idle) {
            debugPrint('🟢 [LoadState] idle → loaded (hive cache hit)');
            _loadState = LoadState.loaded;
          }

          notifyListeners();
          _logRankingTelemetry(
            reason: 'hive_cache',
            cacheHit: true,
          );
          return;
        }
      } catch (e) {
        debugPrint('⚠️ [PeopleRanking] Erro ao ler cache: $e');
      }
    }
    
    if (_isRefreshing && cached != null) {
      debugPrint('🔄 [PeopleRanking] Refresh - ignorando cache, forçando network');
    }
    
    debugPrint('🗂️ [PeopleRanking] Cache MISS - carregando do Firestore');
    
    // 🚀 IMPORTANTE: Não limpar _peopleRankings aqui para evitar flicker
    
    // 🔒 REGRA 3: loadState NÃO pode ser alterado durante refresh
    if (!_isRefreshing) {
      debugPrint('🔵 [LoadState] $_loadState → loading (iniciando fetch)');
      _loadState = LoadState.loading;
    } else {
      debugPrint('🔄 [Refresh] Mantendo loadState atual durante refresh: $_loadState');
    }
    
    _error = null;
    notifyListeners();
    debugPrint('📊 [PeopleRankingViewModel] UI notificada, iniciando fetch do Firestore...');

    try {
      debugPrint('   - Chamando service.getPeopleRanking...');
      final result = await _peopleRankingService.getPeopleRanking(
        selectedState: _selectedState,
        selectedLocality: _selectedCity,
        limit: _rankingLimit,
      ).timeout(const Duration(seconds: 15), onTimeout: () {
        debugPrint('⏰ [PeopleRanking] TIMEOUT após 15s');
        return <UserRankingModel>[];
      });
      
      // 🔒 Verificar se este request ainda é válido
      if (requestId != _requestId) {
        debugPrint('⚠️ [PeopleRanking] Request $requestId descartado (atual: $_requestId)');
        return; // Resposta antiga, ignora
      }
      
      _peopleRankings = result;
      debugPrint('✅ Ranking de pessoas carregado: ${_peopleRankings.length} pessoas');
      
      // 🔍 Filtrar usuários inativos (validação em tempo real)
      final beforeStatusFilter = _peopleRankings.length;
      _peopleRankings = _peopleRankings.where((person) {
        final isActive = UserStatusService.instance.isUserActiveCached(person.userId);
        // Se não está em cache, mantém na lista (será validado no próximo load)
        // Se está em cache e é inativo, remove
        return isActive == null || isActive == true;
      }).toList();
      final afterStatusFilter = _peopleRankings.length;
      if (beforeStatusFilter != afterStatusFilter) {
        debugPrint('🚫 ${beforeStatusFilter - afterStatusFilter} usuários inativos removidos');
      }
      
      // Filtra usuários bloqueados imediatamente
      final currentUserId = AppState.currentUserId;
      if (currentUserId != null) {
        final blockedIds = BlockService.instance.getAllBlockedIds(currentUserId);
        final beforeFilter = _peopleRankings.length;
        _peopleRankings = _peopleRankings
            .where((person) => !blockedIds.contains(person.userId))
            .toList();
        final afterFilter = _peopleRankings.length;
        if (beforeFilter != afterFilter) {
          debugPrint('🚫 ${beforeFilter - afterFilter} pessoas bloqueadas filtradas');
        }
      }
      
      if (_peopleRankings.isNotEmpty) {
        debugPrint('   - Top 3:');
        for (var i = 0; i < _peopleRankings.length && i < 3; i++) {
          final r = _peopleRankings[i];
          debugPrint('     ${i + 1}. ${r.fullName} - ${r.overallRating}⭐ (${r.totalReviews} reviews)');
        }
        
        // 🔵 STEP 2: Salvar no cache global (TTL: 6 horas)
        _cache.set(
          cacheKey,
          _peopleRankings,
          ttl: const Duration(hours: 6),
        );
        debugPrint('🗂️ [PeopleRanking] Cache SAVED - ${_peopleRankings.length} pessoas');

        await _persistentCache.setCachedRanking(cacheKey, _peopleRankings);
      }

      _logRankingTelemetry(
        reason: _isRefreshing ? 'refresh' : 'network',
        cacheHit: false,
      );
    } catch (error, stackTrace) {
      _error = 'Erro ao carregar ranking de pessoas';
      debugPrint('🔴 [LoadState] loading → error');
      _loadState = LoadState.error;
      debugPrint('❌ [PeopleRankingViewModel] $_error');
      debugPrint('   Error: $error');
      debugPrint('   StackTrace: $stackTrace');
    } finally {
      // 🔒 REGRA 3: loadState NÃO pode ser alterado durante refresh
      if (_error == null && !_isRefreshing) {
        debugPrint('🟢 [LoadState] loading → loaded (fetch completo)');
        _loadState = LoadState.loaded;
      } else if (_error != null && !_isRefreshing) {
        debugPrint('🔴 [LoadState] loading → error (fetch falhou)');
        _loadState = LoadState.error;
      } else if (_isRefreshing) {
        debugPrint('🔄 [Refresh] LoadState preservado durante refresh: $_loadState');
      }
      
      notifyListeners();
      debugPrint('   - loadState FINAL: $_loadState');
      debugPrint('   - error: $_error');
      debugPrint('   - _peopleRankings.length: ${_peopleRankings.length}');
    }
  }

  void _logRankingTelemetry({
    required String reason,
    required bool cacheHit,
  }) {
    final metrics = _peopleRankingService.lastMetrics;
    AnalyticsService.instance.logEvent(
      'people_ranking_load',
      parameters: {
        'reason': reason,
        'cache_hit': cacheHit ? 1 : 0,
        'state': _selectedState ?? 'all',
        'city': _selectedCity ?? 'all',
        'reviews_read': metrics?.reviewsRead ?? 0,
        'users_read': metrics?.usersRead ?? 0,
        'unique_reviewees': metrics?.uniqueReviewees ?? 0,
        'limit_used': metrics?.limitUsed ?? 0,
        'duration_ms': metrics?.durationMs ?? 0,
      },
    );
  }

  /// Constrói chave de cache baseada nos filtros atuais
  String _buildCacheKey() {
    final state = _selectedState ?? 'all';
    final city = _selectedCity ?? 'all';
    return '${CacheKeys.rankingGlobal}_people_${state}_$city';
  }

  /// Atualização silenciosa em background (não mostra loading)
  Future<void> _silentRefreshPeopleRanking() async {
    try {
      debugPrint('🔄 [PeopleRanking] Silent refresh iniciado');
      
      final fresh = await _peopleRankingService.getPeopleRanking(
        selectedState: _selectedState,
        selectedLocality: _selectedCity,
        limit: _rankingLimit,
      );

      // Filtrar bloqueados
      final currentUserId = AppState.currentUserId;
      if (currentUserId != null) {
        final blockedIds = BlockService.instance.getAllBlockedIds(currentUserId);
        final filtered = fresh
            .where((person) => !blockedIds.contains(person.userId))
            .toList();

        // Comparar com cache atual
        final hasChanges = filtered.length != _peopleRankings.length ||
            (filtered.isNotEmpty && 
             _peopleRankings.isNotEmpty && 
             filtered.first.userId != _peopleRankings.first.userId);

        if (hasChanges) {
          debugPrint('🔄 [PeopleRanking] Dados atualizados detectados');
          _peopleRankings = filtered;
          
          // Atualizar cache
          final cacheKey = _buildCacheKey();
          _cache.set(
            cacheKey,
            filtered,
            ttl: const Duration(minutes: 10),
          );
          
          notifyListeners();
        } else {
          debugPrint('🔄 [PeopleRanking] Nenhuma mudança detectada');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [PeopleRanking] Erro no silent refresh: $e');
      // Não exibe erro ao usuário - silent refresh falhou mas UI continua ok
    }
  }

  /// Carrega lista de estados disponíveis com cache
  Future<void> _loadAvailableStates() async {
    debugPrint('🗺️ [PeopleRankingViewModel] Carregando estados...');
    
    // 🔵 Tentar cache primeiro
    final cached = _cache.get<List<String>>('${CacheKeys.rankingGlobal}_people_states');
    if (cached != null && cached.isNotEmpty) {
      debugPrint('🗂️ [PeopleRanking] Estados do cache - ${cached.length}');
      _availableStates = cached;
      return;
    }
    
    try {
      final filters = await _getRankingFilters();
      if (filters != null && filters.states.isNotEmpty) {
        _availableStates = filters.states;
        _rankingFilters = filters;
        _citiesByState = filters.citiesByState;
      } else {
        _availableStates = await _peopleRankingService.getAvailableStates();
      }
      debugPrint('✅ Estados disponíveis: ${_availableStates.length}');
      if (_availableStates.isNotEmpty) {
        debugPrint('   - Estados: ${_availableStates.join(", ")}');
        
        // Salvar no cache (TTL: 10 minutos)
        _cache.set(
          '${CacheKeys.rankingGlobal}_people_states',
          _availableStates,
          ttl: const Duration(minutes: 10),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('⚠️ Erro ao carregar estados: $error');
      debugPrint('   StackTrace: $stackTrace');
    }
  }

  /// Carrega lista de cidades disponíveis com cache
  Future<void> _loadAvailableCities() async {
    debugPrint('🌆 [PeopleRankingViewModel] Carregando cidades...');
    
    // 🔵 Tentar cache primeiro
    final cached = _cache.get<List<String>>('${CacheKeys.rankingGlobal}_people_cities');
    if (cached != null && cached.isNotEmpty) {
      debugPrint('🗂️ [PeopleRanking] Cidades do cache - ${cached.length}');
      _availableCities = cached;
      return;
    }
    
    try {
      final filters = await _getRankingFilters();
      if (filters != null && filters.cities.isNotEmpty) {
        _availableCities = filters.cities;
        _rankingFilters = filters;
        _citiesByState = filters.citiesByState;
      } else {
        final allCities = await _peopleRankingService.getAvailableCities();
        _availableCities = allCities;
      }
      debugPrint('✅ Cidades totais disponíveis: ${_availableCities.length}');
      
      if (_availableCities.isNotEmpty) {
        debugPrint('   - Primeiras 5: ${_availableCities.take(5).join(", ")}');
        
        // Salvar no cache (TTL: 10 minutos)
        _cache.set(
          '${CacheKeys.rankingGlobal}_people_cities',
          _availableCities,
          ttl: const Duration(minutes: 10),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('⚠️ Erro ao carregar cidades: $error');
      debugPrint('   StackTrace: $stackTrace');
    }
  }

  /// Atualiza filtro de estado
  Future<void> selectState(String? state) async {
    if (_selectedState == state) {
      debugPrint('🗺️ [PeopleRankingViewModel] Estado já selecionado: $state');
      return;
    }
    
    _selectedState = state;
    _selectedCity = null; // Reset cidade ao trocar estado
    
    debugPrint('🗺️ [PeopleRankingViewModel] Estado selecionado: ${state ?? "Todos"}');
    
    // Atualizar lista de cidades baseado no estado
    await _updateAvailableCitiesForState();
    
    notifyListeners();
    await loadPeopleRanking();
  }

  /// Atualiza lista de cidades baseado no estado selecionado
  Future<void> _updateAvailableCitiesForState() async {
    if (_selectedState == null) {
      // Se nenhum estado selecionado, mostrar todas as cidades
      _availableCities = await _peopleRankingService.getAvailableCities();
      return;
    }

    final cachedFilters = _rankingFilters?.citiesByState[_selectedState!];
    if (cachedFilters != null && cachedFilters.isNotEmpty) {
      _availableCities = cachedFilters;
      debugPrint('   📦 Usando ranking_filters: ${_availableCities.length} cidades');
      return;
    }
    
    // Verificar cache
    if (_citiesByState.containsKey(_selectedState)) {
      _availableCities = _citiesByState[_selectedState]!;
      debugPrint('   📦 Usando cache: ${_availableCities.length} cidades');
      return;
    }
    
    // Buscar cidades do estado selecionado filtrando do ranking
    debugPrint('   🔍 Filtrando cidades do estado: $_selectedState');
    try {
      // Buscar rankings do estado para extrair cidades
      final stateRankings = await _peopleRankingService.getPeopleRanking(
        selectedState: _selectedState,
        limit: _stateCitiesLimit, // Buscar bastante para pegar todas as cidades
        restrictToTopIds: false,
      );
      
      final cities = stateRankings
          .map((r) => r.locality)
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      
      _availableCities = cities;
      _citiesByState[_selectedState!] = cities; // Cachear
      
      debugPrint('   ✅ ${_availableCities.length} cidades no estado $_selectedState');
    } catch (error) {
      debugPrint('   ⚠️ Erro ao filtrar cidades: $error');
      _availableCities = [];
    }
  }

  Future<RankingFilters?> _getRankingFilters() async {
    if (_rankingFilters != null) return _rankingFilters;

    await _persistentCache.initialize();
    final cached = _persistentCache.getCachedFilters();
    if (cached != null) {
      _rankingFilters = cached;
      return cached;
    }

    final fetched = await _peopleRankingService.getRankingFilters();
    if (fetched != null) {
      _rankingFilters = fetched;
      await _persistentCache.setCachedFilters(fetched);
    }

    return fetched;
  }

  /// Atualiza filtro de cidade
  Future<void> selectCity(String? city) async {
    if (_selectedCity == city) {
      debugPrint('🌆 [PeopleRankingViewModel] Cidade já selecionada: $city');
      return;
    }
    
    _selectedCity = city;
    debugPrint('🌆 [PeopleRankingViewModel] Cidade selecionada: ${city ?? "Todas"}');
    
    notifyListeners();
    await loadPeopleRanking();
  }

  /// Limpa filtro de estado
  Future<void> clearStateFilter() async {
    await selectState(null);
  }

  /// Limpa filtro de cidade
  Future<void> clearCityFilter() async {
    await selectCity(null);
  }

  /// Recarrega ranking forçando busca na network (nunca usa cache)
  /// 🔒 REGRA 2: refresh() = forçar network, sempre
  ///
  /// [loadFilters] controla se estados/cidades devem ser recarregados.
  Future<void> refresh({bool loadFilters = true}) async {
    debugPrint('🔄 [PeopleRankingViewModel] refresh() chamado');
    debugPrint('   - ANTES: loadState = $_loadState');
    debugPrint('   - ANTES: _peopleRankings.length = ${_peopleRankings.length}');
    debugPrint('   - ANTES: _isRefreshing = $_isRefreshing');
    
    _isRefreshing = true;
    
    // Invalida cache para garantir dados frescos do servidor
    final cacheKey = _buildCacheKey();
    _cache.remove(cacheKey);
    await _persistentCache.invalidateRanking(cacheKey);
    
    notifyListeners();
    
    try {
      // 🚀 REFRESH = apenas recarregar dados, nunca initialize()
      if (loadFilters) {
        await Future.wait([
          loadPeopleRanking(), // Força network devido ao _isRefreshing = true
          _loadAvailableStates(),
          _loadAvailableCities(),
        ]);
      } else {
        await loadPeopleRanking();
      }
      
      debugPrint('✅ [PeopleRankingViewModel] refresh() dados atualizados');
    } catch (error) {
      debugPrint('❌ [PeopleRankingViewModel] refresh() erro: $error');
      _error = 'Erro ao atualizar ranking';
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
    
    debugPrint('🔄 [PeopleRankingViewModel] refresh() completo');
    debugPrint('   - DEPOIS: loadState = $_loadState');
    debugPrint('   - DEPOIS: _peopleRankings.length = ${_peopleRankings.length}');
    debugPrint('   - DEPOIS: _isRefreshing = $_isRefreshing');
  }
  
  @override
  void dispose() {
    BlockService.instance.removeListener(_onBlockedUsersChanged);
    super.dispose();
  }
}
