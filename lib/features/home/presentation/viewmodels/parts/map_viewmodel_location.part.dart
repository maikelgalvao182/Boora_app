part of '../map_viewmodel.dart';

extension MapViewModelLocation on MapViewModel {
  /// Helper para obter repository de localização (via GetIt)
  LocationRepositoryInterface get _locationRepository => GetIt.instance<LocationRepositoryInterface>();

  void _startLocationTracking() {
    if (_positionSubscription != null) return;
    
    // Configurações de precisão e filtro de distância
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.medium, // Cidade/Estado não precisa de alta precisão
      distanceFilter: 2000, // Atualiza apenas se mover 2km
    );

    try {
      AppLogger.info('📍 [MapViewModel] Iniciando rastreamento de localização para atualização de cidade/estado...', tag: 'MapViewModel');
      _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
          .listen((Position position) {
            _handleUserPositionUpdate(position);
          }, onError: (e) {
            AppLogger.error('❌ [MapViewModel] Erro no tracking de localização: $e', tag: 'MapViewModel');
          });
    } catch (e) {
      AppLogger.error('❌ [MapViewModel] Falha ao iniciar stream de localização: $e', tag: 'MapViewModel');
    }
  }

  void _stopLocationTracking() {
    if (_positionSubscription != null) {
      AppLogger.info('🛑 [MapViewModel] Parando rastreamento de localização.', tag: 'MapViewModel');
      _positionSubscription?.cancel();
      _positionSubscription = null;
    }
  }

  Future<void> _handleUserPositionUpdate(Position position) async {
    final userId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      AppLogger.info('🔄 [MapViewModel] Localização alterada. Atualizando endereço...', tag: 'MapViewModel');
      
      // Reverse Geocoding
      final placemark = await _locationRepository.getUserAddress(
        position.latitude, 
        position.longitude
      );
      
      final city = placemark.locality;
      final state = placemark.administrativeArea;
      final country = placemark.country;

      if (city != null && state != null) {
        // Atualiza Store (UI reage imediatamente)
        UserStore.instance.updateCity(userId, city);
        UserStore.instance.updateState(userId, state);
        
        AppLogger.success('✅ [MapViewModel] UserStore atualizado: $city - $state', tag: 'MapViewModel');

        // Atualiza Firestore (Persistência)
        await _locationRepository.updateUserLocation(
            userId: userId,
            latitude: position.latitude,
            longitude: position.longitude,
            displayLatitude: position.latitude, 
            displayLongitude: position.longitude,
            country: country ?? '',
            locality: city,
            state: state,
        );
      }
    } catch (e) {
      // Ignora erro de geocoding silenciosamente para não spammar logs em caso de falha de rede temporária
      // AppLogger.error('❌ [MapViewModel] Falha ao atualizar endereço do usuário: $e', tag: 'MapViewModel');
    }
  }

  /// Obtém localização do usuário
  /// 
  /// Retorna LocationResult com informações detalhadas
  Future<LocationResult> getUserLocation() async {
    return await _locationService.getUserLocation();
  }
}
