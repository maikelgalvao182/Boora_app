part of '../map_viewmodel.dart';
extension MapViewModelRealtime on MapViewModel {
  void _startBoundsCategoriesListener() {
    // Mantém chips sincronizados com o bounding box (viewport)
    _mapDiscoveryService.nearbyEvents.addListener(_handleBoundsEventsChanged);
    // Atualiza imediatamente com o valor atual (seeded)
    _handleBoundsEventsChanged();
  }

  void _stopBoundsCategoriesListener() {
    _mapDiscoveryService.nearbyEvents.removeListener(_handleBoundsEventsChanged);
  }

  /// Cancela todos os streams Firestore (usar no logout)
  /// Isso evita erros de permission-denied quando o usuário é deslogado
  void cancelAllStreams() {
    debugPrint('🔌 MapViewModel: Cancelando todos os streams...');
    _stopLocationTracking();
    _radiusSubscription?.cancel();
    _radiusSubscription = null;
    _reloadSubscription?.cancel();
    _reloadSubscription = null;
    _remoteDeletionSub?.cancel();
    _remoteDeletionSub = null;
    _stopBoundsCategoriesListener();
    _mapDiscoveryService.stopPeriodicTombstonePolling();
    BlockService.instance.removeListener(_onBlockedUsersChanged);

    // ✅ IMPORTANTE: limpar estado em memória para evitar markers “fantasmas” após logout/delete.
    // Sem isso, o GoogleMapView pode manter markers antigos porque o stream foi cancelado
    // e nenhum novo evento chega para disparar rebuild.
    _events = const [];
    _googleMarkers = <Marker>{};
    _mapReady = false;
    _lastLocation = null;
    _selectedCategory = null;
    _availableCategoriesInBounds = const [];
    _eventsInBoundsCount = 0;
    _matchingEventsInBoundsCount = 0;
    _eventsInBoundsCountByCategory = const {};

    notifyListeners();
    debugPrint('✅ MapViewModel: Streams cancelados');
  }

  /// Inicializa listener para mudanças de raio
  void _initializeRadiusListener() {
    _radiusSubscription = _streamController.radiusStream.listen((radiusKm) {
      debugPrint('🗺️ MapViewModel: Raio atualizado para $radiusKm km');
      // Recarregar eventos com novo raio
      loadNearbyEvents();
    });
    
    // Listener para mudanças de filtros (reload)
    _reloadSubscription = _streamController.reloadStream.listen((_) {
      debugPrint('🗺️ MapViewModel: Reload solicitado (filtros mudaram)');
      // Recarregar eventos com novos filtros
      loadNearbyEvents();
    });
    
    // ⬅️ LISTENER REATIVO PARA BLOQUEIOS
    BlockService.instance.addListener(_onBlockedUsersChanged);
    
    // 📍 Iniciar rastreamento de localização para atualizar cidade/estado
    _startLocationTracking();
    
    // ✅ Importante: não iniciar mais um stream global de eventos aqui.
    // A fonte de verdade para o mapa deve ser o viewport/bounds do GoogleMapView
    // (loadEventsInBounds/forceRefreshBounds), para evitar churn e tráfego
    // desnecessário.
  }
  
  /// Callback quando BlockService muda (via ChangeNotifier)
  void _onBlockedUsersChanged() {
    debugPrint('🔄 MapViewModel: Bloqueios mudaram - recarregando eventos do mapa...');
    // Recarrega tudo porque eventos desbloqueados não estão no cache local
    loadNearbyEvents();
  }
}
