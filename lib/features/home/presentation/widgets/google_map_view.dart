import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:markers_cluster_google_maps_flutter/markers_cluster_google_maps_flutter.dart';
import 'package:partiu/core/models/user.dart' as app_user;
import 'package:partiu/core/services/block_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:partiu/features/home/data/repositories/event_map_repository.dart';
import 'package:partiu/features/home/data/services/avatar_service.dart';
import 'package:partiu/features/home/data/services/people_map_discovery_service.dart';
import 'package:partiu/features/home/presentation/services/map_navigation_service.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_bitmap_generator.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/screens/chat/chat_screen_refactored.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/widgets/confetti_celebration.dart';

/// Widget de mapa Google Maps limpo e performático
/// 
/// Responsabilidades:
/// - Renderizar o Google Map
/// - Exibir localização do usuário
/// - Exibir markers com clustering inteligente baseado em zoom
/// - Controlar câmera
/// 
/// Clustering:
/// - Zoom > 10: Apenas markers individuais (SEM clustering)
/// - Zoom <= 10: Clustering ativado (agrupa eventos próximos)
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
  final VoidCallback? onPlatformMapCreated;
  final VoidCallback? onFirstRenderApplied;

  const GoogleMapView({
    super.key,
    required this.viewModel,
    this.onPlatformMapCreated,
  this.onFirstRenderApplied,
  });

  @override
  State<GoogleMapView> createState() => GoogleMapViewState();
}

class GoogleMapViewState extends State<GoogleMapView> {
  /// Controller do mapa Google Maps
  GoogleMapController? _mapController;

  /// Serviço para contagem de pessoas por bounding box
  final PeopleMapDiscoveryService _peopleCountService = PeopleMapDiscoveryService();
  
  /// Markers atuais do mapa (clusterizados)
  Set<Marker> _markers = {};

  // ===== Cluster Manager =====
  // Implementação atual de clustering usando MarkersClusterManager.
  MarkersClusterManager? _clusterManager;
  int _lastMarkersSignature = 0;

  // ===== Marker icons (estilo antigo) =====
  // Mantém o visual antigo:
  // - Evento individual: 2 markers (emoji em baixo + avatar em cima)
  // - Cluster: 1 marker (emoji + badge)
  //
  // Estratégia:
  // - Cluster manager recebe apenas 1 marker por evento (emoji) => clustering correto.
  // - Avatares são desenhados separadamente como overlay *apenas* para eventos que
  //   estão visíveis como markers individuais (não clusterizados) no momento.
  //
  // Nota: o cluster manager não expõe diretamente “quais ids estão dentro do cluster”,
  // então usamos uma heurística segura baseada nos MarkerIds retornados.
  final Set<Marker> _avatarOverlayMarkers = <Marker>{};
  final Map<String, EventModel> _eventById = <String, EventModel>{};
  final Map<String, BitmapDescriptor> _avatarPinCache = <String, BitmapDescriptor>{};
  final AvatarService _avatarService = AvatarService();
  bool _isAvatarWarmupRunning = false;
  static const int _avatarPinSizePx = 120;

  // Cache de ícones de cluster (estilo antigo) por contagem.
  final Map<int, BitmapDescriptor> _clusterPinCache = <int, BitmapDescriptor>{};

  Future<BitmapDescriptor> _getClusterPinForCount(int count) async {
    final cached = _clusterPinCache[count];
    if (cached != null) return cached;

    // Estilo antigo: emoji + badge com contagem.
    // Como o cluster manager não expõe o emoji dominante do cluster,
    // usamos um emoji neutro por enquanto (pode ser refinado depois).
    const String fallbackEmoji = '🎉';
    final pin = await MarkerBitmapGenerator.generateClusterPinForGoogleMaps(
      fallbackEmoji,
      count,
      size: 230,
    );
    _clusterPinCache[count] = pin;
    return pin;
  }

  /// Extrai a contagem de markers de um marker de cluster gerado pela lib.
  /// O markerId do cluster é 'cluster_LatLng(lat, lng)' e o infoWindow.title é 'N markers'.
  int? _extractClusterCount(Marker m) {
    final title = m.infoWindow.title;
    if (title == null) return null;
    // Formato esperado: "3 markers"
    final match = RegExp(r'^(\d+)\s+markers?$').firstMatch(title);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  int _markerSignatureForEvents(List<EventModel> events) {
    // Hash leve e determinístico para saber quando precisamos reconstruir a base de markers.
    // Considera apenas ids (ordem não importa).
    final ids = events.map((e) => e.id).toList()..sort();
    return Object.hashAll(ids);
  }

  void _ensureClusterManagerInitialized() {
    if (_clusterManager != null) return;

    _clusterManager = MarkersClusterManager(
      // Estilo básico (ajustamos depois para o visual final).
      clusterColor: Colors.black,
      clusterBorderThickness: 6.0,
      clusterBorderColor: Colors.white,
      clusterOpacity: 0.92,
      clusterTextStyle: const TextStyle(
        fontSize: 28,
        color: Colors.white,
        fontWeight: FontWeight.w800,
      ),
      // NÃO usamos onMarkerTap da lib pois ele é chamado para TODOS os taps
      // (clusters e markers individuais). Em vez disso, configuramos onTap
      // individualmente em cada marker no _updateClustersFromManager.
      onMarkerTap: null,
    );
  }

  /// Callback para tap em cluster: zoom in agressivo para expandir rapidamente.
  void _onClusterTap(LatLng position, int count) {
    debugPrint('🔍🔍🔍 _onClusterTap CHAMADO! position=$position, count=$count 🔍🔍🔍');
    
    final controller = _mapController;
    if (controller == null) return;
    
    // Zoom mais agressivo para clusters pequenos (2-3 markers)
    // para expandir rapidamente em 1 clique.
    final zoomIncrement = count <= 3 ? 3.0 : 2.0;
    final targetZoom = (_currentZoom + zoomIncrement).clamp(0.0, 18.0);
    
    debugPrint('🔍 Cluster tap: count=$count, zoom atual=${_currentZoom.toStringAsFixed(1)}, target=$targetZoom');
    
    controller.animateCamera(
      CameraUpdate.newLatLngZoom(position, targetZoom),
    );
  }

  Future<BitmapDescriptor> _getAvatarPinBestEffort(EventModel event) async {
    final userId = event.createdBy;
    final cached = _avatarPinCache[userId];
    if (cached != null) return cached;

    try {
      final avatarUrl = await _avatarService.getAvatarUrl(userId);
      final pin = await MarkerBitmapGenerator.generateAvatarPinForGoogleMaps(
        avatarUrl,
        size: _avatarPinSizePx,
      );
      _avatarPinCache[userId] = pin;
      return pin;
    } catch (_) {
      return BitmapDescriptor.defaultMarker;
    }
  }

  Future<void> _warmupAvatarsForEvents(List<EventModel> events) async {
    if (_isAvatarWarmupRunning) return;
    _isAvatarWarmupRunning = true;
    try {
      // Best-effort warmup em paralelo, mas sem explodir trabalho.
      final uniqueCreators = <String>{};
      final limited = <EventModel>[];
      for (final e in events) {
        if (uniqueCreators.add(e.createdBy)) {
          limited.add(e);
        }
        if (limited.length >= 40) break;
      }

      await Future.wait(limited.map(_getAvatarPinBestEffort));
    } finally {
      _isAvatarWarmupRunning = false;
    }
  }

  Future<void> _syncBaseMarkersIntoClusterManager(List<EventModel> events) async {
    _ensureClusterManagerInitialized();
    final manager = _clusterManager;
    if (manager == null) return;
    if (!mounted) return;

    final signature = _markerSignatureForEvents(events);
    if (signature == _lastMarkersSignature) return;
    _lastMarkersSignature = signature;

    // Recriar manager é a forma mais segura de garantir que não há markers "stale"
    // quando categoria/bounds mudam (a lib não documenta um clear).
    _clusterManager = null;
    _ensureClusterManagerInitialized();
    final rebuilt = _clusterManager!;

    _eventById
      ..clear()
      ..addEntries(events.map((e) => MapEntry(e.id, e)));

    // Best-effort warmup (não bloqueia o render de markers).
    unawaited(_warmupAvatarsForEvents(events));

    // 1 marker por evento (emoji) para alimentar o cluster manager.
    // O avatar é desenhado como overlay apenas quando o evento está individual.
    for (final event in events) {
      try {
        final emojiPin = await MarkerBitmapGenerator.generateEmojiPinForGoogleMaps(
          event.emoji,
          eventId: event.id,
          size: 230,
        );

        rebuilt.addMarker(
          Marker(
            markerId: MarkerId('event_${event.id}'),
            position: LatLng(event.lat, event.lng),
            icon: emojiPin,
            anchor: const Offset(0.5, 1.0),
            // Emoji base fica na camada 1, avatar logo acima na camada 2.
            zIndex: 1,
            onTap: () => unawaited(_onMarkerTap(event)),
          ),
        );
      } catch (_) {
        // Best-effort; se falhar para um evento, seguimos.
      }
    }
  }

  Future<void> _updateClustersFromManager() async {
    final manager = _clusterManager;
    if (manager == null) return;

  // Regra do exemplo oficial da lib: sempre recalcular clusters com o zoom atual.
  await manager.updateClusters(zoomLevel: _currentZoom);
    if (!mounted) return;

    final clustered = Set<Marker>.of(manager.getClusteredMarkers());

    // DEBUG: verificar o que a lib está retornando
    for (final m in clustered) {
      debugPrint('🔷 Marker retornado: id="${m.markerId.value}"');
    }

    // Substitui markers de CLUSTER (gerados pela lib) por ícones no nosso estilo.
    // Heurística: markers de evento começam com 'event_'. Clusters começam com 'cluster_'.
    final nextClusteredStyled = <Marker>{};
    for (final m in clustered) {
      final rawId = m.markerId.value;
      
      // Se começa com 'event_', é um marker individual nosso.
      // IMPORTANTE: a lib pode retornar cópias sem o onTap original,
      // então precisamos re-aplicar o onTap aqui.
      if (rawId.startsWith('event_')) {
        final eventId = rawId.replaceFirst('event_', '');
        final event = _eventById[eventId];
        if (event != null) {
          // Re-aplicar onTap para garantir que o EventCard abre
          final eventForClosure = event;
          nextClusteredStyled.add(
            m.copyWith(
              onTapParam: () {
                debugPrint('👆👆👆 TAP no EMOJI marker: ${eventForClosure.title} 👆👆👆');
                _onMarkerTap(eventForClosure);
              },
            ),
          );
        } else {
          debugPrint('⚠️ Marker individual: $eventId - evento não encontrado em _eventById');
          nextClusteredStyled.add(m);
        }
        continue;
      }

      // Clusters da lib têm markerId 'cluster_LatLng(...)' e count no infoWindow.title.
      // Ex: infoWindow.title = '3 markers'
      if (!rawId.startsWith('cluster_')) {
        // Marker desconhecido, mantemos como está.
        nextClusteredStyled.add(m);
        continue;
      }

      // Extrair contagem real do infoWindow.title
      int? count = _extractClusterCount(m);
      
      // Se não conseguiu extrair, usa 2 como fallback (mínimo de um cluster)
      count ??= 2;

      debugPrint('🔶 Cluster detectado: id="$rawId" -> count=$count (title="${m.infoWindow.title}")');

      final clusterPin = await _getClusterPinForCount(count);
      final clusterPosition = m.position;
      final clusterCount = count;
      nextClusteredStyled.add(
        m.copyWith(
          iconParam: clusterPin,
          anchorParam: const Offset(0.5, 1.0),
          zIndexParam: 1000,
          // Remove o popup padrão da lib que mostra "N markers"
          infoWindowParam: InfoWindow.noText,
          // Adiciona onTap para fazer zoom in no cluster
          onTapParam: () => _onClusterTap(clusterPosition, clusterCount),
        ),
      );
    }

    // Avatares: gerar overlay para SOMENTE os markers individuais.
    // Heurística: markerId começa com 'event_' (os que adicionamos) e não é cluster (que costuma ser numérico/gerado).
    // ✅ CORREÇÃO: Usar zIndex único por evento para manter emoji e avatar na mesma camada lógica
    final nextAvatarOverlays = <Marker>{};
    int avatarZIndexCounter = 0;
    final updatedEmojiMarkers = <Marker>{};
    final markersToRemove = <Marker>{};
  for (final m in nextClusteredStyled) {
      final rawId = m.markerId.value;
      if (!rawId.startsWith('event_')) continue;
      final eventId = rawId.replaceFirst('event_', '');
      final event = _eventById[eventId];
      if (event == null) continue;

      // Calcular zIndex único para este par emoji+avatar (base 100+)
      final baseZIndex = 100 + (avatarZIndexCounter * 2);
      avatarZIndexCounter++;


      // Atualizar o emoji marker para usar o baseZIndex
      markersToRemove.add(m);
      updatedEmojiMarkers.add(m.copyWith(zIndexParam: baseZIndex.toDouble()));
      // Avatar pin best-effort; se ainda não estiver pronto, usa placeholder.
      final avatarPin = await _getAvatarPinBestEffort(event);
      nextAvatarOverlays.add(
        Marker(
          markerId: MarkerId('event_avatar_$eventId'),
          position: m.position,
          icon: avatarPin,
          // Mesmo estilo antigo: avatar “flutuando” sobre o emoji.
          anchor: const Offset(0.5, 0.80),
          onTap: () { debugPrint('👆 TAP AVATAR (line 359)'); _onMarkerTap(event); },
          // Avatar fica logo acima do emoji do mesmo evento.
          zIndex: (baseZIndex + 1).toDouble(),
        ),
      );
    }

    // Atualizar o set de markers com os emojis que têm zIndex corrigido
    nextClusteredStyled.removeAll(markersToRemove);
    nextClusteredStyled.addAll(updatedEmojiMarkers);

    setState(() {
      _avatarOverlayMarkers
        ..clear()
        ..addAll(nextAvatarOverlays);
  _markers = nextClusteredStyled;
    });
  }

  /// Pipeline único de render: qualquer trigger chama `scheduleRender()`.
  ///
  /// - Cancela render agendado anterior
  /// - Executa em debounce curto
  Timer? _renderDebounce;
  static const Duration _renderDebounceDuration = Duration(milliseconds: 80);

  /// Se um render foi solicitado enquanto `_isCameraMoving`/`_isAnimating` estava true,
  /// guardamos pendência para executar assim que a câmera ficar idle.
  bool _renderPendingAfterMove = false;
  
  /// Estilo customizado do mapa carregado de assets
  String? _mapStyle;
  
  /// Zoom atual do mapa (usado para clustering)
  double _currentZoom = 12.0;

  /// Último bounds visível (expandido com buffer) usado para filtrar markers no viewport.
  LatLngBounds? _lastExpandedVisibleBounds;

  /// Última versão do dataset (MapViewModel.eventsVersion) que foi usada
  /// para renderizar markers.
  int _lastRenderedEventsVersion = -1;

  // Limiar de UX: acima disso tendemos a filtrar por viewport para reduzir custo.
  static const double _clusterZoomThreshold = 11.0;

  // No cold start, renderizar TODOS os eventos no viewport pode atrasar o
  // primeiro paint (principalmente se houver muitos). Para a UX, é melhor
  // mostrar um subconjunto rapidamente e depois completar.


  /// Sinaliza para o pai (Discover) que o primeiro render de markers foi aplicado.
  /// Isso ajuda a sincronizar warmups (ex.: clusters) sem competir com o cold start.
  bool _didEmitFirstRenderApplied = false;
  
  /// Flag para evitar rebuilds durante animação de câmera
  bool _isAnimating = false;

  /// Flag para evitar rebuild pesado enquanto o usuário move o mapa
  bool _isCameraMoving = false;

  Timer? _cameraIdleDebounce;
  static const Duration _cameraIdleDebounceDuration = Duration(milliseconds: 200);

  Timer? _avatarBitmapsDebounce;
  

  // Buffer do viewport usado para filtrar markers em zoom alto.
  // Aumentar esse fator melhora a sensação de "instantâneo" ao pan, pois mais
  // eventos que estão logo fora do frame já entram no conjunto renderizável.
  static const double _viewportBoundsBufferFactor = 2.0;

  // ===== Prefetch por "zona de gordura" (cobertura além do frame) =====
  // Ideia: manter um bounds maior (pré-carregado) para que pans dentro dessa área
  // não disparem rede e apenas re-renderizem markers/clusters.
  //
  // Em zoom baixo usamos clustering sem filtro de viewport; então o ganho aqui é
  // principalmente evitar espera de rede ao pan em zoom alto (markers individuais).
  static const double _prefetchBoundsBufferFactor = 2.6;
  LatLngBounds? _prefetchedExpandedBounds;

  MapBounds? _lastRequestedQueryBounds;
  DateTime _lastRequestedQueryAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minIntervalBetweenContainedBoundsQueries = Duration(seconds: 2);

  bool _isLatLngBoundsContained(LatLngBounds inner, LatLngBounds outer) {
    // Note: tratamos o caso típico (não cruza antimeridiano). Para robustez,
    // aplicamos a mesma lógica de longitude do _boundsContains.
    final innerSw = inner.southwest;
    final innerNe = inner.northeast;
    final outerSw = outer.southwest;
    final outerNe = outer.northeast;

    final innerMinLat = innerSw.latitude < innerNe.latitude ? innerSw.latitude : innerNe.latitude;
    final innerMaxLat = innerSw.latitude < innerNe.latitude ? innerNe.latitude : innerSw.latitude;
    final outerMinLat = outerSw.latitude < outerNe.latitude ? outerSw.latitude : outerNe.latitude;
    final outerMaxLat = outerSw.latitude < outerNe.latitude ? outerNe.latitude : outerSw.latitude;

    final latContained = innerMinLat >= outerMinLat && innerMaxLat <= outerMaxLat;

    // Para containment de longitude, cobrimos dois cenários do outer:
    // - outerSw <= outerNe: intervalo normal
    // - outerSw > outerNe: outer cruza o antimeridiano
    final outerCrosses = outerSw.longitude > outerNe.longitude;
    final innerCrosses = innerSw.longitude > innerNe.longitude;

    // Se inner cruza antimeridiano mas outer não cruza, não pode estar contido.
    if (innerCrosses && !outerCrosses) return false;

    if (!outerCrosses) {
      // Intervalo normal.
      final minLng = outerSw.longitude;
      final maxLng = outerNe.longitude;
      final innerMinLng = innerSw.longitude;
      final innerMaxLng = innerNe.longitude;
      return latContained && innerMinLng >= minLng && innerMaxLng <= maxLng;
    }

    // Outer cruza antimeridiano, então "contido" significa que ambos os cantos
    // do inner estão em uma das duas faixas válidas: [outerSw..180] U [-180..outerNe].
    final swOk = (innerSw.longitude >= outerSw.longitude) || (innerSw.longitude <= outerNe.longitude);
    final neOk = (innerNe.longitude >= outerSw.longitude) || (innerNe.longitude <= outerNe.longitude);
    return latContained && swOk && neOk;
  }

  Future<void> _prefetchEventsForExpandedBounds(LatLngBounds visibleRegion) async {
    // Best-effort: não bloquear UX. Se falhar, o onCameraIdle normal ainda faz fetch.
    if (!mounted) return;
    if (_mapController == null) return;

    final expanded = _expandBounds(visibleRegion, _prefetchBoundsBufferFactor);
    _prefetchedExpandedBounds = expanded;

    final prefetchQuery = MapBounds.fromLatLngBounds(expanded);
    try {
      await widget.viewModel.loadEventsInBounds(prefetchQuery);
    } catch (_) {
      // ignora
    }
  }

  bool _isBoundsContained(MapBounds inner, MapBounds outer) {
    return inner.minLat >= outer.minLat &&
        inner.maxLat <= outer.maxLat &&
        inner.minLng >= outer.minLng &&
        inner.maxLng <= outer.maxLng;
  }

  LatLngBounds _expandBounds(LatLngBounds bounds, double factor) {
    final sw = bounds.southwest;
    final ne = bounds.northeast;

    final centerLat = (sw.latitude + ne.latitude) / 2.0;
    final centerLng = (sw.longitude + ne.longitude) / 2.0;

    final halfLatSpan = (ne.latitude - sw.latitude).abs() * factor / 2.0;
    final halfLngSpan = (ne.longitude - sw.longitude).abs() * factor / 2.0;

    double clampLat(double v) => v.clamp(-90.0, 90.0);
    double clampLng(double v) => v.clamp(-180.0, 180.0);

    return LatLngBounds(
      southwest: LatLng(
        clampLat(centerLat - halfLatSpan),
        clampLng(centerLng - halfLngSpan),
      ),
      northeast: LatLng(
        clampLat(centerLat + halfLatSpan),
        clampLng(centerLng + halfLngSpan),
      ),
    );
  }

  bool _boundsContains(LatLngBounds bounds, double lat, double lng) {
    final sw = bounds.southwest;
    final ne = bounds.northeast;

    final minLat = sw.latitude < ne.latitude ? sw.latitude : ne.latitude;
    final maxLat = sw.latitude < ne.latitude ? ne.latitude : sw.latitude;
    final withinLat = lat >= minLat && lat <= maxLat;

    // Normalmente (Brasil) não cruza antimeridiano; ainda assim, trata caso sw.lng > ne.lng.
    final swLng = sw.longitude;
    final neLng = ne.longitude;
    final withinLng = swLng <= neLng ? (lng >= swLng && lng <= neLng) : (lng >= swLng || lng <= neLng);

    return withinLat && withinLng;
  }

  /// Método público para centralizar no usuário
  void centerOnUser() {
    _moveCameraToUserLocation();
  }

  /// Preload best-effort: força um render com o estado atual.
  Future<void> preloadZoomOutClusters({
    double targetZoom = 6.0,
    Duration settleDelay = const Duration(milliseconds: 220),
  }) async {
    if (!mounted) return;
    final controller = _mapController;
    if (controller == null) return;

    // Se ainda não temos eventos, não há o que clusterizar.
    if (widget.viewModel.events.isEmpty) return;

    // Evitar competir com interação do usuário.
    if (_isCameraMoving || _isAnimating) return;

  scheduleRender();
  }

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    widget.viewModel.onMarkerTap = (event) => _onMarkerTap(event);
    MapNavigationService.instance.registerMapHandler(
      (eventId, {showConfetti = false}) {
        _handleEventNavigation(eventId, showConfetti: showConfetti);
      },
    );
    widget.viewModel.addListener(_onEventsChanged);

    // Quando um avatar termina de carregar em background, o Marker do Google Maps
    // NÃO se atualiza sozinho: precisamos reconstruir o Set<Marker> para trocar o ícone.
    // Listener de avatares era usado no fluxo antigo (pins compostos). No novo
    // fluxo, o POC usa ícone simples; mantemos sem listener para reduzir churn.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  /// Carrega o estilo do mapa de assets
  Future<void> _loadMapStyle() async {
    try {
      final style = await rootBundle.loadString('assets/map_styles/clean.json');
      if (!mounted) return;
      setState(() {
        _mapStyle = style;
      });
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar estilo do mapa: $e');
    }
  }
  
  /// Callback quando eventos mudarem
  void _onEventsChanged() async {
    if (!mounted || _isAnimating) return;
    scheduleRender();
  }

  /// Agenda um rebuild de markers num pipeline único.
  void scheduleRender() {
    if (!mounted) return;
    if (_mapController == null) return;

    // Se estamos em movimento/animação, não tentamos render agora (evita churn),
    // mas garante que o próximo idle execute um render obrigatório.
    if (_isAnimating || _isCameraMoving) {
      _renderPendingAfterMove = true;
      return;
    }

    _renderDebounce?.cancel();
    _renderDebounce = Timer(_renderDebounceDuration, () {
      if (!mounted) return;
      if (_isAnimating || _isCameraMoving) return;
      unawaited(_rebuildMarkersUsingClusterManager());
    });
  }

  Future<void> _rebuildMarkersUsingClusterManager() async {
    if (!mounted || _isAnimating || _isCameraMoving) return;
    if (_mapController == null) return;

    // Snapshot consistente (similar ao fluxo atual).
    final allEvents = List<EventModel>.from(widget.viewModel.events);
    if (allEvents.isEmpty) {
      if (_markers.isNotEmpty) setState(() => _markers = {});
      return;
    }

    // Reusar a mesma regra de filtro do modo atual (categoria + viewport quando zoom alto).
    var bounds = _lastExpandedVisibleBounds;
    if (bounds == null) {
      try {
        final visibleRegion = await _mapController!.getVisibleRegion();
        bounds = _expandBounds(visibleRegion, _viewportBoundsBufferFactor);
        _lastExpandedVisibleBounds = bounds;
      } catch (_) {
        return;
      }
    }
    if (bounds == null) return;

    final zoomSnapshot = _currentZoom;
    final shouldFilterByViewport = zoomSnapshot > _clusterZoomThreshold;
    final categoryFiltered = _applyCategoryFilter(allEvents);
    final b = bounds;
    final viewportEvents = categoryFiltered
        .where((event) => !shouldFilterByViewport || _boundsContains(b, event.lat, event.lng))
        .toList(growable: false);

    if (viewportEvents.isEmpty) {
      if (_markers.isNotEmpty) setState(() => _markers = {});
      return;
    }

    await _syncBaseMarkersIntoClusterManager(viewportEvents);
    await _updateClustersFromManager();

    // Notifica apenas uma vez, após aplicar markers pela primeira vez.
    if (!_didEmitFirstRenderApplied) {
      _didEmitFirstRenderApplied = true;
      widget.onFirstRenderApplied?.call();
    }
  }

  List<EventModel> _applyCategoryFilter(List<EventModel> events) {
    final selected = widget.viewModel.selectedCategory;
    if (selected == null || selected.trim().isEmpty) return events;

    final normalized = selected.trim();
    return events.where((event) {
      final category = event.category;
      if (category == null) return false;
      return category.trim() == normalized;
    }).toList(growable: false);
  }

  /// Callback quando o mapa é criado
  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;

    // Sinaliza que o PlatformView do mapa já foi criado (evita tela branca sem feedback)
    widget.onPlatformMapCreated?.call();
    
    // Mover câmera para localização inicial (já carregada)
    if (widget.viewModel.lastLocation != null) {
      await _moveCameraTo(
        widget.viewModel.lastLocation!.latitude,
        widget.viewModel.lastLocation!.longitude,
        zoom: 12.0, // Visão regional para ver mais eventos
        animate: false,
      );
    } else {
      await _moveCameraToUserLocation(animate: false);
    }

    // Fazer busca inicial de eventos na região visível
    // Isso garante que o drawer tenha dados logo ao abrir
    await _triggerInitialEventSearch();
  }

  /// Prefetch best-effort baseado no viewport REAL (visibleRegion) com bounds expandido.
  ///
  /// Uso típico: warmup pós-splash, após primeiro render aplicado.
  Future<void> prefetchExpandedBounds({double? bufferFactor}) async {
    final controller = _mapController;
    if (controller == null || !mounted) return;

    try {
      final visibleRegion = await controller.getVisibleRegion();
      final factor = bufferFactor ?? _prefetchBoundsBufferFactor;
      final expanded = _expandBounds(visibleRegion, factor);
      await _prefetchEventsForExpandedBounds(expanded);
    } catch (_) {
      // Best-effort.
    }
  }

  /// Callback quando a câmera para de se mover
  /// 
  /// Responsável por:
  /// 1. Capturar bounding box visível
  /// 2. Buscar eventos na região
  /// 3. Recalcular clusters se zoom mudou
  Future<void> _onCameraIdle() async {
    _isCameraMoving = false;

    if (_mapController == null || _isAnimating) return;

  // NOTE: n e3o temos mais pipeline de "cluster expansion"; qualquer movimento termina
  // em um render debounced normal.

    _cameraIdleDebounce?.cancel();
    _cameraIdleDebounce = Timer(_cameraIdleDebounceDuration, () {
      if (!mounted) return;
      unawaited(_handleCameraIdleDebounced());
    });
  }

  Future<void> _handleCameraIdleDebounced() async {
    if (_mapController == null || _isAnimating) return;

    try {
      // Sincronizar zoom (pode ter mudado durante o movimento)
      _currentZoom = await _mapController!.getZoomLevel();

      final visibleRegion = await _mapController!.getVisibleRegion();
      widget.viewModel.setVisibleBounds(visibleRegion);
      final expandedBounds = _expandBounds(visibleRegion, _viewportBoundsBufferFactor);
      _lastExpandedVisibleBounds = expandedBounds;

      // Bounds "prefetched" usa um buffer maior, pensado para cobrir vários pans.
      final prefetchExpandedBounds = _expandBounds(visibleRegion, _prefetchBoundsBufferFactor);

      // Fonte de verdade para drawer/chips: bounds VISÍVEL (frame).
      final queryBounds = MapBounds.fromLatLngBounds(visibleRegion);
      final peopleBounds = MapBounds.fromLatLngBounds(visibleRegion);
      
      debugPrint('📍 GoogleMapView: Câmera parou (zoom: ${_currentZoom.toStringAsFixed(1)})');
      
      // Disparar busca de eventos no bounding box
      final now = DateTime.now();
      final withinPrevious = _lastRequestedQueryBounds != null &&
          _isBoundsContained(queryBounds, _lastRequestedQueryBounds!);
      final tooSoon = now.difference(_lastRequestedQueryAt) < _minIntervalBetweenContainedBoundsQueries;

      final withinPrefetched = _prefetchedExpandedBounds != null &&
          _isLatLngBoundsContained(visibleRegion, _prefetchedExpandedBounds!);

      if (withinPrefetched) {
        // Dentro da zona de gordura: não faz rede.
        debugPrint('📦 GoogleMapView: Dentro do bounds pré-carregado, pulando refetch');
      } else if (withinPrevious && tooSoon) {
        debugPrint('📦 GoogleMapView: Bounds contido, pulando refetch (janela curta)');
      } else {
        _lastRequestedQueryBounds = queryBounds;
        _lastRequestedQueryAt = now;
        await widget.viewModel.loadEventsInBounds(queryBounds);

        // Atualiza a zona de gordura baseada no viewport atual.
        _prefetchedExpandedBounds = prefetchExpandedBounds;

        // Se novos dados chegaram, forçar um render para atualizar markers.
        scheduleRender();
      }

      // Fallback de confiabilidade: se o dataset mudou desde o último render.
      final currentVersion = widget.viewModel.eventsVersion.value;
      if (currentVersion != _lastRenderedEventsVersion) {
        _lastRenderedEventsVersion = currentVersion;
        scheduleRender();
      }

      // Atualizar contagem/lista de pessoas quando zoom está próximo.
      final viewportActive = _currentZoom > _clusterZoomThreshold;
      _peopleCountService.setViewportActive(viewportActive);
      if (viewportActive) {
        await _peopleCountService.loadPeopleCountInBounds(peopleBounds);
      }
    } catch (error) {
      debugPrint('⚠️ GoogleMapView: Erro ao capturar bounding box: $error');
    }
  }

  void _onCameraMoveStarted() {
    _isCameraMoving = true;
    // Evita acumular downloads enquanto o usuário está pan/zoom no mapa.
    UserStore.instance.cancelAvatarPreloads();
  }

  /// Callback a cada movimento de câmera.
  /// 
  /// Seguindo a documentação da lib markers_cluster_google_maps_flutter,
  /// atualizamos os clusters em tempo real conforme o zoom muda.
  void _onCameraMove(CameraPosition position) {
    // Atualizar zoom atual imediatamente
    _currentZoom = position.zoom;
    
    // Atualizar clusters em tempo real (sem debounce)
    // Isso garante que os clusters se reorganizem instantaneamente durante zoom
    _updateClustersRealtime();
  }

  /// Atualiza clusters em tempo real durante movimento de câmera.
  /// Otimizado para ser chamado frequentemente sem bloquear a UI.
  void _updateClustersRealtime() {
    final manager = _clusterManager;
    if (manager == null) return;
    if (!mounted) return;
    
    // Usar unawaited para não bloquear o movimento do mapa
    unawaited(_performClusterUpdate());
  }

  Future<void> _performClusterUpdate() async {
    final manager = _clusterManager;
    if (manager == null) return;
    
    // Atualizar clusters com o zoom atual
    await manager.updateClusters(zoomLevel: _currentZoom);
    if (!mounted) return;
    
    final clustered = Set<Marker>.of(manager.getClusteredMarkers());
    
    // Substituir markers de CLUSTER por ícones customizados
    final nextClusteredStyled = <Marker>{};
    for (final m in clustered) {
      final rawId = m.markerId.value;
      
      // Markers individuais: re-aplicar onTap (a lib pode retornar cópias sem ele)
      if (rawId.startsWith('event_')) {
        final eventId = rawId.replaceFirst('event_', '');
        final event = _eventById[eventId];
        if (event != null) {
          nextClusteredStyled.add(
            m.copyWith(
              onTapParam: () {
                debugPrint('👆 TAP (realtime) no marker: ${event.title}');
                unawaited(_onMarkerTap(event));
              },
            ),
          );
        } else {
          nextClusteredStyled.add(m);
        }
        continue;
      }

      if (!rawId.startsWith('cluster_')) {
        nextClusteredStyled.add(m);
        continue;
      }

      int? count = _extractClusterCount(m);
      count ??= 2;

      final clusterPin = await _getClusterPinForCount(count);
      final clusterPosition = m.position;
      final clusterCount = count;
      nextClusteredStyled.add(
        m.copyWith(
          iconParam: clusterPin,
          anchorParam: const Offset(0.5, 1.0),
          zIndexParam: 1000,
          infoWindowParam: InfoWindow.noText,
          // Adiciona onTap para fazer zoom in no cluster
          onTapParam: () => _onClusterTap(clusterPosition, clusterCount),
        ),
      );
    }

    // Avatares para markers individuais
    // ✅ CORREÇÃO: Usar zIndex único por evento para manter emoji e avatar na mesma camada lógica
    final nextAvatarOverlays = <Marker>{};
    final updatedEmojiMarkers2 = <Marker>{};
    final markersToRemove2 = <Marker>{};
    int avatarZIndexCounter2 = 0;
    for (final m in nextClusteredStyled) {
      final rawId = m.markerId.value;
      if (!rawId.startsWith('event_')) continue;
      final eventId = rawId.replaceFirst('event_', '');
      final event = _eventById[eventId];
      if (event == null) continue;

      // Calcular zIndex único para este par emoji+avatar (base 100+)
      final baseZIndex = 100 + (avatarZIndexCounter2 * 2);
      avatarZIndexCounter2++;

      // Atualizar o emoji marker para usar o baseZIndex
      markersToRemove2.add(m);
      updatedEmojiMarkers2.add(m.copyWith(zIndexParam: baseZIndex.toDouble()));

      final avatarPin = await _getAvatarPinBestEffort(event);

      nextAvatarOverlays.add(
        Marker(
          markerId: MarkerId('event_avatar_$eventId'),
          position: m.position,
          icon: avatarPin,
          anchor: const Offset(0.5, 0.80),
          onTap: () { debugPrint('👆 TAP AVATAR (line 920)'); _onMarkerTap(event); },
          // Avatar fica logo acima do emoji do mesmo evento.
          zIndex: (baseZIndex + 1).toDouble(),
        ),
      );
    }

    // Atualizar o set de markers com os emojis que têm zIndex corrigido
    nextClusteredStyled.removeAll(markersToRemove2);
    nextClusteredStyled.addAll(updatedEmojiMarkers2);

    if (!mounted) return;
    setState(() {
      _avatarOverlayMarkers
        ..clear()
        ..addAll(nextAvatarOverlays);
      _markers = nextClusteredStyled;
    });
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
  widget.viewModel.setVisibleBounds(visibleRegion);
      _lastExpandedVisibleBounds = _expandBounds(visibleRegion, _viewportBoundsBufferFactor);
      final bounds = MapBounds.fromLatLngBounds(visibleRegion);

  // Preload de cobertura (zona de gordura): buscar eventos num bounds maior logo no início.
  // Isso faz com que, ao pan dentro dessa área, os markers/clusters apareçam mais rápido.
  // Best-effort e não substitui o fetch normal do frame.
  unawaited(_prefetchEventsForExpandedBounds(visibleRegion));
      
      debugPrint('🎯 GoogleMapView: Busca inicial de eventos em $bounds');
      
      // Forçar busca imediata para categorias do drawer (ignora debounce)
      // mas evita duplicar com um refetch que possa ter sido disparado no 1º onCameraIdle.
      final now = DateTime.now();
      final withinPrevious = _lastRequestedQueryBounds != null &&
          _isBoundsContained(bounds, _lastRequestedQueryBounds!);
      final tooSoon = now.difference(_lastRequestedQueryAt) < _minIntervalBetweenContainedBoundsQueries;

      if (!(withinPrevious && tooSoon)) {
        _lastRequestedQueryBounds = bounds;
        _lastRequestedQueryAt = now;
        await widget.viewModel.forceRefreshBounds(bounds);
      }

      // Contagem/lista de pessoas só faz sentido quando zoom está próximo
      // (clusters desfeitos). Em zoom out, não fazemos preload.
      final viewportActive = _currentZoom > _clusterZoomThreshold;
      _peopleCountService.setViewportActive(viewportActive);
      if (viewportActive) {
        await _peopleCountService.forceRefresh(bounds);
      }
      
      // Gerar markers iniciais com clustering
      if (widget.viewModel.events.isNotEmpty) {
  scheduleRender();
      }
    } catch (error) {
      debugPrint('⚠️ GoogleMapView: Erro na busca inicial: $error');
    }
  }

  /// Move a câmera para a localização do usuário
  Future<void> _moveCameraToUserLocation({bool animate = true}) async {
    final result = await widget.viewModel.getUserLocation();

    // Exibir mensagem de erro se houver
    if (result.hasError && mounted) {
      _showMessage(result.errorMessage!);
    }

    // Mover câmera
    await _moveCameraTo(
      result.location.latitude,
      result.location.longitude,
      zoom: 12.0, // Visão regional para ver mais eventos
      animate: animate,
    );
  }

  /// Move a câmera para uma coordenada específica
  Future<void> _moveCameraTo(
    double lat,
    double lng, {
    double zoom = 14.0,
    bool animate = true,
  }) async {
    if (_mapController == null) return;

    try {
      final update = CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(lat, lng),
          zoom: zoom,
        ),
      );

      if (animate) {
        await _mapController!.animateCamera(update);
      } else {
        await _mapController!.moveCamera(update);
      }
    } catch (e) {
      // Falha silenciosa - câmera continua onde está
    }
  }

  /// Exibe mensagem para o usuário
  void _showMessage(String message) {
    if (!mounted) return;

    ToastService.showInfo(message: message);
  }

  void _showClusterEventsSheet(List<EventModel> events) {
    if (!mounted) return;

    final sorted = [...events]
      ..sort((a, b) => (a.title).toLowerCase().compareTo((b.title).toLowerCase()));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 500),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Eventos neste cluster (${sorted.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = sorted[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text(e.emoji, style: const TextStyle(fontSize: 20)),
                        title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: e.category == null
                            ? null
                            : Text(e.category!, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.of(context).pop();
                          unawaited(_onMarkerTap(e));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Handler de navegação chamado pelo MapNavigationService
  /// 
  /// Responsável por:
  /// 1. Encontrar o evento na lista de eventos carregados (ou buscar do Firestore)
  /// 2. Mover câmera para o evento
  /// 3. Abrir o EventCard
  /// 
  /// [showConfetti] - Se true, mostra confetti ao abrir o card (usado após criar evento)
  void _handleEventNavigation(String eventId, {bool showConfetti = false}) async {
    debugPrint('🗺️ [GoogleMapView] Navegando para evento: $eventId (confetti: $showConfetti)');
    
    if (!mounted) return;
    
    EventModel? event;
    
    // Primeiro, tentar encontrar na lista de eventos carregados (mais rápido)
    try {
      event = widget.viewModel.events.firstWhere((e) => e.id == eventId);
      debugPrint('✅ [GoogleMapView] Evento encontrado na lista local: ${event.title}');
    } catch (_) {
      // Não encontrou na lista local, buscar do Firestore
      debugPrint('⚠️ [GoogleMapView] Evento não encontrado na lista local, buscando do Firestore...');
      
      try {
        event = await EventMapRepository().getEventById(eventId);
        
        if (event == null) {
          debugPrint('❌ [GoogleMapView] Evento não encontrado no Firestore: $eventId');
          return;
        }
        
        debugPrint('✅ [GoogleMapView] Evento carregado do Firestore: ${event.title}');
        
        // Injetar o evento no ViewModel para que o marker apareça
        await widget.viewModel.injectEvent(event);
      } catch (e) {
        debugPrint('❌ [GoogleMapView] Erro ao buscar evento do Firestore: $e');
        return;
      }
    }
    
    if (!mounted) return;
    
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
    
    // Abrir EventCard (com confetti se for evento recém-criado)
    _onMarkerTap(event, showConfetti: showConfetti);
  }

  /// Callback quando usuário toca em um marker
  /// 
  /// [showConfetti] - Se true, mostra confetti ao abrir o card (usado após criar evento)
  Future<void> _onMarkerTap(EventModel event, {bool showConfetti = false}) async {
    debugPrint('🔴🔴🔴 GoogleMapView._onMarkerTap CHAMADO! 🔴🔴🔴');
    debugPrint('🔴 GoogleMapView._onMarkerTap called for: ${event.id} - ${event.title}');
    
    final firestore = FirebaseFirestore.instance;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    // ✅ Pré-carregar TODOS os dados necessários em paralelo
    String? creatorFullName = event.creatorFullName;
    List<Map<String, dynamic>>? participants = event.participants;
    dynamic userApplication = event.userApplication;
    
    try {
      final futures = <Future>[];
      
      // 1. Buscar creatorFullName se necessário
      if (creatorFullName == null && event.createdBy.isNotEmpty) {
        futures.add(
          firestore.collection('Users').doc(event.createdBy).get().then((doc) {
            creatorFullName = doc.data()?['fullName'] as String?;
            debugPrint('✅ creatorFullName: $creatorFullName');
          }),
        );
      }
      
      // 2. Buscar participants se necessário
      if (participants == null || participants!.isEmpty) {
        futures.add(
          firestore
              .collection('EventApplications')
              .where('eventId', isEqualTo: event.id)
              .where('status', whereIn: ['approved', 'autoApproved'])
              .get()
              .then((snapshot) async {
            final userIds = snapshot.docs.map((d) => d.data()['userId'] as String).toList();
            if (userIds.isEmpty) {
              participants = [];
              return;
            }
            
            // Buscar dados dos usuários em batch
            final usersSnapshot = await firestore
                .collection('Users')
                .where(FieldPath.documentId, whereIn: userIds.take(10).toList())
                .get();
            
            participants = usersSnapshot.docs.map((doc) {
              final data = doc.data();
              return {
                'userId': doc.id,
                'photoUrl': data['photoUrl'] as String?,
                'fullName': data['fullName'] as String?,
              };
            }).toList();
            debugPrint('✅ participants: ${participants?.length}');
          }),
        );
      }
      
      // 3. Buscar userApplication se necessário
      if (userApplication == null && currentUserId != null) {
        futures.add(
          firestore
              .collection('EventApplications')
              .where('eventId', isEqualTo: event.id)
              .where('userId', isEqualTo: currentUserId)
              .limit(1)
              .get()
              .then((snapshot) {
            if (snapshot.docs.isNotEmpty) {
              userApplication = snapshot.docs.first;
              debugPrint('✅ userApplication: ${snapshot.docs.first.data()['status']}');
            }
          }),
        );
      }
      
      // Aguardar todas as queries terminarem
      await Future.wait(futures);
      
    } catch (e) {
      debugPrint('⚠️ Erro ao pré-carregar dados: $e');
    }
    
    // Criar evento enriquecido com todos os dados
    final enrichedEvent = event.copyWith(
      creatorFullName: creatorFullName,
      participants: participants,
      // userApplication é tratado separadamente no controller
    );
    
    debugPrint('📦 EventModel enriquecido:');
    debugPrint('   - creatorFullName: ${enrichedEvent.creatorFullName}');
    debugPrint('   - participants: ${enrichedEvent.participants?.length ?? 0}');
    
    // Criar controller com evento enriquecido
    final controller = EventCardController(
      eventId: enrichedEvent.id,
      preloadedEvent: enrichedEvent,
    );
    
    debugPrint('🔴 Controller criado com dados pré-carregados');
    debugPrint('🔴 Abrindo showModalBottomSheet');
    
    // Mostrar confetti se for evento recém-criado
    if (showConfetti) {
      ConfettiOverlay.show(context);
    }
    
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
                message: i18n.translate('user_blocked_cannot_message'),
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
    final seededLocation = widget.viewModel.lastLocation;
    final initialTarget = seededLocation ?? const LatLng(-23.5505, -46.6333);

    return GoogleMap(
      style: _mapStyle,
      // Callback de criação
      onMapCreated: _onMapCreated,

      onCameraMoveStarted: _onCameraMoveStarted,

      // Callback a cada movimento de câmera (seguindo documentação da lib de clustering)
      onCameraMove: _onCameraMove,

      // Callback quando câmera para (após movimento) - usado para fetch de dados
      onCameraIdle: _onCameraIdle,

      // Posição inicial: usa localização persistida (Firestore) quando disponível.
      // Fallback para São Paulo apenas se não houver coords em cache/memória.
      initialCameraPosition: CameraPosition(
        target: initialTarget,
        zoom: seededLocation != null ? 12.0 : 10.0,
      ),
      
      // Permitir zoom de 3.0 (visão continental) até 20.0 (visão de rua detalhada)
      minMaxZoomPreference: const MinMaxZoomPreference(3.0, 20.0),

      // Markers customizados gerados pelo GoogleEventMarkerService
      markers: {
        ..._markers,
        ..._avatarOverlayMarkers,
      },

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
    _cameraIdleDebounce?.cancel();
  _renderDebounce?.cancel();
    _avatarBitmapsDebounce?.cancel();
    widget.viewModel.removeListener(_onEventsChanged);
    MapNavigationService.instance.unregisterMapHandler();
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }
}
