import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/locations_ranking_model.dart';
import 'package:partiu/features/home/data/services/locations_ranking_service.dart';
import 'package:partiu/features/home/data/services/user_location_service.dart';

/// ViewModel para gerenciar estado do ranking
/// 
/// Responsabilidades:
/// - Carregar ranking de locais
/// - Gerenciar estado de loading e erros
/// - Filtrar por raio geográfico
/// - Fornecer dados limpos para a UI
class RankingViewModel extends ChangeNotifier {
  final LocationsRankingService _rankingService;
  final UserLocationService _locationService;

  // Estado
  bool _isLoadingLocations = false;
  String? _error;

  // Dados
  List<LocationRankingModel> _locationRankings = [];

  // Filtros
  double? _userLat;
  double? _userLng;
  double _radiusKm = 30.0; // Raio padrão 30km
  bool _useRadiusFilter = false;

  RankingViewModel({
    LocationsRankingService? rankingService,
    UserLocationService? locationService,
  })  : _rankingService = rankingService ?? LocationsRankingService(),
        _locationService = locationService ?? UserLocationService();

  // Getters - Estado
  bool get isLoadingLocations => _isLoadingLocations;
  bool get isLoading => _isLoadingLocations;
  String? get error => _error;

  // Getters - Dados
  List<LocationRankingModel> get locationRankings => _locationRankings;

  // Getters - Filtros
  double get radiusKm => _radiusKm;
  bool get useRadiusFilter => _useRadiusFilter;
  bool get hasLocation => _userLat != null && _userLng != null;

  /// Inicializa o ViewModel carregando localização e rankings
  /// Inicializa o ViewModel carregando localização e ranking de locais
  Future<void> initialize() async {
    await _loadUserLocation();
    await loadLocationsRanking();
  }

  /// Carrega localização do usuário
  Future<void> _loadUserLocation() async {
    try {
      final result = await _locationService.getUserLocation();
      
      if (!result.hasError) {
        _userLat = result.location.latitude;
        _userLng = result.location.longitude;
        debugPrint('📍 Localização do usuário: $_userLat, $_userLng');
      }
    } catch (error) {
      debugPrint('⚠️ Não foi possível obter localização: $error');
    }
  }

  /// Carrega ranking de locais
  Future<void> loadLocationsRanking() async {
    _isLoadingLocations = true;
    _error = null;
    notifyListeners();

    try {
      _locationRankings = await _rankingService.getLocationsRanking(
        userLat: _useRadiusFilter ? _userLat : null,
        userLng: _useRadiusFilter ? _userLng : null,
        radiusKm: _useRadiusFilter ? _radiusKm : null,
      );
    } catch (error) {
      _error = 'Erro ao carregar ranking de locais';
      debugPrint('❌ $_error: $error');
    } finally {
      _isLoadingLocations = false;
      notifyListeners();
    }
  }

  /// Alterna filtro de raio
  Future<void> toggleRadiusFilter() async {
    _useRadiusFilter = !_useRadiusFilter;
    debugPrint('🔘 Filtro de raio: ${_useRadiusFilter ? 'ATIVADO' : 'DESATIVADO'}');
    
    notifyListeners();
    await loadLocationsRanking();
  }

  /// Atualiza raio de busca
  Future<void> updateRadius(double newRadiusKm) async {
    if (_radiusKm == newRadiusKm) return;
    
    _radiusKm = newRadiusKm;
    debugPrint('📏 Raio atualizado: $_radiusKm km');
    
    if (_useRadiusFilter) {
      notifyListeners();
      await loadLocationsRanking();
    }
  }

  /// Recarrega todos os rankings
  Future<void> refresh() async {
    await initialize();
  }
}