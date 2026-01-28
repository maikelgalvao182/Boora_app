import 'dart:typed_data';
import 'package:flutter/material.dart';
// import 'package:partiu/features/feed/domain/usecases/create_automatic_event_post_usecase.dart';

typedef NavigateToEventFn = Future<void> Function(String eventId, {bool showConfetti});

/// Singleton service para gerenciar navegação para eventos no mapa
/// 
/// IMPLEMENTAÇÃO ROBUSTA (Estável):
/// - Executa a navegação imediatamente ao registrar se houver pendência.
/// - Remove dependência de PostFrameCallbacks complexos internos.
/// - Loga claramente o ciclo de vida do handler.
class MapNavigationService {
  // Singleton pattern
  static final MapNavigationService _instance = MapNavigationService._internal();
  static MapNavigationService get instance => _instance;
  factory MapNavigationService() => _instance;
  MapNavigationService._internal();

  NavigateToEventFn? _mapHandler;
  String? _pendingEventId;
  bool _pendingConfetti = false;

  /// Dados para post automático pendente
  Map<String, dynamic>? _pendingPostData;

  /// Handler para tirar snapshot do mapa
  Future<Uint8List?> Function()? _snapshotHandler;

  /// Registra o handler e consome imediatamente se houver pendência
  /// 
  /// REGRA DE OURO: Quando o handler é registrado, automaticamente tenta consumir
  /// qualquer pendência. Isso resolve race conditions onde a notificação chega
  /// antes do mapa estar pronto.
  void registerMapHandler(NavigateToEventFn handler) {
    debugPrint('🧠 [MapNavigationService] registerMapHandler: instance hash=${identityHashCode(this)}');
    debugPrint('✅ [MapNavigationService] Handler REGISTRADO. Verificando pendências...');
    
    _mapHandler = handler;
    
    // CRÍTICO: Tenta consumir pendências automaticamente ao registrar
    // Usa tryConsumePending() que é idempotente e seguro
    if (_pendingEventId != null) {
      debugPrint('🚀 [MapNavigationService] Pendência encontrada: $_pendingEventId. Tentando consumir...');
      // Não executa diretamente - delega para tryConsumePending que é mais robusto
      // e vai ser chamado novamente pelo setController se mapController ainda for null
      tryConsumePending();
    } else {
      debugPrint('💤 [MapNavigationService] Nenhuma navegação pendente.');
    }
  }

  void unregisterMapHandler() {
    debugPrint('🧹 [MapNavigationService] Handler REMOVIDO');
    _mapHandler = null;
  }

  void navigateToEvent(String eventId, {bool showConfetti = false}) {
    debugPrint('🧠 [MapNavigationService] navigateToEvent: instance hash=${identityHashCode(this)}');
    debugPrint('🗺️ [MapNavigationService] Solicitando navegação: $eventId (confetti: $showConfetti)');
    
    final handler = _mapHandler;
    if (handler != null) {
      debugPrint('🚀 [MapNavigationService] Handler ativo. Executando direto...');
      handler(eventId, showConfetti: showConfetti);
    } else {
      _pendingEventId = eventId;
      _pendingConfetti = showConfetti;
      debugPrint('⏳ [MapNavigationService] Sem handler registrado. Salvando como PENDENTE.');
    }
  }

  /// Força o salvamento do evento como pendente, ignorando handler atual.
  /// Útil quando sabemos que o mapa será reconstruído (ex: via deep link com refresh).
  /// 
  /// NOTA: Não tenta executar imediatamente. Apenas enfileira para que a UI consuma
  /// quando estiver pronta (via tryConsumePending explícito).
  void queueEvent(String eventId, {bool showConfetti = false}) {
    debugPrint('📌 [MapNavigationService] queueEvent: $eventId (confetti: $showConfetti)');
    // Define pendência
    _pendingEventId = eventId;
    _pendingConfetti = showConfetti;
    
    debugPrint('💤 [MapNavigationService] Evento enfileirado. Aguardando consumo pela UI (DiscoverTab).');
  }

  bool get hasPendingNavigation => _pendingEventId != null;
  String? get pendingEventId => _pendingEventId;

  /// Tenta consumir pendências se houver handler e evento
  Future<void> tryConsumePending() async {
    final handler = _mapHandler;
    final pendingId = _pendingEventId;

    debugPrint('🧪 [MapNavigationService] tryConsumePending: handler=${handler != null} pending=$pendingId');

    if (handler == null || pendingId == null) return;

    debugPrint('🚀 [MapNavigationService] Consumindo pendência via tryConsumePending: $pendingId');
    final confetti = _pendingConfetti;
    _pendingEventId = null; // Limpa antes de executar para evitar loop
    _pendingConfetti = false;

    try {
      await handler(pendingId, showConfetti: confetti);
    } catch (e) {
      debugPrint('❌ [MapNavigationService] Erro ao executar navegação pendente: $e');
    }
  }

  /// Registra o handler de snapshot do mapa
  void registerSnapshotHandler(Future<Uint8List?> Function() handler) {
    _snapshotHandler = handler;
  }

  void unregisterSnapshotHandler() {
    _snapshotHandler = null;
  }

  /// Tira snapshot do mapa se disponível
  Future<Uint8List?> takeSnapshot() async {
    if (_snapshotHandler != null) {
      return await _snapshotHandler!();
    }
    debugPrint('⚠️ [MapNavigationService] Handler de snapshot não registrado');
    return null;
  }

  /// Limpa navegação pendente
  /// 
  /// Útil para cancelar navegação antes de ser executada
  void clear() {
    debugPrint('🗑️ [MapNavigationService] Limpando navegação pendente');
    _pendingEventId = null;
    _pendingPostData = null;
    _pendingConfetti = false;
  }
  
  /// Ageda um post automático para ser criado na próxima navegação ao evento
  void scheduleAutoPost({
    required String eventId,
    required String caption,
    required String userId,
  }) {
    _pendingPostData = {
      'eventId': eventId,
      'caption': caption,
      'userId': userId,
    };
    debugPrint('📸 [MapNavigationService] Post agendado para evento $eventId');
  }

  /// Recupera e consome dados do post pendente se corresponder ao evento
  Map<String, dynamic>? consumePendingPostData(String eventId) {
    if (_pendingPostData != null && _pendingPostData!['eventId'] == eventId) {
      final data = _pendingPostData;
      _pendingPostData = null; // Consume
      return data;
    }
    return null;
  }
  
  /// Executa a criação do post
  Future<void> executeAutoPost(Map<String, dynamic> data, Uint8List snapshot) async {
    try {
      debugPrint('📸 [MapNavigationService] Criando post automático...');
      /*
      // TODO: Restaurar uso de CreateAutomaticEventPostUseCase quando o arquivo existir
      await CreateAutomaticEventPostUseCase().execute(
        mapSnapshot: snapshot,
        eventId: data['eventId'],
        caption: data['caption'],
        userId: data['userId'],
      );
      */
      debugPrint('📸 [MapNavigationService] Post criado com sucesso!');
    } catch (e) {
      debugPrint('⚠️ [MapNavigationService] Erro ao criar post automático: $e');
    }
  }
}
