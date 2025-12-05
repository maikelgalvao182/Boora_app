import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/presentation/services/google_event_marker_service.dart';
import 'package:partiu/features/home/presentation/viewmodels/apple_map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/screens/chat/chat_screen_refactored.dart';

/// Widget de mapa Google Maps limpo e performático
/// 
/// Responsabilidades:
/// - Renderizar o Google Map
/// - Exibir localização do usuário
/// - Exibir markers (delegado ao ViewModel)
/// - Controlar câmera
/// 
/// Toda lógica de negócio foi extraída para:
/// - AppleMapViewModel (orquestração) - Reutilizado!
/// - EventMarkerService (markers)
/// - UserLocationService (localização)
/// - AvatarService (avatares)
class GoogleMapView extends StatefulWidget {
  final AppleMapViewModel viewModel;

  const GoogleMapView({
    super.key,
    required this.viewModel,
  });

  @override
  State<GoogleMapView> createState() => GoogleMapViewState();
}

class GoogleMapViewState extends State<GoogleMapView> {
  /// Controller do mapa Google Maps
  GoogleMapController? _mapController;
  
  /// Serviço para gerar markers customizados
  final GoogleEventMarkerService _markerService = GoogleEventMarkerService();
  
  /// Markers atuais do mapa
  Set<Marker> _markers = {};
  
  /// Estilo customizado do mapa carregado de assets
  String? _mapStyle;

  /// Método público para centralizar no usuário
  void centerOnUser() {
    _moveCameraToUserLocation();
  }

  @override
  void initState() {
    super.initState();
    
    // Carregar estilo do mapa de assets
    _loadMapStyle();
    
    // Pré-carregar pins padrão
    _markerService.preloadDefaultPins();
    
    // Configurar callback de tap no ViewModel recebido
    debugPrint('🔴 GoogleMapView: Configurando callback onMarkerTap');
    widget.viewModel.onMarkerTap = _onMarkerTap;
    debugPrint('🔴 GoogleMapView: Callback configurado? ${widget.viewModel.onMarkerTap != null}');
    
    // Listener para regenerar markers quando eventos mudarem
    widget.viewModel.addListener(_onEventsChanged);
    
    // Agora que o callback está configurado, carregar eventos
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('🔴 GoogleMapView: Carregando eventos APÓS callback configurado');
      widget.viewModel.loadNearbyEvents();
    });
  }
  
  /// Carrega o estilo do mapa de assets
  Future<void> _loadMapStyle() async {
    try {
      _mapStyle = await rootBundle.loadString('assets/map_styles/clean.json');
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar estilo do mapa: $e');
    }
  }
  
  /// Callback quando eventos mudarem
  void _onEventsChanged() async {
    if (!mounted) return;
    
    debugPrint('🗺️ GoogleMapView: Regenerando ${widget.viewModel.events.length} markers');
    
    // Gerar markers customizados
    final markers = await _markerService.buildEventMarkers(
      widget.viewModel.events,
      onTap: (eventId) {
        final event = widget.viewModel.events.firstWhere((e) => e.id == eventId);
        _onMarkerTap(event);
      },
    );
    
    if (mounted) {
      setState(() {
        _markers = markers;
      });
    }
  }

  /// Callback quando o mapa é criado
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    
    // Aplicar estilo customizado ao mapa se já foi carregado
    if (_mapStyle != null) {
      _mapController?.setMapStyle(_mapStyle);
    }

    // Mover câmera para localização inicial (já carregada)
    if (widget.viewModel.lastLocation != null) {
      _moveCameraTo(
        widget.viewModel.lastLocation!.latitude,
        widget.viewModel.lastLocation!.longitude,
        zoom: 15.0,
      );
    } else {
      _moveCameraToUserLocation();
    }
  }

  /// Move a câmera para a localização do usuário
  Future<void> _moveCameraToUserLocation() async {
    final result = await widget.viewModel.getUserLocation();

    // Exibir mensagem de erro se houver
    if (result.hasError && mounted) {
      _showMessage(result.errorMessage!);
    }

    // Mover câmera
    await _moveCameraTo(
      result.location.latitude,
      result.location.longitude,
      zoom: 15.0,
    );
  }

  /// Move a câmera para uma coordenada específica
  Future<void> _moveCameraTo(
    double lat,
    double lng, {
    double zoom = 14.0,
  }) async {
    if (_mapController == null) return;

    try {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(lat, lng),
            zoom: zoom,
          ),
        ),
      );
    } catch (e) {
      // Falha silenciosa - câmera continua onde está
    }
  }

  /// Exibe mensagem para o usuário
  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Callback quando usuário toca em um marker
  void _onMarkerTap(EventModel event) {
    debugPrint('🔴 GoogleMapView._onMarkerTap called for: ${event.id} - ${event.title}');
    
    // Criar controller com evento pré-carregado (evita query Firestore)
    final controller = EventCardController(
      eventId: event.id,
      preloadedEvent: event,
    );
    
    debugPrint('🔴 Controller criado, iniciando load()');
    // Iniciar carregamento dos dados adicionais em background
    controller.load();
    
    debugPrint('🔴 Abrindo showModalBottomSheet');
    // Abrir o card imediatamente (sem aguardar load)
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(
        maxWidth: 500,
      ),
      builder: (context) => EventCard(
        controller: controller,
        onActionPressed: () async {
          // Capturar o navigator antes de fechar o modal
          final navigator = Navigator.of(context);
          
          // Fechar o card
          navigator.pop();
          
          // Se for o criador ou estiver aprovado, navegar para o chat
          if (controller.isCreator || controller.isApproved) {
            // Usar dados do evento pré-carregado
            final eventName = event.title;
            final emoji = event.emoji;
            
            // Criar User com dados do evento usando campos corretos do SessionManager
            final chatUser = User.fromDocument({
              'userId': 'event_${event.id}',
              'fullName': eventName,
              'profilePhotoUrl': emoji,
              'gender': '',
              'birthDay': 1,
              'birthMonth': 1,
              'birthYear': 2000,
              'jobTitle': '',
              'bio': '',
              'country': '',
              'locality': '',
              'latitude': 0.0,
              'longitude': 0.0,
              'status': 'active',
              'level': '',
              'isVerified': false,
              'registrationDate': DateTime.now().toIso8601String(),
              'lastLoginDate': DateTime.now().toIso8601String(),
              'totalLikes': 0,
              'totalVisits': 0,
              'isOnline': false,
            });
            
            // Usar o navigator capturado anteriormente
            navigator.push(
              MaterialPageRoute(
                builder: (context) => ChatScreenRefactored(
                  user: chatUser,
                  isEvent: true,
                  eventId: event.id,
                ),
              ),
            );
          }
        },
      ),
    ).whenComplete(() {
      // Garantir limpeza do controller ao fechar o modal
      controller.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Widget limpo - apenas UI
    // Toda lógica delegada ao ViewModel
    return GoogleMap(
      // Callback de criação
      onMapCreated: _onMapCreated,

      // Posição inicial (São Paulo)
      initialCameraPosition: const CameraPosition(
        target: LatLng(-23.5505, -46.6333),
        zoom: 12.0,
      ),
      
      // Aumentar zoom máximo para mostrar mais detalhes das ruas
      minMaxZoomPreference: const MinMaxZoomPreference(9.0, 40.0),

      // Markers customizados gerados pelo GoogleEventMarkerService
      markers: _markers,

      // Configurações do mapa
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      mapType: MapType.normal,
      compassEnabled: true,
      rotateGesturesEnabled: true,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      tiltGesturesEnabled: false,
    );
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onEventsChanged);
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }
}
