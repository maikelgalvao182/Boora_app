import 'package:flutter/material.dart';

/// Singleton service para gerenciar navegação para eventos no mapa
/// 
/// Responsabilidades:
/// 1. Guardar evento pendente (vindo de notificação, deep link, trigger)
/// 2. Reagir quando o mapa estiver pronto (GoogleMapView registra handler)
/// 3. Executar navegação do mapa (mover câmera, abrir card, selecionar marker)
/// 
/// Arquitetura:
/// - Singleton pattern (única instância global)
/// - Callback registration (GoogleMapView registra handler quando pronto)
/// - Pendência automática (se mapa não estiver pronto, guarda para depois)
/// 
/// Fluxo de uso:
/// ```dart
/// // 1. Na notificação (NotificationItemWidget)
/// MapNavigationService.instance.navigateToEvent('event123');
/// 
/// // 2. No GoogleMapView.initState()
/// MapNavigationService.instance.registerMapHandler((eventId) {
///   _moveToEventAndOpenCard(eventId);
/// });
/// ```
class MapNavigationService {
  // Singleton pattern
  static final MapNavigationService _instance = MapNavigationService._internal();
  static MapNavigationService get instance => _instance;
  factory MapNavigationService() => _instance;
  MapNavigationService._internal();

  /// Evento pendente aguardando o mapa estar pronto
  String? _pendingEventId;

  /// Callback registrado pelo GoogleMapView quando estiver pronto
  Function(String eventId)? _onEventNavigationCallback;

  /// Solicita navegação para um evento
  /// 
  /// Chamado quando:
  /// - Usuário clica em uma notificação
  /// - Deep link para evento
  /// - Trigger automático
  /// 
  /// Se o mapa estiver pronto (handler registrado), executa imediatamente.
  /// Caso contrário, guarda para executar quando o mapa registrar o handler.
  void navigateToEvent(String eventId) {
    debugPrint('🗺️ [MapNavigationService] Solicitando navegação para evento: $eventId');
    
    if (_onEventNavigationCallback != null) {
      // Mapa está pronto, executar imediatamente
      debugPrint('✅ [MapNavigationService] Mapa pronto, executando navegação agora');
      _onEventNavigationCallback!(eventId);
    } else {
      // Mapa não está pronto, guardar para depois
      debugPrint('⏳ [MapNavigationService] Mapa não pronto, guardando navegação pendente');
      _pendingEventId = eventId;
    }
  }

  /// Registra o handler de navegação do mapa
  /// 
  /// Chamado pelo GoogleMapView quando estiver pronto (no initState ou onMapCreated).
  /// 
  /// Se houver navegação pendente, executa automaticamente.
  void registerMapHandler(Function(String eventId) handler) {
    debugPrint('🗺️ [MapNavigationService] Handler do mapa registrado');
    _onEventNavigationCallback = handler;

    // Se existe navegação pendente, executar agora
    if (_pendingEventId != null) {
      debugPrint('✅ [MapNavigationService] Executando navegação pendente: $_pendingEventId');
      handler(_pendingEventId!);
      _pendingEventId = null;
    }
  }

  /// Remove o handler quando o mapa for destruído
  /// 
  /// Chamado pelo GoogleMapView no dispose()
  void unregisterMapHandler() {
    debugPrint('🗺️ [MapNavigationService] Handler do mapa removido');
    _onEventNavigationCallback = null;
  }

  /// Limpa navegação pendente
  /// 
  /// Útil para cancelar navegação antes de ser executada
  void clear() {
    debugPrint('🗑️ [MapNavigationService] Limpando navegação pendente');
    _pendingEventId = null;
  }

  /// Verifica se há navegação pendente
  bool get hasPendingNavigation => _pendingEventId != null;

  /// Retorna o ID do evento pendente (se houver)
  String? get pendingEventId => _pendingEventId;
}
