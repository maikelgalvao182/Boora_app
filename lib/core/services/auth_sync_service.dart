import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fire_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/models/user.dart' as app_user;
import 'package:partiu/core/managers/session_manager.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/common/services/notifications_counter_service.dart';
import 'package:partiu/features/notifications/services/fcm_token_service.dart';
import 'package:partiu/features/subscription/services/simple_revenue_cat_service.dart';
import 'package:partiu/core/services/device_identity_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/services/location_background_updater.dart';
import 'package:partiu/core/services/location_service.dart';
import 'package:get_it/get_it.dart';

/// Serviço de orquestração de autenticação que trabalha COM SessionManager.
/// 
/// Segue o padrão do Advanced-Dating:
/// - Escuta Firebase Auth
/// - Carrega dados do Firestore
/// - Salva no SessionManager (fonte de verdade)
/// - SessionManager sincroniza automaticamente com AppState
/// 
/// SPLASH SCREEN:
/// O splash é uma MÁSCARA de estado real, não decoração.
/// - `initialized` só é true quando AUTH + SESSION estão prontos
/// - Sem delays artificiais - baseado 100% em estado real
class AuthSyncService extends ChangeNotifier {
  /// Auth já respondeu (Firebase disse se há user ou não)
  bool _authResolved = false;
  
  /// Sessão pronta (login/logout completo, serviços inicializados)
  bool _sessionReady = false;
  
  bool _notificationServiceInitialized = false; // Flag para inicializar apenas uma vez
  bool _locationSyncSchedulerInitialized = false; // Flag para LocationSyncScheduler
  bool _deviceIdentityChecked = false;
  StreamSubscription<fire_auth.User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  /// Usuário do Firebase Auth (delegado)
  fire_auth.User? get firebaseUser => fire_auth.FirebaseAuth.instance.currentUser;
  
  /// Usuário completo da aplicação (delegado para SessionManager)
  app_user.User? get appUser => SessionManager.instance.currentUser;
  
  /// Indica se o serviço foi inicializado (auth resolvido + sessão pronta)
  /// 
  /// REGRA DE OURO: Splash só some quando este getter retornar true.
  /// Isso é um COMPUTED STATE, não um flag manual.
  bool get initialized => _authResolved && _sessionReady;
  
  /// Indica se o usuário está logado (delegado para SessionManager)
  bool get isLoggedIn => SessionManager.instance.isLoggedIn && SessionManager.instance.currentUser != null;
  
  /// ID do usuário logado (delegado para AppState)
  String? get userId => AppState.currentUserId;

  AuthSyncService() {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🏗️ AuthSyncService() construtor chamado!');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _initializeAuth();
  }

  /// Reavalia estado atual do FirebaseAuth (útil após `currentUser.reload()`)
  /// para refletir mudanças de `emailVerified` sem depender de um novo authStateChanges.
  Future<void> refreshCurrentUser() async {
    await _handleAuthStateChange(fire_auth.FirebaseAuth.instance.currentUser);
  }

  bool _requiresEmailVerification(fire_auth.User user) {
    final hasEmail = (user.email ?? '').trim().isNotEmpty;
    final isPasswordProvider = user.providerData.any((p) => p.providerId == 'password');
    return hasEmail && isPasswordProvider;
  }

  void _initializeAuth() {
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _log('🔄 _initializeAuth() CHAMADO!');
    _log('🔄 Inicializando AuthSyncService');
    
    // Carregar usuário inicial do SessionManager se existir
    final sessionUser = SessionManager.instance.currentUser;
    if (sessionUser != null) {
      _log('📱 Usuário encontrado no SessionManager: ${sessionUser.userId}');
    }
    
    _log('🔄 Criando listener de authStateChanges...');
    // Escuta mudanças no Firebase Auth
    _authSubscription = fire_auth.FirebaseAuth.instance
        .authStateChanges()
        .listen(_handleAuthStateChange);
    _log('✅ Listener de authStateChanges criado!');
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  Future<void> _handleAuthStateChange(fire_auth.User? user) async {
    try {
      _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _log('🔄 _handleAuthStateChange DISPARADO!');
      _log('🔄 Auth state changed: ${user?.uid ?? 'null'}');
      _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      // ✅ Auth respondeu - Firebase disse se há user ou não
      _authResolved = true;
      
      // Reset session ready - será marcado quando tudo estiver pronto
      _sessionReady = false;
      _deviceIdentityChecked = false;

      // Cancela subscription anterior do usuário se existir
      await _userSubscription?.cancel();
      _userSubscription = null;

      if (user != null) {
        // 🔒 Email/senha exige e-mail verificado antes de iniciar sessão do app
        // (mantém FirebaseAuth logado, mas não inicia SessionManager/AppState)
        if (_requiresEmailVerification(user) && user.emailVerified == false) {
          _log('🔒 Email não verificado (provider=password). Mantendo sessão do app deslogada.');

          await SessionManager.instance.logout();

          // ✅ Sessão pronta (mas usuário ainda não pode acessar rotas protegidas)
          _sessionReady = true;
          notifyListeners();
          return;
        }

        // Usuário logado - carregar dados completos do Firestore e salvar no SessionManager
        _log('✅ Usuário logado, carregando dados do Firestore: ${user.uid}');

        // NOTA: RevenueCat login movido para dentro de _loadUserDataAndSaveToSession
        // para garantir que só logamos se o usuário existir no Firestore
        // _sessionReady será marcado dentro do snapshot listener quando tudo estiver pronto

        await _loadUserDataAndSaveToSession(user.uid);
        // NOTA: NotificationsCounterService.initialize() agora é chamado dentro do snapshot listener
      } else {
        // Usuário deslogado - limpar SessionManager (que limpa AppState automaticamente)
        _log('🚪 Usuário deslogado, limpando SessionManager');
        
        // 🔐 REVENUECAT LOGOUT
        try {
          await SimpleRevenueCatService.logout();
          _log('✅ RevenueCat logout realizado');
        } catch (e, stack) {
          _logError('❌ Erro ao fazer logout no RevenueCat', e, stack);
        }
        
        // 🌍 LOCATION SYNC SCHEDULER STOP
        if (_locationSyncSchedulerInitialized) {
          _log('🛑 Parando LocationSyncScheduler...');
          try {
            LocationSyncScheduler.stop();
            _locationSyncSchedulerInitialized = false;
            _log('✅ LocationSyncScheduler parado');
          } catch (e, stack) {
            _logError('❌ Erro ao parar LocationSyncScheduler', e, stack);
          }
        }

        await SessionManager.instance.logout();
        
        // Resetar contadores de notificações e badge do ícone
        await NotificationsCounterService.instance.reset();
        
        // Resetar flag para permitir reinicialização no próximo login
        _notificationServiceInitialized = false;
        _deviceIdentityChecked = false;
        
        // ✅ Sessão pronta (logout completo)
        _sessionReady = true;
        _log('✅ Logout completo - initialized: $initialized');
      }

      // Notifica listeners (GoRouter, widgets, etc.)
      notifyListeners();
    } catch (e, stack) {
      _logError('❌ Erro ao processar mudança de auth', e, stack);
      
      // Mesmo com erro, marca como inicializado para não travar a UI
      _authResolved = true;
      _sessionReady = true;
      notifyListeners();
    }
  }

  /// Carrega dados do usuário do Firestore e salva no SessionManager (padrão Advanced-Dating)
  Future<void> _loadUserDataAndSaveToSession(String uid) async {
    try {
        _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        _log('🔥🔥🔥 _loadUserDataAndSaveToSession CHAMADO!');
        _log('🔥🔥🔥 Carregando dados do usuário do Firestore: $uid');
        _log('🔥 Criando snapshot listener para Users/$uid...');
        _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        
      // Escuta atualizações do Firestore em tempo real
      _userSubscription = FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .snapshots()
          .listen((snapshot) async {
        try {
          _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          _log('🔥 SNAPSHOT RECEBIDO para $uid - exists: ${snapshot.exists}');
          _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          
          if (!snapshot.exists) {
            _log('Documento do usuário não existe: $uid');
            await SessionManager.instance.logout();
            // Sessão pronta (documento não existe = logout)
            if (!_sessionReady) {
              _sessionReady = true;
              notifyListeners();
            }
            return;
          }

          final data = snapshot.data();
          if (data == null) {
            _log('Dados do usuário são null: $uid');
            await SessionManager.instance.logout();
            // Sessão pronta (dados null = logout)
            if (!_sessionReady) {
              _sessionReady = true;
              notifyListeners();
            }
            return;
          }

          if (!_deviceIdentityChecked) {
            _log('📱 Verificando device blacklist...');
            final checkResult =
                await DeviceIdentityService.instance.checkAndRegisterOnLogin();

            if (checkResult.blocked) {
              _log('⛔ Dispositivo bloqueado. Encerrando sessão.');

              ToastService.showError(
                message: checkResult.reason ??
                    'Dispositivo bloqueado. Contate o suporte.',
              );

              await _userSubscription?.cancel();
              _userSubscription = null;
              await SessionManager.instance.logout();
              await fire_auth.FirebaseAuth.instance.signOut();

              if (!_sessionReady) {
                _sessionReady = true;
                notifyListeners();
              }
              return;
            }

            _deviceIdentityChecked = true;
            _log('✅ Device aprovado e registrado');
          }

          // CORREÇÃO: Garantir que o documento tem o campo userId
          if (!data.containsKey('userId') && uid.isNotEmpty) {
            data['userId'] = uid;
          }
          
          final user = app_user.User.fromDocument(data);
          _log('✅ Dados carregados do Firestore, salvando no SessionManager: ${user.userId}');
          
          // CHAVE: Salvar no SessionManager - ele sincroniza automaticamente com AppState
          await SessionManager.instance.login(user);

          // 🔐 REVENUECAT LOGIN (Agora seguro, pois sabemos que o usuário existe no Firestore)
          try {
            await SimpleRevenueCatService.login(user.userId);
            _log('✅ RevenueCat login realizado para: ${user.userId}');
          } catch (e, stack) {
            _logError('❌ Erro ao fazer login no RevenueCat', e, stack);
          }
          
          _log('✅ Usuário salvo no SessionManager - AppState.currentUserId: ${AppState.currentUserId}');
          _log('🔔 _notificationServiceInitialized: $_notificationServiceInitialized');
          
          // Inicializar contadores de notificações APÓS o usuário estar no AppState
          // Mas apenas uma vez (não a cada update do snapshot)
          if (!_notificationServiceInitialized) {
            _log('🔔🔔🔔 Inicializando NotificationsCounterService pela primeira vez...');
            _log('🔔 AppState.currentUserId: ${AppState.currentUserId}');
            
            _log('📊 [INIT] Etapa 1/3: Inicializando NotificationsCounterService...');
            await NotificationsCounterService.instance.initialize();
            _log('✅ [INIT] Etapa 1/3: NotificationsCounterService inicializado');
            
            // Inicializar FCM Token Service
            _log('📊 [INIT] Etapa 2/3: Inicializando FcmTokenService...');
            await FcmTokenService.instance.initialize();
            _log('✅ [INIT] Etapa 2/3: FcmTokenService inicializado');
            
            _notificationServiceInitialized = true;
            _log('📊 [INIT] Etapa 3/3: Marcando serviços como inicializados');
            _log('✅ [INIT] Etapa 3/3: Todos os serviços de notificação inicializados');
            
            // 🌍 Inicializar LocationSyncScheduler para atualização automática de localização
            if (!_locationSyncSchedulerInitialized) {
              _log('📊 [INIT] Etapa 4/4: Inicializando LocationSyncScheduler...');
              try {
                // ServiceLocator.init() já registrou o LocationService no GetIt no boot do app.
                final locationService = GetIt.instance.get<LocationService>();
                LocationSyncScheduler.start(
                  locationService,
                  config: LocationConfig.standard,
                );
                _locationSyncSchedulerInitialized = true;
                _log('✅ [INIT] Etapa 4/4: LocationSyncScheduler iniciado');
              } catch (e, stack) {
                _logError('❌ Erro ao iniciar LocationSyncScheduler', e, stack);
              }
            } else {
              _log('🌍 LocationSyncScheduler já foi inicializado anteriormente');
            }
            
            _log('🎉 [INIT] INICIALIZAÇÃO COMPLETA - Chamando notifyListeners()...');
          } else {
            _log('🔔 NotificationsCounterService já foi inicializado anteriormente');
            // Verificar se os listeners ainda estão ativos (pode ter sido resetado por hot reload)
            if (NotificationsCounterService.instance.isActive) {
              _log('🔔 Listeners ainda ativos, não precisa reinicializar');
            } else {
              _log('🔔 Listeners inativos, reinicializando...');
              await NotificationsCounterService.instance.initialize();
            }
          }
          
          // ✅ Sessão pronta - todos os serviços inicializados
          final wasSessionReady = _sessionReady;
          if (!_sessionReady) {
            _sessionReady = true;
            _log('✅ Sessão pronta - initialized: $initialized');
          }
          
          // 🔑 IMPORTANTE: Só notifica GoRouter se a sessão ACABOU de ficar pronta.
          // Mudanças subsequentes no documento do usuário (ex: followersCount, followingCount)
          // não devem disparar rebuild do GoRouter, pois isso causa flash na UI.
          if (!wasSessionReady) {
            _log('📊 [INIT] Chamando notifyListeners() final...');
            notifyListeners();
            _log('✅ [INIT] notifyListeners() completo - UI pode atualizar agora');
          } else {
            _log('🔕 [SNAPSHOT] Sessão já estava pronta, NÃO chamando notifyListeners() para evitar rebuild do GoRouter');
          }
        } catch (e, stack) {
          _logError('Erro ao processar snapshot do usuário', e, stack);
          // Mesmo com erro, marca sessão como pronta para não travar
          if (!_sessionReady) {
            _sessionReady = true;
            notifyListeners();
          }
        }
      }, onError: (error, stack) {
        final isPermissionDenied =
            error is FirebaseException && error.code == 'permission-denied';
        final isLoggedOut = fire_auth.FirebaseAuth.instance.currentUser == null;

        if (isPermissionDenied && isLoggedOut) {
          return;
        }

        _logError('Erro no stream Users/$uid', error, stack);
      });
    } catch (e, stack) {
      _logError('Erro ao carregar dados do usuário', e, stack);
      // Mesmo com erro, marca sessão como pronta para não travar
      if (!_sessionReady) {
        _sessionReady = true;
        notifyListeners();
      }
    }
  }

  /// Força logout do usuário (delega para SessionManager)
  Future<void> signOut() async {
    try {
      _log('Iniciando logout via AuthSyncService');
      
      // Cancela subscriptions
      await _userSubscription?.cancel();
      _userSubscription = null;
      
      // Limpar tokens FCM
      _log('🔑 Removendo FCM tokens...');
      await FcmTokenService.instance.clearTokens();
      
      // Limpar cache do UserRepository
      UserRepository.clearCache();
      
      // SessionManager.logout() limpa tudo (AppState incluído)
      await SessionManager.instance.logout();
      
      // Firebase signOut por último (dispara authStateChanges que confirma o logout)
      await fire_auth.FirebaseAuth.instance.signOut();
      
      _log('Logout completado');
    } catch (e, stack) {
      _logError('Erro durante logout', e, stack);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }

  void _log(String message) {
    developer.log(message, name: 'partiu.auth_sync');
  }

  void _logError(String message, Object error, StackTrace stackTrace) {
    developer.log(
      message,
      name: 'partiu.auth_sync',
      error: error,
      stackTrace: stackTrace,
    );
  }
}