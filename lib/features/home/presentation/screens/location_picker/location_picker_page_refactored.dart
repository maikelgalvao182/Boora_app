import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/core/services/google_maps_config_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/location_picker_controller.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/location_picker_map.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/place_service.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/widgets/location_search_bar.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/widgets/location_suggestions_overlay.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/widgets/map_center_pin.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/widgets/meeting_point_info_card.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/widgets/nearby_places_carousel.dart';
import 'package:partiu/features/home/presentation/widgets/schedule_drawer.dart';
import 'package:partiu/plugins/locationpicker/entities/localization_item.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';

/// Location picker refatorado e modularizado
class LocationPickerPageRefactored extends StatefulWidget {
  const LocationPickerPageRefactored({
    super.key,
    this.displayLocation,
    this.localizationItem,
    this.defaultLocation = const LatLng(-23.5505, -46.6333), // São Paulo
    this.coordinator,
  });

  final LatLng? displayLocation;
  final LocalizationItem? localizationItem;
  final LatLng defaultLocation;
  final CreateFlowCoordinator? coordinator;

  @override
  State<LocationPickerPageRefactored> createState() => _LocationPickerPageRefactoredState();
}

class _LocationPickerPageRefactoredState extends State<LocationPickerPageRefactored> {
  late final String _apiKey;

  late LocationPickerController _controller;
  final GlobalKey<LocationPickerMapState> _mapKey = GlobalKey();
  final GlobalKey _searchBarKey = GlobalKey();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isLoadingMap = true;
  bool _isInitializing = true;
  OverlayEntry? _overlayEntry;
  bool _isProgrammaticMove = false; // Flag para indicar movimento programático do mapa

  @override
  void initState() {
    super.initState();
    debugPrint('🟢 [LocationPicker] initState');
    _initializeAsync();
  }

  Future<void> _initializeAsync() async {
    try {
      // Carregar API key do Firebase
      final configService = GoogleMapsConfigService();
      _apiKey = await configService.getGoogleMapsApiKey();
      debugPrint('✅ [LocationPicker] API Key carregada: ${_apiKey.substring(0, 10)}...');

      _controller = LocationPickerController(
        placeService: PlaceService(apiKey: _apiKey),
        localizationItem: widget.localizationItem ?? LocalizationItem(),
        initialLocation: widget.displayLocation ?? widget.defaultLocation,
      );

      _controller.addListener(_onControllerChanged);

      if (mounted) {
        debugPrint('✅ [LocationPicker] Controller pronto, mostrando mapa');
        setState(() {
          _isInitializing = false;
          _isLoadingMap = false;
        });
        
        // Carregar localização após mapa estar visível
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            debugPrint('🟢 [LocationPicker] Timeout - carregando localização');
            _loadInitialLocation();
          }
        });
      }
    } catch (e, stack) {
      debugPrint('❌ [LocationPicker] Erro ao inicializar: $e');
      debugPrint('Stack: $stack');
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    debugPrint('🔴 [LocationPicker] dispose iniciado');
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _overlayEntry?.remove();
    _searchController.dispose();
    _searchFocusNode.dispose();
    debugPrint('✅ [LocationPicker] dispose concluído');
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Carrega localização inicial
  Future<void> _loadInitialLocation() async {
    debugPrint('📍 [LocationPicker] Carregando localização inicial');

    final LatLng target = widget.displayLocation ?? await _getCurrentLocation();
    debugPrint('📍 [LocationPicker] Localização inicial: $target');

    // Aguardar um pouco para garantir que o mapa está pronto
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    // PRIMEIRO: mover a câmera (instantâneo)
    final mapState = _mapKey.currentState;
    if (mapState != null && mapState.controller != null) {
      debugPrint('📍 [LocationPicker] Movendo câmera do mapa...');
      _isProgrammaticMove = true;
      mapState.setInitialCamera(target);
      Future.delayed(const Duration(milliseconds: 500), () {
        _isProgrammaticMove = false;
      });
    } else {
      debugPrint('⚠️ [LocationPicker] Mapa ainda não está pronto, aguardando...');
      // Tentar novamente após 500ms
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted && _mapKey.currentState != null) {
        _mapKey.currentState?.setInitialCamera(target);
      }
    }

    // DEPOIS: reverse + nearby em background (sem await)
    unawaited(_controller.moveToLocation(target, loadNearby: true));
  }

  /// Obtém localização atual do dispositivo
  Future<LatLng> _getCurrentLocation() async {
    try {
      debugPrint('📍 [LocationPicker] Obtendo localização atual...');
      
      // Tentar última localização conhecida primeiro
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        debugPrint('✅ [LocationPicker] Última localização conhecida: $lastKnown');
        return LatLng(lastKnown.latitude, lastKnown.longitude);
      }

      // Verificar serviço e permissões
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('⚠️ [LocationPicker] Serviço de localização desabilitado');
        return widget.defaultLocation;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('⚠️ [LocationPicker] Permissão de localização negada');
        return widget.defaultLocation;
      }

      // Obter posição atual
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 2),
        ),
      ).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('⏰ [LocationPicker] Timeout ao obter localização');
          throw TimeoutException('Location timeout');
        },
      );

      debugPrint('✅ [LocationPicker] Localização atual obtida: $position');
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('❌ [LocationPicker] Erro ao obter localização: $e');
      return widget.defaultLocation;
    }
  }

  /// Callback quando mapa é criado
  void _onMapCreated(GoogleMapController controller) async {
    debugPrint('🗺️ [LocationPicker] onMapCreated disparado!');
    // Mapa criado com sucesso - não precisa fazer nada
    // A localização já será carregada pelo timeout no _initializeAsync
  }

  /// Callback quando usuário toca no mapa - não usado com pin fixo
  void _onMapTap(LatLng location) {
    _clearOverlay();
    FocusScope.of(context).unfocus();
  }

  /// Atualiza localização selecionada baseado no centro do mapa
  void _updateLocationFromMapCenter() async {
    final mapState = _mapKey.currentState;
    if (mapState == null) return;

    final controller = mapState.controller;
    if (controller == null) return;

    final region = await controller.getVisibleRegion();
    final center = LatLng(
      (region.northeast.latitude + region.southwest.latitude) / 2,
      (region.northeast.longitude + region.southwest.longitude) / 2,
    );

    await _controller.moveToLocation(center, loadNearby: false);
  }

  /// Callback quando usuário digita na busca
  void _onSearchChanged(String query) {
    _controller.clearSearch();

    if (query.isEmpty) {
      _clearOverlay();
      return;
    }

    _showLoadingOverlay();
    _controller.searchPlace(query).then((_) {
      if (_controller.suggestions.isNotEmpty) {
        _showSuggestionsOverlay();
      } else {
        _clearOverlay();
      }
    });
  }

  /// Callback quando usuário seleciona uma sugestão
  Future<void> _onSuggestionTap(String placeId, String placeName) async {
    debugPrint('👆 [LocationPicker] _onSuggestionTap: $placeName');
    FocusScope.of(context).unfocus();
    _clearOverlay();
    
    // Atualizar input com o nome do lugar selecionado
    _searchController.text = placeName;
    debugPrint('✏️ [LocationPicker] Input atualizado com: $placeName');

    final location = await _controller.selectPlaceFromSuggestion(placeId);
    debugPrint('📍 [LocationPicker] Localização retornada: $location');
    if (location != null) {
      _isProgrammaticMove = true; // Marcar como movimento programático
      _mapKey.currentState?.animateToLocation(location);
      // Resetar flag após animação (com delay)
      Future.delayed(const Duration(milliseconds: 1500), () {
        _isProgrammaticMove = false;
      });
    }
  }

  /// Mostra overlay de loading
  void _showLoadingOverlay() {
    _clearOverlay();

    final searchBarBox = _searchBarKey.currentContext?.findRenderObject() as RenderBox?;
    final searchBarPosition = searchBarBox?.localToGlobal(Offset.zero);
    final top = (searchBarPosition?.dy ?? 0) + (searchBarBox?.size.height ?? 0) + 8;

    _overlayEntry = OverlayEntry(
      builder: (context) => LocationSearchLoadingOverlay(
        message: _controller.localizationItem.findingPlace,
        top: top,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Mostra overlay com sugestões
  void _showSuggestionsOverlay() {
    _clearOverlay();

    final searchBarBox = _searchBarKey.currentContext?.findRenderObject() as RenderBox?;
    final searchBarPosition = searchBarBox?.localToGlobal(Offset.zero);
    final top = (searchBarPosition?.dy ?? 0) + (searchBarBox?.size.height ?? 0) + 8;

    final suggestions = _controller.suggestions
        .map((s) => s.autoCompleteItem)
        .toList();

    _overlayEntry = OverlayEntry(
      builder: (context) => LocationSuggestionsOverlay(
        suggestions: suggestions,
        onTap: (placeId, placeName) => _onSuggestionTap(placeId, placeName),
        top: top,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Remove overlay
  void _clearOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    debugPrint('🎨 [LocationPicker] build - _isLoadingMap: $_isLoadingMap, _isInitializing: $_isInitializing');
    debugPrint('🟢 [LocationPicker] isLocationConfirmed: ${_controller.isLocationConfirmed}, selectedLocation: ${_controller.selectedLocation}');
    
    // Se ainda está inicializando, mostrar loading
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CupertinoActivityIndicator(radius: 16),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Mapa ocupando toda a tela
          LocationPickerMap(
            key: _mapKey,
            initialLocation: _controller.currentLocation ?? widget.defaultLocation,
            selectedLocation: _controller.selectedLocation,
            markers: const {}, // Sem markers, usamos pin fixo
            onMapCreated: _onMapCreated,
            onTap: _onMapTap,
            onCameraIdle: () {
              if (_controller.isLocked) return;
              _updateLocationFromMapCenter();
            },
            onCameraMoveStarted: () {
              // Só desbloquear se for movimento manual (não programático)
              if (!_isProgrammaticMove) {
                debugPrint('🔓 [LocationPicker] Movimento manual detectado - desbloqueando');
                _controller.unlockLocation();
              } else {
                debugPrint('🤖 [LocationPicker] Movimento programático - mantendo bloqueio');
              }
            },
          ),

          // Pin personalizado no centro
          const Center(
            child: MapCenterPin(),
          ),

          // Widget flutuante no topo com busca
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Column(
              key: _searchBarKey,
              children: [
                // Barra de busca
                LocationSearchBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  onBack: () => Navigator.of(context).pop(),
                  onClose: () => Navigator.of(context).pop(),
                ),

                const SizedBox(height: 12),

                // Card informativo
                const MeetingPointInfoCard(),

                // Carousel de fotos do lugar selecionado
                if (_controller.selectedPlacePhotos.isNotEmpty)
                  SelectedPlacePhotosCarousel(
                    photoUrls: _controller.selectedPlacePhotos, // Já são URLs reais
                    placeName: _controller.getLocationName(),
                  ),
              ],
            ),
          ),

          // Botão fixo no rodapé
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            child: GlimpseButton(
              text: i18n.translate('set_activity_location'),
              onPressed: _controller.selectedLocation != null && _controller.isLocationConfirmed
                  ? () async {
                      // Salvar localização no coordinator
                      if (widget.coordinator != null && _controller.locationResult != null) {
                        widget.coordinator!.setLocation(
                          _controller.locationResult!,
                          photoReferences: _controller.selectedPlacePhotos,
                        );
                      }

                      // Abrir drawer de agendamento
                      final scheduleResult = await showModalBottomSheet<Map<String, dynamic>>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => ScheduleDrawer(
                          coordinator: widget.coordinator,
                        ),
                      );

                      if (scheduleResult != null && mounted) {
                        // Retornar resultado completo com location + schedule
                        final result = {
                          'location': _controller.locationResult,
                          'schedule': scheduleResult,
                        };
                        Navigator.of(context).pop(result);
                      }
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
