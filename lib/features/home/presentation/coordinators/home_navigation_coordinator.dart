import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/presentation/services/map_navigation_service.dart';
import 'package:partiu/features/home/presentation/coordinators/home_tab_coordinator.dart';

/// Coordinator de alto nível para navegação complexa na Home.
/// Orquestra a interação entre troca de abas e ações específicas dentro das abas (ex: mapa).
class HomeNavigationCoordinator {
  static final HomeNavigationCoordinator _instance = HomeNavigationCoordinator._internal();
  static HomeNavigationCoordinator get instance => _instance;

  HomeNavigationCoordinator._internal();

  /// Abre um evento específico no mapa, garantindo que a aba do mapa esteja ativa
  /// e que o evento seja processado mesmo se o mapa estiver em background.
  /// 
  /// [showConfetti] - Se true, mostra confetti ao abrir o EventCard.
  ///                  Usar apenas quando o evento foi CRIADO pelo usuário.
  Future<void> openEventOnMap(String eventId, {bool showConfetti = false}) async {
    debugPrint('🧭 [HomeNavigationCoordinator] openEventOnMap: $eventId (confetti: $showConfetti)');

    // 1. Seta a intenção de navegação (enfileira SOMENTE)
    // Agora o queueEvent é passivo, não inicia execução automática.
    MapNavigationService.instance.queueEvent(eventId, showConfetti: showConfetti);

    // 2. Troca para a aba do Mapa (index 0)
    // Usamos forceNotify: true para garantir que o DiscoverTab receba o evento e tente consumir
    // a pendência, mesmo que já estejamos na aba 0.
    HomeTabCoordinator.instance.goToTab(0, forceNotify: true);
    
    debugPrint('✅ [HomeNavigationCoordinator] Navegação enfileirada e aba solicitada.');
  }
}
