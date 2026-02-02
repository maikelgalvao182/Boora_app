import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/place_service.dart';
import 'package:partiu/plugins/locationpicker/entities/localization_item.dart';
import 'package:partiu/plugins/locationpicker/place_picker.dart';
import 'package:partiu/plugins/locationpicker/uuid.dart';
import 'dart:ui' show PlatformDispatcher;
import 'dart:async';

/// Controller que gerencia todo o estado do LocationPicker
class LocationPickerController extends ChangeNotifier {
  LocationPickerController({
    required this.placeService,
    required this.localizationItem,
    LatLng? initialLocation,
  }) : _currentLocation = initialLocation;

  final PlaceService placeService;
  final LocalizationItem localizationItem;

  // Estado do mapa
  final LatLng? _currentLocation;
  LatLng? _selectedLocation;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};

  // Estado do lugar selecionado
  LocationResult? _locationResult;
  List<String> _selectedPlacePhotos = [];

  // Controla se deve ignorar updates automáticos do mapa
  bool _lockOnSelectedPlace = false;

  // Controla se usuário confirmou a seleção clicando no dropdown
  bool _isLocationConfirmed = false;

  // Autocomplete
  List<RichSuggestion> _suggestions = [];
  bool _hasSearchTerm = false;
  String _previousSearchTerm = '';
  final String _sessionToken = Uuid().generateV4();
  Timer? _debounceTimer;

  // Getters
  LatLng? get currentLocation => _currentLocation;
  LatLng? get selectedLocation => _selectedLocation;
  Set<Marker> get markers => _markers;
  Set<Circle> get circles => _circles;
  LocationResult? get locationResult => _locationResult;
  List<String> get selectedPlacePhotos => _selectedPlacePhotos;
  bool get hasSearchTerm => _hasSearchTerm;
  List<RichSuggestion> get suggestions => _suggestions;
  bool get isLocked => _lockOnSelectedPlace;
  bool get isLocationConfirmed => _isLocationConfirmed;

  // -------------------------------------------------------------
  //  ATUALIZAÇÕES DO MAPA
  // -------------------------------------------------------------

  void setMarker(LatLng location) {
    _selectedLocation = location;
    _markers = {
      Marker(
        markerId: const MarkerId('selected-location'),
        position: location,
      ),
    };
    _updateCircle(location);
  }

  /// Atualiza o círculo de range ao redor da localização
  void _updateCircle(LatLng center) {
    _circles = {
      Circle(
        circleId: const CircleId('location_range'),
        center: center,
        radius: 300, // 300 metros de raio
        fillColor: const Color(0xFFD32F2F).withOpacity(0.15),
        strokeColor: const Color(0xFFD32F2F).withOpacity(0.5),
        strokeWidth: 2,
      ),
    };
  }

  Future<void> moveToLocation(
    LatLng location, {
    String? placeId,
  }) async {
    // Evitar processamento se a localização não mudou significativamente
    if (_selectedLocation != null && _isSameCoord(_selectedLocation!, location) && placeId == null) {
      // Mesmo se as coordenadas não mudaram, garantir que o círculo está visível
      if (_circles.isEmpty) {
        _updateCircle(location);
        notifyListeners();
      }
      return;
    }

    setMarker(location);

    final isExplicitSelection = placeId != null;

    if (isExplicitSelection) {
      _lockOnSelectedPlace = true; // trava qualquer movimento automático
      // Fotos do Google Places desativadas (custo). Mantemos lista vazia.
      _selectedPlacePhotos = [];
    }

    // reverse geocode NUNCA altera as fotos
    await _loadReverseGeocode(location);

    // Notificar apenas uma vez após todas as operações
    notifyListeners();
  }

  // -------------------------------------------------------------
  //  BUSCAS
  // -------------------------------------------------------------

  Future<void> searchPlace(String query) async {
    _hasSearchTerm = query.isNotEmpty;

    if (query.isEmpty) {
      _debounceTimer?.cancel();
      _suggestions = [];
      _previousSearchTerm = '';
      notifyListeners();
      return;
    }

    // Notificar UI (ex: mostrar botão X)
    notifyListeners();

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (query == _previousSearchTerm) return;
      
      _previousSearchTerm = query;

      // Otimização: Evitar chamadas curtas
      if (query.length < 3) {
        if (_suggestions.isNotEmpty) {
           _suggestions = [];
           notifyListeners();
        }
        return;
      }

      final results = await placeService.autocomplete(
        query: query,
        sessionToken: _sessionToken,
        localization: localizationItem,
        bias: _locationResult?.latLng,
        countryCode: _locationResult?.country?.shortName ?? PlatformDispatcher.instance.locale.countryCode,
      );

      _suggestions = results;
      notifyListeners();
    });
  }

  Future<LatLng?> selectPlaceFromSuggestion(String placeId) async {
    _lockOnSelectedPlace = true; // trava o mapa
    _isLocationConfirmed = true; // confirma a seleção

    // ✅ Buscar detalhes essenciais do lugar (name + geometry)
    final locationResult = await placeService.getPlaceDetails(
      placeId: placeId,
      languageCode: localizationItem.languageCode,
    );

    if (locationResult != null && locationResult.latLng != null) {
      final location = locationResult.latLng!;

      // Localização via busca = endereço exato (não aproximado)
      locationResult.isApproximateLocation = false;
      
      // Salvar resultado completo sem fazer reverse geocode
      _locationResult = locationResult;
      setMarker(location);

      // Fotos do Google Places desativadas (custo). Mantemos lista vazia.
      _selectedPlacePhotos = [];
      notifyListeners();
      return location;
    }

    return null;
  }

  // -------------------------------------------------------------
  //  LOADERS
  // -------------------------------------------------------------

  Future<void> _loadReverseGeocode(LatLng location) async {
    final result = await placeService.reverseGeocode(
      location: location,
      languageCode: localizationItem.languageCode,
    );

    if (result != null) {
      // Marcar como localização aproximada (selecionada via mapa, não via busca)
      // Isso evita mostrar endereço exato no EventCard
      result.isApproximateLocation = true;
      _locationResult = result;
    }
  }

  // -------------------------------------------------------------
  //  UTIL
  // -------------------------------------------------------------

  void clearSearch() {
    _hasSearchTerm = false;
    _suggestions = [];
    _previousSearchTerm = '';
    notifyListeners();
  }

  void clearPhotos() {
    _selectedPlacePhotos = [];
    notifyListeners();
  }

  /// Atualiza o locationResult diretamente (usado ao restaurar estado salvo)
  void updateLocationResult(LocationResult location) {
    _locationResult = location;
    if (location.latLng != null) {
      setMarker(location.latLng!);
    }
    if (location.placeId != null) {
      _isLocationConfirmed = true;
    }
    notifyListeners();
  }

  void unlockLocation() {
    _lockOnSelectedPlace = false;
    _isLocationConfirmed = false; // remove confirmação ao mover mapa manualmente
    notifyListeners();
  }

  /// Confirma a localização atual (para uso com interação direta no mapa)
  void confirmCurrentLocation() {
    if (_selectedLocation != null) {
      _isLocationConfirmed = true;
      notifyListeners();
    }
  }

  String getLocationName() {
    if (_locationResult == null) {
      return localizationItem.unnamedLocation;
    }

    final result = _locationResult!;

    if (result.name != null && result.name!.isNotEmpty) {
      return result.name!;
    }

    if (result.locality != null && result.locality!.isNotEmpty) {
      return result.locality!;
    }

    return result.formattedAddress ?? localizationItem.unnamedLocation;
  }

  bool _isSameCoord(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 0.00001 &&
        (a.longitude - b.longitude).abs() < 0.00001;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    placeService.dispose();
    super.dispose();
  }
}
