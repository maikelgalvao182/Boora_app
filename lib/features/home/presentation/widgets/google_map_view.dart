import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/core/models/user.dart' as app_user;
import 'package:partiu/core/services/block_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:partiu/features/home/data/services/map_discovery_service.dart';
import 'package:partiu/features/home/presentation/services/google_event_marker_service.dart';
import 'package:partiu/features/home/presentation/services/map_navigation_service.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/screens/chat/chat_screen_refactored.dart';

/// Widget de mapa Google Maps limpo e performático
/// 
/// Responsabilidades:
/// - Renderizar o Google Map
/// - Exibir localização do usuário
/// - Exibir markers com clustering inteligente baseado em zoom
/// - Controlar câmera
/// 
/// Clustering:
/// - Zoom alto (>= 16): Markers individuais (emoji + avatar)
/// - Zoom médio (12-15): Clustering moderado
/// - Zoom baixo (< 12): Clustering agressivo
/// - Ao tocar em cluster: zoom in para expandir
/// 
/// Toda lógica de negócio foi extraída para:
/// - MapViewModel (orquestração)
/// - EventMarkerService (markers + clustering)
/// - UserLocationService (localização)
/// - AvatarService (avatares)
/// - MarkerClusterService (algoritmo de clustering)
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
  
  /// Serviço para gerar markers customizados (com clustering)
  final GoogleEventMarkerService _markerService = GoogleEventMarkerService();
  
  /// Serviço para descoberta de eventos por bounding box
  final MapDiscoveryService _discoveryService = MapDiscoveryService();
  
  /// Markers atuais do mapa (clusterizados)
  Set<Marker> _markers = {};
  
  /// Estilo customizado do mapa carregado de assets
  String? _mapStyle;
  
  /// Zoom atual do mapa (usado para clustering)
  double _currentZoom = 12.0;
  
  /// Flag para evitar rebuilds durante animação de câmera
  bool _isAnimating = false;

  /// Método público para centralizar no usuário
  void centerOnUser() {
    _moveCameraToUserLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    debugPrint('🗺️ GoogleMapView didChangeDependencies → registrando handler');

    MapNavigationService.instance.registerMapHandler((eventId) {
      debugPrint('📍 GoogleMapView recebeu navegação: $eventId');
      _handleEventNavigation(eventId);
    });
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
    
    // Registrar handler de navegação no MapNavigationService
    MapNavigationService.instance.registerMapHandler(_handleEventNavigation);
    debugPrint('🗺️ GoogleMapView: Handler de navegação registrado');
    
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
  /// 
  /// Recalcula clusters baseado no zoom atual
  void _onEventsChanged() async {
    if (!mounted || _isAnimating) return;
    
    await _rebuildClusteredMarkers();
  }

  /// Reconstrói markers com clustering baseado no zoom atual
  /// 
  /// Este método é chamado:
  /// - Quando eventos mudam (listener do ViewModel)
  /// - Quando zoom muda (onCameraIdle)
  Future<void> _rebuildClusteredMarkers() async {
    if (!mounted || widget.viewModel.events.isEmpty) return;
    
    final stopwatch = Stopwatch()..start();
    
    debugPrint('🔲 GoogleMapView: Reconstruindo markers com clustering (zoom: ${_currentZoom.toStringAsFixed(1)})');
    
    // Gerar markers clusterizados
    final markers = await _markerService.buildClusteredMarkers(
      widget.viewModel.events,
      zoom: _currentZoom,
      onSingleTap: (eventId) {
        debugPrint('🎯 Marker individual tocado: $eventId');
        final event = widget.viewModel.events.firstWhere((e) => e.id == eventId);
        _onMarkerTap(event);
      },
      onClusterTap: (eventsInCluster) {
        debugPrint('🔴 Cluster tocado: ${eventsInCluster.length} eventos');
        _onClusterTap(eventsInCluster);
      },
    );
    
    if (mounted) {
      setState(() {
        _markers = markers;
      });
      stopwatch.stop();
      debugPrint('✅ GoogleMapView: ${_markers.length} markers clusterizados em ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  /// Callback quando cluster é tocado
  /// 
  /// Comportamento:
  /// - Zoom in para expandir o cluster
  /// - Se zoom já alto, mostra lista de eventos
  void _onClusterTap(List<EventModel> eventsInCluster) async {
    if (_mapController == null || eventsInCluster.isEmpty) return;
    
    // Se zoom já está alto (>= 16), não faz sentido dar mais zoom
    // Mostrar lista de eventos ou o primeiro evento
    if (_currentZoom >= 16) {
      debugPrint('📍 Cluster tocado em zoom alto - mostrando primeiro evento');
      _onMarkerTap(eventsInCluster.first);
      return;
    }
    
    // Calcular centro do cluster
    double avgLat = 0;
    double avgLng = 0;
    for (final event in eventsInCluster) {
      avgLat += event.lat;
      avgLng += event.lng;
    }
    avgLat /= eventsInCluster.length;
    avgLng /= eventsInCluster.length;
    
    // Calcular novo zoom (aumenta em 2 níveis)
    final newZoom = (_currentZoom + 2).clamp(3.0, 20.0);
    
    debugPrint('🔍 Expandindo cluster: zoom ${_currentZoom.toStringAsFixed(1)} → ${newZoom.toStringAsFixed(1)}');
    
    // Marcar que está animando para evitar rebuilds intermediários
    _isAnimating = true;
    
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(avgLat, avgLng),
          newZoom,
        ),
      );
    } finally {
      // Aguardar um pouco para animação completar
      await Future.delayed(const Duration(milliseconds: 300));
      _isAnimating = false;
    }
    
    // Nota: O recálculo dos clusters acontecerá automaticamente
    // no onCameraIdle quando a animação terminar
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
  /// Responsável por:
  /// 1. Capturar bounding box visível
  /// 2. Buscar eventos na região
  /// 3. Recalcular clusters se zoom mudou
  Future<void> _onCameraIdle() async {
    if (_mapController == null || _isAnimating) return;

    try {
      // Obter zoom atual
      final newZoom = await _mapController!.getZoomLevel();
      final zoomChanged = (newZoom - _currentZoom).abs() > 0.5;
      
      // Atualizar zoom atual
      _currentZoom = newZoom;

      final visibleRegion = await _mapController!.getVisibleRegion();
      final bounds = MapBounds.fromLatLngBounds(visibleRegion);
      
      debugPrint('📍 GoogleMapView: Câmera parou (zoom: ${newZoom.toStringAsFixed(1)}, mudou: $zoomChanged)');
      
      // Recalcular clusters se zoom mudou significativamente
      if (zoomChanged && widget.viewModel.events.isNotEmpty) {
        debugPrint('🔄 GoogleMapView: Zoom mudou - recalculando clusters');
        await _rebuildClusteredMarkers();
      }
      
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
  /// Também inicializa o zoom para clustering.
  Future<void> _triggerInitialEventSearch() async {
    if (_mapController == null) return;

    try {
      // Pequeno delay para garantir que o mapa terminou de carregar
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Obter zoom inicial para clustering
      _currentZoom = await _mapController!.getZoomLevel();
      debugPrint('🔲 GoogleMapView: Zoom inicial: ${_currentZoom.toStringAsFixed(1)}');
      
      final visibleRegion = await _mapController!.getVisibleRegion();
      final bounds = MapBounds.fromLatLngBounds(visibleRegion);
      
      debugPrint('🎯 GoogleMapView: Busca inicial de eventos em $bounds');
      
      // Forçar busca imediata (ignora debounce)
      await _discoveryService.forceRefresh(bounds);
      
      // Gerar markers iniciais com clustering
      if (widget.viewModel.events.isNotEmpty) {
        await _rebuildClusteredMarkers();
      }
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

    ToastService.showInfo(message: message);
  }

  /// Handler de navegação chamado pelo MapNavigationService
  /// 
  /// Responsável por:
  /// 1. Encontrar o evento na lista de eventos carregados
  /// 2. Mover câmera para o evento
  /// 3. Abrir o EventCard
  void _handleEventNavigation(String eventId) async {
    debugPrint('🗺️ [GoogleMapView] Navegando para evento: $eventId');
    
    if (!mounted) return;
    
    // Buscar evento na lista de eventos carregados
    final event = widget.viewModel.events.firstWhere(
      (e) => e.id == eventId,
      orElse: () {
        debugPrint('⚠️ [GoogleMapView] Evento não encontrado na lista: $eventId');
        // Se não encontrou, tentar recarregar eventos
        widget.viewModel.loadNearbyEvents();
        throw Exception('Evento não encontrado');
      },
    );
    
    debugPrint('✅ [GoogleMapView] Evento encontrado: ${event.title}');
    
    // Mover câmera para o evento
    if (_mapController != null) {
      final target = LatLng(event.lat, event.lng);
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(target, 15.0),
      );
      debugPrint('📍 [GoogleMapView] Câmera movida para: ${event.title}');
    }
    
    // Aguardar animação da câmera
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted) return;
    
    // Abrir EventCard
    _onMarkerTap(event);
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
            final chatUser = app_user.User.fromDocument({
              'userId': 'event_${event.id}',
              'fullName': eventName,
              'photoUrl': emoji,
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
            
            // Verificar se usuário está bloqueado
            final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
            if (currentUserId.isNotEmpty && 
                BlockService().isBlockedCached(currentUserId, event.createdBy)) {
              final i18n = AppLocalizations.of(context);
              ToastService.showWarning(
                message: i18n?.translate('user_blocked_cannot_message') ?? 
                'Você não pode enviar mensagens para este usuário',
              );
              return;
            }
            
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
      
      // Permitir zoom de 3.0 (visão continental) até 20.0 (visão de rua detalhada)
      minMaxZoomPreference: const MinMaxZoomPreference(3.0, 20.0),

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
    MapNavigationService.instance.unregisterMapHandler();
    debugPrint('🗺️ GoogleMapView: Handler de navegação removido');
    _markerService.clearCache(); // Limpar cache de markers e clusters
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }
}
