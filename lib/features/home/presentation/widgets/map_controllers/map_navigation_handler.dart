import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/repositories/event_map_repository.dart';
import 'package:partiu/features/home/presentation/coordinators/home_tab_coordinator.dart';
import 'package:partiu/features/home/presentation/services/map_navigation_service.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/event_card_presenter.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/map_render_controller.dart';

class MapNavigationHandler {
  final BuildContext context;
  final bool Function() isMounted;
  final MapViewModel viewModel;
  final MapRenderController renderController;
  final EventCardPresenter eventPresenter;
  GoogleMapController? mapController;
  
  // Prevent duplicate registration
  bool _registered = false;

  MapNavigationHandler({
    required this.context,
    required this.isMounted,
    required this.viewModel,
    required this.renderController,
    required this.eventPresenter,
  });

  void setController(GoogleMapController? controller) {
    mapController = controller;
    
    // Se controller ficou disponível, tenta consumir pendências do SINGLETON
    // Isso é importante porque quando mapController era null, re-enfileiramos no singleton
    if (mapController != null) {
      _tryConsumeWithRetry();
    }
  }
  
  /// Tenta consumir pendências com retry para garantir que não perca eventos
  /// em dispositivos mais lentos onde o timing pode variar
  Future<void> _tryConsumeWithRetry() async {
    // Aguarda um pouco para o mapa estar totalmente pronto
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Tenta até 5 vezes com intervalos crescentes
    for (int attempt = 0; attempt < 5; attempt++) {
      final pendingId = MapNavigationService.instance.pendingEventId;
      if (pendingId == null) {
        if (attempt == 0) {
          debugPrint('💤 [MapNavigationHandler] Nenhuma pendência no singleton.');
        }
        return; // Sem pendência, nada a fazer
      }
      
      if (mapController == null) {
        debugPrint('⏳ [MapNavigationHandler] Controller voltou a ser null. Abortando retry.');
        return;
      }
      
      if (!isMounted()) {
        debugPrint('⏳ [MapNavigationHandler] Widget desmontado. Abortando retry.');
        return;
      }
      
      debugPrint('🔁 [MapNavigationHandler] Tentativa ${attempt + 1}/5 de consumir pendência: $pendingId');
      
      await MapNavigationService.instance.tryConsumePending();
      
      // Verifica se foi consumido com sucesso (pendingEventId deve ser null)
      if (MapNavigationService.instance.pendingEventId == null) {
        debugPrint('✅ [MapNavigationHandler] Pendência consumida com sucesso!');
        return;
      }
      
      // Se ainda tem pendência, pode ser que o handler re-enfileirou (controller null temporário?)
      // Aguarda um pouco mais antes de tentar novamente
      final delay = Duration(milliseconds: 200 * (attempt + 1));
      debugPrint('⏳ [MapNavigationHandler] Pendência ainda existe. Aguardando ${delay.inMilliseconds}ms...');
      await Future.delayed(delay);
    }
    
    debugPrint('⚠️ [MapNavigationHandler] Não conseguiu consumir pendência após 5 tentativas.');
  }

  void registerMapServices() {
    debugPrint('🧨 [MapNavigationHandler] registerMapServices EXECUTOU');
    debugPrint('🧠 [MapNavigationHandler] Service hash=${identityHashCode(MapNavigationService.instance)}');
    
    if (_registered) {
      debugPrint('⚠️ [MapNavigationHandler] Já registrado. Verificando pendências no singleton...');
      // Já registrado, tenta consumir pendências se controller estiver pronto
      if (mapController != null && MapNavigationService.instance.hasPendingNavigation) {
         setController(mapController);
      }
      return;
    }
    _registered = true;

    debugPrint('🧩 [MapNavigationHandler] registerMapServices chamado (mounted=${isMounted()})');
    debugPrint('🧠 [MapNavigationHandler] MapNavigationService hash=${identityHashCode(MapNavigationService.instance)}');
    
    MapNavigationService.instance.registerMapHandler(
      (eventId, {showConfetti = false}) async {
        if (!isMounted()) return;
        await _handleEventNavigation(eventId, showConfetti: showConfetti);
      },
    );
    MapNavigationService.instance.registerSnapshotHandler(() async {
      return await mapController?.takeSnapshot();
    });
  }

  void unregisterMapServices() {
    MapNavigationService.instance.unregisterMapHandler();
    MapNavigationService.instance.unregisterSnapshotHandler();
  }

  Future<void> _handleEventNavigation(String eventId, {bool showConfetti = false}) async {
    debugPrint('🗺️ [MapNavigationHandler] Navegando para evento: $eventId (confetti: $showConfetti)');

    // [FIX] Garantir que estamos na Tab 0 (Mapa) antes de prosseguir
    // Isso evita que o EventCard abra sobre outras telas se o handler tiver ficado "preso"
    // ou se o switch de tab ainda estiver processando.
    int tabRetries = 0;
    while (HomeTabCoordinator.instance.currentIndex != 0) {
      if (tabRetries > 20) { // ~2 segundos de tolerância
        debugPrint('⚠️ [MapNavigationHandler] Timeout: Tab map (0) não ativa (atual=${HomeTabCoordinator.instance.currentIndex}). Re-enfileirando e abortando.');
        // Re-enfileira para tentar novamente quando o usuário voltar para o mapa manualmente ou via retry
        MapNavigationService.instance.queueEvent(eventId, showConfetti: showConfetti);
        return; 
      }
      debugPrint('⏳ [MapNavigationHandler] Aguardando Tab 0 ativa (atual=${HomeTabCoordinator.instance.currentIndex})...');
      await Future.delayed(const Duration(milliseconds: 100));
      tabRetries++;
    }
    
    // [FIX] Se o controller ainda não existe, re-enfileira no SINGLETON para garantir
    // que a navegação não se perca se o widget for reconstruído (ex: app voltando de background).
    // Isso é crucial porque o _queuedEventId local se perde quando o widget é recriado.
    if (mapController == null) {
      debugPrint('⏳ [MapNavigationHandler] MapController ainda nulo. Re-enfileirando no singleton: $eventId');
      MapNavigationService.instance.queueEvent(eventId, showConfetti: showConfetti);
      return;
    }
    
    if (!isMounted()) return;
    
    EventModel? event;
    
    try {
      event = viewModel.events.firstWhere((e) => e.id == eventId);
      debugPrint('✅ [MapNavigationHandler] Evento encontrado na lista local: ${event.title}');
    } catch (_) {
      debugPrint('⚠️ [MapNavigationHandler] Evento não encontrado na lista local, buscando do Firestore...');
      
      try {
        event = await EventMapRepository().getEventById(eventId);
        
        if (event == null) {
          debugPrint('❌ [MapNavigationHandler] Evento não encontrado no Firestore: $eventId');
          return;
        }
        
        debugPrint('✅ [MapNavigationHandler] Evento carregado do Firestore: ${event.title}');
        
        // [FIX] Pinning + Injection
        // 1. Pina o evento para protegê-lo do próximo refresh de bounds (que pode vir vazio)
        viewModel.pinEvent(event.id);
        
        // 2. Injeta no ViewModel
        await viewModel.injectEvent(event);
        
        // 3. Aguarda um frame para garantir que os listeners (Markers) foram notificados
        // e que o evento já existe na "source of truth" da UI.
        await Future.delayed(const Duration(milliseconds: 50));
        
      } catch (e) {
        debugPrint('❌ [MapNavigationHandler] Erro ao buscar evento do Firestore: $e');
        return;
      }
    }
    
    if (!isMounted()) return;

    renderController.scheduleRender();
    
    if (mapController != null) {
      final target = LatLng(event.lat, event.lng);
      await mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(target, 15.0),
      );
      debugPrint('📍 [MapNavigationHandler] Câmera movida para: ${event.title}');
    }
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!isMounted()) return;
    
    eventPresenter.onMarkerTap(context, event, showConfetti: showConfetti);
  }
}
