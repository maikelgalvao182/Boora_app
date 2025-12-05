import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:partiu/features/home/data/services/map_discovery_service.dart';
import 'package:partiu/features/home/presentation/services/google_event_marker_service.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
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
/// - MapViewModel (orquestração)
/// - EventMarkerService (markers)
/// - UserLocationService (localização)
/// - AvatarService (avatares)
class GoogleMapView extends StatefulWidget {
  final MapViewModel viewModel;

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
  
  /// Serviço para descoberta de eventos por bounding box
  final MapDiscoveryService _discoveryService = MapDiscoveryService();
  
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
    
    // Configurar callback de tap no ViewModel recebido
    debugPrint('🔴 GoogleMapView: Configurando callback onMarkerTap');
    widget.viewModel.onMarkerTap = _onMarkerTap;
    debugPrint('🔴 GoogleMapView: Callback configurado? ${widget.viewModel.onMarkerTap != null}');
    
    // Listener para atualizar markers quando eventos mudarem
    widget.viewModel.addListener(_onEventsChanged);
    
    // Verificar se eventos e markers já foram pré-carregados pelo AppInitializerService
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.viewModel.events.isEmpty && !widget.viewModel.isLoading) {
        debugPrint('🔴 GoogleMapView: Nenhum evento pré-carregado, carregando agora...');
        widget.viewModel.loadNearbyEvents();
      } else {
        debugPrint('✅ GoogleMapView: ${widget.viewModel.events.length} eventos já pré-carregados!');
        debugPrint('✅ GoogleMapView: ${widget.viewModel.googleMarkers.length} markers já pré-carregados!');
        // Usar markers pré-carregados
        _onEventsChanged();
      }
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
    
    final stopwatch = Stopwatch()..start();
    
    // Usar markers pré-carregados do ViewModel SE existirem
    if (widget.viewModel.googleMarkers.isNotEmpty) {
      debugPrint('⚡ GoogleMapView: Usando ${widget.viewModel.googleMarkers.length} markers PRÉ-CARREGADOS (cache)');
      
      // RECONSTRUIR markers com callback correto
      final Set<Marker> markersWithCallback = {};
      
      for (final marker in widget.viewModel.googleMarkers) {
        // Extrair eventId do markerId (formato: 'event_emoji_ID' ou 'event_avatar_ID')
        final markerId = marker.markerId.value;
        final eventId = markerId.replaceAll('event_emoji_', '').replaceAll('event_avatar_', '');
        
        // Recriar marker com callback
        markersWithCallback.add(
          marker.copyWith(
            onTapParam: () {
              debugPrint('🎯 Marker callback acionado para eventId: $eventId');
              final event = widget.viewModel.events.firstWhere((e) => e.id == eventId);
              debugPrint('🎯 Evento encontrado: ${event.title}');
              _onMarkerTap(event);
            },
          ),
        );
      }
      
      if (mounted) {
        setState(() {
          _markers = markersWithCallback;
        });
        stopwatch.stop();
        debugPrint('✅ GoogleMapView: ${_markers.length} markers atualizados com callback em ${stopwatch.elapsedMilliseconds}ms');
      }
      return;
    }
    
    // Fallback: gerar markers do zero (só acontece se AppInitializer falhou)
    debugPrint('⚠️ GoogleMapView: Gerando ${widget.viewModel.events.length} markers do ZERO (fallback)');
    
    final markers = await _markerService.buildEventMarkers(
      widget.viewModel.events,
      onTap: (eventId) {
        debugPrint('🎯 Marker callback acionado para eventId: $eventId');
        final event = widget.viewModel.events.firstWhere((e) => e.id == eventId);
        debugPrint('🎯 Evento encontrado: ${event.title}');
        _onMarkerTap(event);
      },
    );
    
    if (mounted) {
      setState(() {
        _markers = markers;
      });
      stopwatch.stop();
      debugPrint('✅ GoogleMapView: ${_markers.length} markers gerados em ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  /// Callback quando o mapa é criado
  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    
    // Aplicar estilo customizado ao mapa se já foi carregado
    if (_mapStyle != null) {
      _mapController?.setMapStyle(_mapStyle);
    }

    // Mover câmera para localização inicial (já carregada)
    if (widget.viewModel.lastLocation != null) {
      await _moveCameraTo(
        widget.viewModel.lastLocation!.latitude,
        widget.viewModel.lastLocation!.longitude,
        zoom: 15.0,
      );
    } else {
      await _moveCameraToUserLocation();
    }

    // Fazer busca inicial de eventos na região visível
    // Isso garante que o drawer tenha dados logo ao abrir
    await _triggerInitialEventSearch();
  }

  /// Callback quando a câmera para de se mover
  /// 
  /// Captura o bounding box visível e busca eventos na região.
  Future<void> _onCameraIdle() async {
    if (_mapController == null) return;

    try {
      final visibleRegion = await _mapController!.getVisibleRegion();
      
      final bounds = MapBounds.fromLatLngBounds(visibleRegion);
      
      debugPrint('📍 GoogleMapView: Câmera parou em $bounds');
      
      // Disparar busca de eventos no bounding box
      await _discoveryService.loadEventsInBounds(bounds);
    } catch (error) {
      debugPrint('⚠️ GoogleMapView: Erro ao capturar bounding box: $error');
    }
  }

  /// Faz busca inicial de eventos na região visível
  /// 
  /// Chamado logo após o mapa ser criado para garantir
  /// que o drawer tenha dados ao abrir pela primeira vez.
  Future<void> _triggerInitialEventSearch() async {
    if (_mapController == null) return;

    try {
      // Pequeno delay para garantir que o mapa terminou de carregar
      await Future.delayed(const Duration(milliseconds: 500));
      
      final visibleRegion = await _mapController!.getVisibleRegion();
      final bounds = MapBounds.fromLatLngBounds(visibleRegion);
      
      debugPrint('🎯 GoogleMapView: Busca inicial de eventos em $bounds');
      
      // Forçar busca imediata (ignora debounce)
      await _discoveryService.forceRefresh(bounds);
    } catch (error) {
      debugPrint('⚠️ GoogleMapView: Erro na busca inicial: $error');
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
    debugPrint('🔴🔴🔴 GoogleMapView._onMarkerTap CHAMADO! 🔴🔴🔴');
    debugPrint('🔴 GoogleMapView._onMarkerTap called for: ${event.id} - ${event.title}');
    debugPrint('📦 EventModel pré-carregado:');
    debugPrint('   - locationName: ${event.locationName}');
    debugPrint('   - privacyType: ${event.privacyType}');
    debugPrint('   - creatorFullName: ${event.creatorFullName}');
    debugPrint('   - scheduleDate: ${event.scheduleDate}');
    debugPrint('   - userApplication: ${event.userApplication?.status.value}');
    debugPrint('   - participants: ${event.participants?.length ?? 0}');
    
    // Criar controller com evento pré-carregado (evita query Firestore)
    final controller = EventCardController(
      eventId: event.id,
      preloadedEvent: event,
    );
    
    debugPrint('🔴 Controller criado com dados pré-carregados');
    
    // NÃO chamar load() aqui - deixar o EventCard chamar quando necessário
    // O controller já tem todos os dados essenciais via preloadedEvent
    
    debugPrint('🔴 Abrindo showModalBottomSheet');
    // Abrir o card imediatamente
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

      // Callback quando câmera para (após movimento)
      onCameraIdle: _onCameraIdle,

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
