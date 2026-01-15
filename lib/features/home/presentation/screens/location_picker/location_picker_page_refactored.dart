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
import 'package:partiu/features/home/presentation/widgets/participants_drawer.dart';
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

  bool _isInitializing = true;
  OverlayEntry? _overlayEntry;
  bool _isProgrammaticMove = false; // Flag para indicar movimento programático do mapa
  bool _isUpdatingSearchText = false; // Flag para ignorar onChange programático

  @override
  void initState() {
    super.initState();
    _initializeAsync();
  }

  Future<void> _initializeAsync() async {
    try {
      // Carregar API key local (constants.dart)
      final configService = GoogleMapsConfigService();
      _apiKey = await configService.getGooglePlacesApiKey();

      _controller = LocationPickerController(
        placeService: PlaceService(apiKey: _apiKey),
        localizationItem: widget.localizationItem ?? LocalizationItem(),
        initialLocation: widget.displayLocation ?? widget.defaultLocation,
      );

      _controller.addListener(_onControllerChanged);

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        
        // Carregar localização após mapa estar visível
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            _loadInitialLocation();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _overlayEntry?.remove();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Carrega localização inicial
  Future<void> _loadInitialLocation() async {
    LatLng target;
    
    // Prioridade: 1. displayLocation, 2. coordinator.draft.location, 3. localização atual
    if (widget.displayLocation != null) {
      target = widget.displayLocation!;
    } else if (widget.coordinator?.draft.location?.latLng != null) {
      target = widget.coordinator!.draft.location!.latLng!;
      // Atualizar o controller com a localização salva
      _controller.updateLocationResult(widget.coordinator!.draft.location!);
      // Atualizar o campo de busca com o nome/endereço
      final savedLocation = widget.coordinator!.draft.location!;
      final searchText = savedLocation.name ?? savedLocation.formattedAddress ?? '';
      if (searchText.isNotEmpty) {
        _isUpdatingSearchText = true;
        _searchController.text = searchText;
        _isUpdatingSearchText = false;
      }
    } else {
      target = await _getCurrentLocation();
    }

    // Aguardar um pouco para garantir que o mapa está pronto
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    // PRIMEIRO: mover a câmera (instantâneo)
    final mapState = _mapKey.currentState;
    if (mapState != null && mapState.controller != null) {
      _isProgrammaticMove = true;
      mapState.setInitialCamera(target);
      Future.delayed(const Duration(milliseconds: 500), () {
        _isProgrammaticMove = false;
      });
    } else {
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
      // Tentar última localização conhecida primeiro
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return LatLng(lastKnown.latitude, lastKnown.longitude);
      }

      // Verificar serviço e permissões
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return widget.defaultLocation;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
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
          throw TimeoutException('Location timeout');
        },
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      return widget.defaultLocation;
    }
  }

  /// Callback quando mapa é criado
  void _onMapCreated(GoogleMapController controller) async {
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
    // Ignorar se estamos atualizando o texto programaticamente
    if (_isUpdatingSearchText) return;
    
    // Ignorar se a localização já foi confirmada (usuário selecionou do dropdown)
    if (_controller.isLocationConfirmed) {
      _clearOverlay();
      return;
    }

    if (query.isEmpty) {
      _controller.clearSearch();
      _clearOverlay();
      return;
    }

    _showLoadingOverlay();
    _controller.searchPlace(query).then((_) {
      // Verificar novamente se não foi confirmado durante a busca
      if (_controller.isLocationConfirmed) {
        _clearOverlay();
        return;
      }
      
      if (_controller.suggestions.isNotEmpty) {
        _showSuggestionsOverlay();
      } else {
        _clearOverlay();
      }
    });
  }

  /// Callback quando usuário seleciona uma sugestão
  Future<void> _onSuggestionTap(String placeId, String placeName) async {
    FocusScope.of(context).unfocus();
    _clearOverlay();
    
    // Atualizar input com o nome do lugar selecionado (sem disparar onChange)
    _isUpdatingSearchText = true;
    _searchController.text = placeName;
    
    // Limpar sugestões para evitar re-exibição do overlay
    _controller.clearSearch();

    final location = await _controller.selectPlaceFromSuggestion(placeId);
    
    // Resetar flag após operação completa
    _isUpdatingSearchText = false;
    
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
    if (searchBarBox == null) return;
    final searchBarPosition = searchBarBox.localToGlobal(Offset.zero);
    final top = searchBarPosition.dy + searchBarBox.size.height + 8;

    _overlayEntry = OverlayEntry(
      builder: (context) => LocationSearchLoadingOverlay(
        message: _controller.localizationItem.findingPlace,
        top: top,
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  /// Mostra overlay com sugestões
  void _showSuggestionsOverlay() {
    _clearOverlay();

    final searchBarBox = _searchBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (searchBarBox == null) return;
    final searchBarPosition = searchBarBox.localToGlobal(Offset.zero);
    final top = searchBarPosition.dy + searchBarBox.size.height + 8;

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

    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  /// Remove overlay
  void _clearOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
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
                _controller.unlockLocation();
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
              children: [
                // Barra de busca
                KeyedSubtree(
                  key: _searchBarKey,
                  child: LocationSearchBar(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _onSearchChanged,
                    onBack: () => Navigator.of(context).pop({'action': 'back'}), // Volta para ScheduleDrawer
                    onClose: () {
                      // Limpar o campo de busca e resetar seleção
                      _isUpdatingSearchText = true; // Evitar que onChange seja disparado durante clear
                      _searchController.clear();
                      _isUpdatingSearchText = false;
                      _clearOverlay();
                      _controller.clearSearch(); // Limpa _previousSearchTerm para permitir nova busca
                      _controller.unlockLocation(); // Isso limpa isLocationConfirmed e permite nova busca
                      _controller.clearPhotos(); // Limpa as fotos do carousel
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ),

                const SizedBox(height: 12),

                // Card informativo
                const MeetingPointInfoCard(),
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
                        );
                      }

                      final navigator = Navigator.of(context);

                      // Abrir drawer de participantes (último passo)
                      final participantsResult = await showModalBottomSheet<Map<String, dynamic>>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => ParticipantsDrawer(
                          coordinator: widget.coordinator,
                        ),
                      );

                      if (!context.mounted) return;

                      if (participantsResult != null) {
                        // Retornar resultado completo com location + participants
                        final result = {
                          'location': _controller.locationResult,
                          'participants': participantsResult,
                        };
                        navigator.pop(result);
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
