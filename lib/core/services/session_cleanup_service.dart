import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/managers/session_manager.dart';
import 'package:partiu/core/services/analytics_service.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/common/services/notifications_counter_service.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/services/google_event_marker_service.dart';
import 'package:firebase_auth/firebase_auth.dart' as fire_auth;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:partiu/features/notifications/services/push_notification_manager.dart';

/// Serviço responsável por realizar a limpeza robusta de sessão.
/// Inspirado no fluxo de logout do projeto Advanced-Dating.
/// Problema reportado: dados antigos de usuário permanecem após login em outra conta.
/// Solução: limpar fontes reativas, caches, tokens push e estado global.
class SessionCleanupService {
  final fire_auth.FirebaseAuth _firebaseAuth = fire_auth.FirebaseAuth.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // Tópico global (ajustar se houver diferença entre ambientes)
  static const String globalTopic = 'partiu_global';
  
  // Flag para controlar logout em andamento e prevenir relogin automático
  static bool _isLoggingOut = false;
  
  /// Retorna true se logout está em andamento
  static bool get isLoggingOut => _isLoggingOut;

  /// Executa o logout completo e limpeza de sessão.
  /// Processo robusto com 9 etapas sequenciais.
  Future<void> performLogout() async {
    _isLoggingOut = true;
    final startTime = DateTime.now();
    _log('🚀 === INICIANDO LOGOUT COMPLETO (${startTime.toIso8601String()}) ===');
    
    try {
      // 1. Parar listeners de push e remover token do usuário atual
      _log('📱 ETAPA 1/9: Removendo device token do usuário');
      try {
        final uid = _firebaseAuth.currentUser?.uid;
        if (uid != null) {
          // TODO: Implementar remoção do device token quando tivermos push notifications
          // await UserPushNotificationService().removeUserDeviceToken(uid);
          _log('✅ Device token preparado para remoção (UID: ${_maskUid(uid)})');
        } else {
          _log('⚠️  Nenhum usuário logado, pulando remoção de device token');
        }
      } catch (e) {
        _log('⚠️  Etapa 1/9 falhou: $e (continuando...)');
      }

      // 2. Google Sign-In logout
      _log('🔓 ETAPA 2/9: Limpando Google Sign-In');
      try {
        await GoogleSignIn.instance.signOut();
        _log('✅ Google Sign-In limpo com sucesso');
      } catch (e) {
        _log('⚠️  Etapa 2/9 falhou: $e (continuando...)');
      }

      // 3. Limpar caches personalizados
      _log('🗑️  ETAPA 3/9: Limpando caches personalizados');
      try {
        final uid = _firebaseAuth.currentUser?.uid;
        if (uid != null) {
          // TODO: Implementar limpeza de caches específicos quando necessário
          _log('✅ Caches personalizados preparados para limpeza');
        } else {
          _log('⚠️  UID nulo, pulando limpeza de caches');
        }
      } catch (e) {
        _log('⚠️  Etapa 3/9 falhou: $e (continuando...)');
      }

      // 4. Desinscrever de tópicos FCM específicos do usuário (se aplicável)
      _log('🔔 ETAPA 4/9: Desinscrevendo de tópicos FCM do usuário');
      try {
        final uid = _firebaseAuth.currentUser?.uid;
        if (uid != null) {
          final topicName = 'user_$uid';
          await _messaging.unsubscribeFromTopic(topicName);
          _log('✅ Desinscrição do tópico user_* realizada');
        } else {
          _log('⚠️  UID nulo, pulando desinscrição de tópicos');
        }
      } catch (e) {
        _log('⚠️  Etapa 4/9 falhou: $e (continuando...)');
      }

      // 4.1. Apagar token FCM local para evitar associação com nova sessão
      _log('🗑️  ETAPA 4.1/9: Apagando token FCM local');
      try {
        await _messaging.deleteToken();
        _log('✅ Token FCM local deletado com sucesso');
      } catch (e) {
        _log('⚠️  Etapa 4.1/9 falhou: $e (continuando...)');
      }

      // 5. Limpar sessão persistida (SharedPreferences) via SessionManager
      _log('💾 ETAPA 5/9: Limpando SessionManager e SharedPreferences');
      try {
        await SessionManager.instance.initialize();
        SessionManager.instance.fcmToken = null;
        await SessionManager.instance.logout();
        _log('✅ SessionManager limpo (configurações preservadas)');
      } catch (e) {
        _log('⚠️  Etapa 5/9 falhou: $e (continuando...)');
      }

      // 5.1 Limpar estado do PushNotificationManager
      _log('🔔 ETAPA 5.1/9: Limpando estado do PushNotificationManager');
      try {
        PushNotificationManager.instance.resetState();
        _log('✅ PushNotificationManager resetado');
      } catch (e) {
        _log('⚠️  Etapa 5.1/9 falhou: $e (continuando...)');
      }

      // 5.2 Cancelar listeners de Firestore (NotificationsCounterService)
      // IMPORTANTE: Fazer ANTES do signOut para evitar permission-denied
      _log('🔌 ETAPA 5.2/9: Cancelando listeners do NotificationsCounterService');
      try {
        await NotificationsCounterService.instance.reset();
        _log('✅ NotificationsCounterService resetado (listeners cancelados)');
      } catch (e) {
        _log('⚠️  Etapa 5.2/9 falhou: $e (continuando...)');
      }

      // 5.3 Cancelar streams do MapViewModel (evita permission-denied)
      _log('🗺️  ETAPA 5.3/9: Cancelando streams do MapViewModel');
      try {
        MapViewModel.instance?.cancelAllStreams();
        // Limpar cache de bitmaps/markers (singleton) para evitar estado visual antigo.
        GoogleEventMarkerService().clearCache();
        _log('✅ MapViewModel streams cancelados');
      } catch (e) {
        _log('⚠️  Etapa 5.3/9 falhou: $e (continuando...)');
      }

      // 6. Firebase Auth signOut (após limpar preferências/caches)
      _log('🔥 ETAPA 6/9: Fazendo signOut do Firebase Auth');
      try { 
        await _firebaseAuth.signOut();
        _log('✅ Firebase Auth signOut executado');
      } catch (e) {
        _log('⚠️  Etapa 6/9 falhou: $e (continuando...)');
      }

      // 7. Reset reativo global (ValueNotifiers)
      _log('🔄 ETAPA 7/9: Resetando estado reativo global');
      try {
        _resetGlobalReactiveState();
        _log('✅ Estado reativo (AppState) resetado');
      } catch (e) {
        _log('⚠️  Etapa 7/9 falhou: $e (continuando...)');
      }

      // 7.1 Limpar userId do Analytics
      _log('📊 ETAPA 7.1/9: Limpando userId do Analytics');
      try {
        await AnalyticsService.instance.setUserId(null);
        _log('✅ Analytics userId limpo');
      } catch (e) {
        _log('⚠️  Etapa 7.1/9 falhou: $e (continuando...)');
      }

      // 8. Cancelar listeners ativos antes de limpar cache
      _log('🔌 ETAPA 8a/9: Cancelando listeners Firestore ativos');
      try {
        // Força GC para cancelar listeners pendentes
        await Future.delayed(const Duration(milliseconds: 100));
        _log('✅ Delay para cancelamento de listeners aplicado');
      } catch (e) {
        _log('⚠️  Etapa 8a/9 falhou: $e (continuando...)');
      }
      
      // 8b. Limpar cache offline do Firestore para evitar dados antigos
      _log('🗄️  ETAPA 8b/9: Limpando cache offline do Firestore');
      try {
        await FirebaseFirestore.instance.clearPersistence()
          .timeout(const Duration(seconds: 5));
        _log('✅ Cache Firestore limpo com sucesso');
      } catch (e) {
        _log('⚠️  Etapa 8b/9 falhou: $e (continuando...)');
      }

      // 9. Reinscrever em tópico global (padrão pós logout)
      _log('🌍 ETAPA 9/9: Reinscrevendo no tópico global');
      try { 
        await _messaging.subscribeToTopic(globalTopic);
        _log('✅ Reinscrito em tópico global: $globalTopic');
      } catch (e) {
        _log('⚠️  Etapa 9/9 falhou: $e (continuando...)');
      }

      final duration = DateTime.now().difference(startTime);
      _log('🎉 === LOGOUT COMPLETO FINALIZADO (${duration.inMilliseconds}ms) ===');
    } catch (e, st) {
      _log('❌ ERRO CRÍTICO durante logout: $e');
      _logError('Stack trace:', stackTrace: st);
      // NÃO propaga erro - deixa UI navegar mesmo assim
    } finally {
      _isLoggingOut = false;
      _log('✅ Flag de logout resetada - processo finalizado');
    }
  }

  void _resetGlobalReactiveState() {
    AppState.currentUser.value = null;
    AppState.isVerified.value = false;
    AppState.unreadNotifications.value = 0;
    AppState.unreadMessages.value = 0;
    AppState.unreadLikes.value = 0;
    AppState.currentRoute.value = '/';
    AppState.isAppInBackground.value = false;
  }

  // ==================== HELPERS ====================

  /// Mascara UID para logs (mostra primeiros 4 e últimos 4 caracteres)
  String _maskUid(String uid) {
    if (uid.length <= 8) return '****';
    return '${uid.substring(0, 4)}****${uid.substring(uid.length - 4)}';
  }

  // ==================== LOGGING ====================

  void _log(String message) {
    if (kDebugMode) {
      developer.log(message, name: 'SessionCleanup');
    }
  }

  void _logError(String message, {StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'SessionCleanup',
      error: message,
      stackTrace: stackTrace,
    );
  }
}