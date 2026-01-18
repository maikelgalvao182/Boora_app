import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:partiu/common/utils/app_logger.dart';

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
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  
  /// Verifica se o dispositivo suporta badge
  bool get isSupported => _isSupported;
  
  /// Inicializa o serviço verificando suporte
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      _isSupported = Platform.isIOS;
      _initialized = true;
      
      AppLogger.info(
        '🔔 [BadgeService] Inicializado - Suporte: $_isSupported',
      );
    } catch (e, stack) {
      AppLogger.error(
        '❌ [BadgeService] Erro ao verificar suporte',
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
      if (Platform.isIOS) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                DarwinFlutterLocalNotificationsPlugin>()
            ?.setBadgeCount(count);
      }
    } catch (e, stack) {
      AppLogger.error(
        '❌ [BadgeService] Erro ao atualizar badge',
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
      if (Platform.isIOS) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                DarwinFlutterLocalNotificationsPlugin>()
            ?.setBadgeCount(0);
      }
    } catch (e, stack) {
      AppLogger.error(
        '❌ [BadgeService] Erro ao remover badge',
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
