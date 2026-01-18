import 'dart:async';

import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/core/utils/location_offset_helper.dart';
import 'package:partiu/features/location/domain/repositories/location_repository_interface.dart';
import 'package:partiu/core/services/state_abbreviation_service.dart';
import 'package:partiu/core/services/location_service.dart';
import 'package:partiu/core/services/location_permission_flow.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Estados do salvamento de localização
enum LocationSaveState {
  idle,
  loading,
  success,
  error,
}

/// ViewModel simplificado para atualização de localização
/// 
/// Responsabilidades reduzidas:
/// - Orquestrar o fluxo de salvamento de localização
/// - Obter endereço legível via repository
/// - Salvar dados no Firestore via repository
/// - Notificar UI sobre estados (loading, success, error)
/// 
/// Delegado para outros serviços:
/// - LocationPermissionFlow: gerenciar permissões
/// - LocationService: obter coordenadas GPS
class UpdateLocationViewModel extends ChangeNotifier {
  
  UpdateLocationViewModel({
    required LocationRepositoryInterface locationRepository,
    required LocationService locationService,
    required LocationPermissionFlow permissionFlow,
  }) : _locationRepository = locationRepository,
       _locationService = locationService,
       _permissionFlow = permissionFlow;
  
  final LocationRepositoryInterface _locationRepository;
  final LocationService _locationService;
  final LocationPermissionFlow _permissionFlow;
  
  // Estados de salvamento
  LocationSaveState _saveState = LocationSaveState.idle;
  String? _savedLocation;
  String? _saveError;
  
  // Getters de salvamento
  LocationSaveState get saveState => _saveState;
  String? get savedLocation => _savedLocation;
  String? get saveError => _saveError;
  
  /// Verifica o status da permissão sem solicitar
  Future<LocationPermission> checkPermissionStatus() async {
    return await _permissionFlow.check();
  }
  
  /// Solicita permissão de localização
  Future<LocationPermission> requestLocationPermission() async {
    return await _permissionFlow.resolvePermission();
  }
  
  /// Verifica se GPS está habilitado
  Future<bool> isGpsEnabled() async {
    return await _permissionFlow.isGpsEnabled();
  }
  
  /// Obtém a localização atual do dispositivo via LocationService
  Future<Position?> getCurrentLocation() async {
    return await _locationService.getCurrentLocation();
  }
  
  /// Salva a localização atual do usuário no Firestore
  /// 
  /// Fluxo:
  /// 1. Obtém posição atual via LocationService
  /// 2. Busca endereço legível via repository (geocoding reverso)
  /// 3. Salva no Firestore via repository
  Future<void> saveCurrentLocation(String userId) async {
    _saveState = LocationSaveState.loading;
    _saveError = null;
    _savedLocation = null;
    notifyListeners();
    
    try {
      // 1. Obtém posição atual
      final position = await _locationService.getCurrentLocation(
        timeout: const Duration(seconds: 10),
      );
      
      if (position == null) {
        _saveState = LocationSaveState.error;
        _saveError = 'Unable to get current location';
        notifyListeners();
        return;
      }
      
      // 2. Salva usando as coordenadas obtidas
      await saveLocationDirectly(
        userId: userId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      
    } catch (e) {
      _saveState = LocationSaveState.error;
      _saveError = 'Error getting location: $e';
      AppLogger.error('Error in saveCurrentLocation: $e', tag: 'UpdateLocationVM');
      notifyListeners();
    }
  }
  
  /// Salva localização diretamente com coordenadas fornecidas
  Future<void> saveLocationDirectly({
    required String userId,
    required double latitude,
    required double longitude,
  }) async {
    _saveState = LocationSaveState.loading;
    _saveError = null;
    _savedLocation = null;
    notifyListeners();
    
    try {
      AppLogger.info('Saving location - lat: $latitude, lng: $longitude', tag: 'UpdateLocationVM');
      
      // Get user readable address
      final place = await _locationRepository.getUserAddress(
        latitude,
        longitude,
      );
      
      // Get locality and state
      String? locality;
      String? state;
      // Check locality
      if (place.locality == null || place.locality!.isEmpty) {
        locality = place.administrativeArea;
      } else {
        locality = place.locality;
      }
      // Get state from administrativeArea
      state = place.administrativeArea ?? '';
      
      // Abrevia o estado antes de salvar
      final stateAbbr = StateAbbreviationService.getAbbreviation(state);
      
      // ✅ GARANTIR conversão para String explícita
      final countryStr = place.country?.toString() ?? '';
      final localityStr = locality?.toString() ?? '';
      final stateStr = stateAbbr.toString();
      
      AppLogger.info('Location data: country=$countryStr, locality=$localityStr, state=$stateStr', tag: 'UpdateLocationVM');
      
      // ⚠️ VALIDAÇÃO: Backend requer todos os campos não vazios
      if (countryStr.isEmpty) {
        throw Exception('País está vazio. Não é possível salvar localização sem país.');
      }
      if (localityStr.isEmpty) {
        throw Exception('Cidade está vazia. Não é possível salvar localização sem cidade.');
      }
      if (stateStr.isEmpty) {
        throw Exception('Estado está vazio. Não é possível salvar localização sem estado.');
      }
      
      // 🚨 VALIDAÇÃO PRÉ-OFFSET: Garantir que valores são lat/lng válidos
      if (latitude < -90 || latitude > 90) {
        throw Exception(
          'Latitude inválida: $latitude. '
          'Deve estar entre -90 e +90. '
          'Possível bug: coordenada projetada sendo usada como latitude.'
        );
      }
      
      if (longitude < -180 || longitude > 180) {
        throw Exception(
          'Longitude inválida: $longitude. '
          'Deve estar entre -180 e +180. '
          'Possível bug: coordenada projetada sendo usada como longitude.'
        );
      }
      
      AppLogger.info('✅ Validação de coordenadas passou:', tag: 'UpdateLocationVM');
      AppLogger.info('   Latitude: $latitude (válida)', tag: 'UpdateLocationVM');
      AppLogger.info('   Longitude: $longitude (válida)', tag: 'UpdateLocationVM');
      
      // 🔒 Gerar coordenadas display com offset determinístico
      final displayCoords = LocationOffsetHelper.generateDisplayLocation(
        realLat: latitude,
        realLng: longitude,
        userId: userId,
      );
      final displayLatitude = displayCoords['displayLatitude']!;
      final displayLongitude = displayCoords['displayLongitude']!;
      
      AppLogger.info('🔒 Generated display offset:', tag: 'UpdateLocationVM');
      AppLogger.info('   Real: ($latitude, $longitude)', tag: 'UpdateLocationVM');
      AppLogger.info('   Display: ($displayLatitude, $displayLongitude)', tag: 'UpdateLocationVM');
      
      // Update User location
      await _locationRepository.updateUserLocation(
        userId: userId,
        latitude: latitude,
        longitude: longitude,
        displayLatitude: displayLatitude,
        displayLongitude: displayLongitude,
        country: countryStr,
        locality: localityStr,
        state: stateStr,
      );
      
      _saveState = LocationSaveState.success;
      _savedLocation = '$countryStr, $localityStr, $stateAbbr';
      
      AppLogger.success('Location saved successfully', tag: 'UpdateLocationVM');
      notifyListeners();
      
    } on TimeoutException {
      _saveState = LocationSaveState.error;
      _saveError = 'Location request timed out';
      
      AppLogger.error('Timeout saving location', tag: 'UpdateLocationVM');
      notifyListeners();
      
    } catch (e) {
      _saveState = LocationSaveState.error;
      _saveError = 'Failed to save location: $e';
      
      AppLogger.error('Error saving location: $e', tag: 'UpdateLocationVM');
      notifyListeners();
    }
  }
  
  /// Reseta o estado de salvamento
  void resetSaveState() {
    _saveState = LocationSaveState.idle;
    _saveError = null;
    _savedLocation = null;
    notifyListeners();
  }
}
