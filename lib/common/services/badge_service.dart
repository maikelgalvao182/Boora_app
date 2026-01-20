import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// 🔔 BadgeService - Controle centralizado do badge do ícone do app
/// 
/// Responsabilidades:
/// - Atualizar badge do ícone do app (iOS + Android)
/// - Manter contador sincronizado com notificações não lidas
/// - Limpar badge quando app é aberto ou notificações são lidas
/// 
/// ⚠️ IMPORTANTE:
/// - iOS: Badge precisa ser controlado manualmente pelo app
/// - Android: Badge depende do launcher (Samsung, Pixel OK; Xiaomi variável)
/// - NÃO depende do push notification - o app controla 100%
class BadgeService {
  BadgeService._();
  
  static final BadgeService instance = BadgeService._();
  
  bool _isSupported = false;
  bool _initialized = false;
  
  /// Verifica se o dispositivo suporta badge
  bool get isSupported => _isSupported;
  
  /// Inicializa o serviço verificando suporte
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      // Verificar suporte do dispositivo
      _isSupported = await FlutterAppBadger.isAppBadgeSupported();
      _initialized = true;
      
      AppLogger.info(
        '🔔 [BadgeService] Inicializado - Suporte: $_isSupported',
        tag: 'BadgeService',
      );
    } catch (e, stack) {
      AppLogger.error(
        '❌ [BadgeService] Erro ao verificar suporte',
        tag: 'BadgeService',
        error: e,
        stackTrace: stack,
      );
      _isSupported = false;
      _initialized = true;
    }
  }
  
  /// Atualiza o badge com o número de notificações não lidas
  /// 
  /// [count] - Número total de notificações não lidas (deve incluir
  /// mensagens + notificações + outros)
  Future<void> updateBadge(int count) async {
    if (!_initialized) {
      await initialize();
    }
    
    if (!_isSupported) {
      return;
    }
    
    try {
      if (count > 0) {
        await FlutterAppBadger.updateBadgeCount(count);
        AppLogger.info(
          '🔔 [BadgeService] Badge atualizado: $count',
          tag: 'BadgeService',
        );
      } else {
        await FlutterAppBadger.removeBadge();
        AppLogger.info(
          '🔔 [BadgeService] Badge removido',
          tag: 'BadgeService',
        );
      }
    } catch (e, stack) {
      AppLogger.error(
        '❌ [BadgeService] Erro ao atualizar badge',
        tag: 'BadgeService',
        error: e,
        stackTrace: stack,
      );
    }
  }
  
  /// Remove o badge do ícone (zera contador)
  Future<void> removeBadge() async {
    if (!_initialized) {
      await initialize();
    }
    
    if (!_isSupported) return;
    
    try {
      await FlutterAppBadger.removeBadge();
      AppLogger.info(
        '🔔 [BadgeService] Badge removido',
        tag: 'BadgeService',
      );
    } catch (e, stack) {
      AppLogger.error(
        '❌ [BadgeService] Erro ao remover badge',
        tag: 'BadgeService',
        error: e,
        stackTrace: stack,
      );
    }
  }
  
  /// Atualiza badge baseado em múltiplos contadores
  /// 
  /// Soma todos os tipos de notificações não lidas:
  /// - Notificações gerais (sino)
  /// - Mensagens não lidas (chat)
  /// - Ações pendentes (reviews, aplicações)
  Future<void> updateBadgeFromCounters({
    int unreadNotifications = 0,
    int unreadMessages = 0,
    int pendingActions = 0,
  }) async {
    final total = unreadNotifications + unreadMessages + pendingActions;
    await updateBadge(total);
  }
}
