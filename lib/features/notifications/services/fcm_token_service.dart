import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as fire_auth;

/// 🔑 Serviço de gerenciamento de FCM tokens
/// 
/// Responsável por:
/// - Obter FCM token do dispositivo
/// - Salvar token na coleção `DeviceTokens`
/// - Atualizar token quando mudar
/// - Limpar tokens no logout
/// 
/// Estrutura no Firestore:
/// ```
/// DeviceTokens/
///   └── {tokenId}/
///       ├── userId: string
///       ├── token: string
///       ├── deviceId: string
///       ├── deviceName: string
///       ├── platform: "android" | "ios"
///       ├── createdAt: timestamp
///       ├── updatedAt: timestamp
///       └── lastUsedAt: timestamp
/// ```
class FcmTokenService {
  FcmTokenService._();
  
  static final FcmTokenService instance = FcmTokenService._();
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  String? _currentToken;
  String? _currentDeviceId;
  
  /// 🔒 Flag para garantir que initialize() só rode uma vez por sessão
  bool _initialized = false;
  
  /// 🔔 Subscription do listener de token refresh (para cancelar no logout)
  StreamSubscription<String>? _tokenRefreshSub;
  
  /// 🔒 Mutex para evitar chamadas concorrentes de _saveToken()
  bool _saving = false;
  
  /// 🚀 Inicializa o serviço de FCM tokens
  /// 
  /// Deve ser chamado após o login do usuário.
  /// ⚠️ IDÊMPOTENTE: só executa uma vez por sessão.
  Future<void> initialize() async {
    // 🔒 Guard: evita múltiplas inicializações (causa de push duplicado)
    if (_initialized) {
      print('⚠️ [FCM Token] initialize() já executado nesta sessão, ignorando');
      return;
    }
    
    // ⚠️ IMPORTANTE: Verificar user ANTES de setar _initialized
    // Evita "queimar" a sessão se chamado antes do login
    final user = fire_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('⚠️ [FCM Token] Usuário não autenticado, aguardando login');
      return;
    }
    
    // ✅ Só marca como inicializado APÓS confirmar que há user
    _initialized = true;
    
    try {
      print('╔═══════════════════════════════════════════════════════');
      print('║ 🔑 [FCM Token Service] INICIALIZANDO');
      print('╚═══════════════════════════════════════════════════════');
      
      print('👤 [FCM Token] User ID: ${user.uid}');
      print('📧 [FCM Token] Email: ${user.email ?? "N/A"}');
      
      // 1. Obter token FCM
      print('\n🔍 [FCM Token] Passo 1: Obtendo FCM token...');
      final token = await _getToken();
      if (token == null) {
        print('❌ [FCM Token] Não foi possível obter token FCM');
        
        // iOS: Agenda retry para depois que o APNS token estiver disponível
        if (Platform.isIOS) {
          print('⏰ [FCM Token] Agendando retry em 5 segundos...');
          final userIdAtSchedule = user.uid; // Captura o userId no momento do agendamento
          Future.delayed(const Duration(seconds: 5), () async {
            // 🔒 Guard: aborta se sessão foi invalidada (logout/troca de conta)
            if (!_initialized) {
              print('⚠️ [FCM Token] Retry abortado — sessão inválida (logout ocorreu)');
              return;
            }
            
            // Verifica se o usuário atual ainda é o mesmo
            final currentUser = fire_auth.FirebaseAuth.instance.currentUser;
            if (currentUser == null || currentUser.uid != userIdAtSchedule) {
              print('⚠️ [FCM Token] Retry abortado — usuário mudou');
              return;
            }
            
            print('\n🔄 [FCM Token] Tentando novamente após delay...');
            final retryToken = await _getToken();
            if (retryToken != null) {
              final retryDeviceId = await _getDeviceId();
              await _saveToken(
                userId: currentUser.uid,
                token: retryToken,
                deviceId: retryDeviceId,
              );
              print('✅ [FCM Token] Token salvo com sucesso no retry');
            }
          });
        }
        
        return;
      }
      
      // 2. Obter device ID
      print('\n🔍 [FCM Token] Passo 2: Obtendo Device ID...');
      final deviceId = await _getDeviceId();
      
      // 3. Salvar token no Firestore
      print('\n🔍 [FCM Token] Passo 3: Salvando no Firestore...');
      await _saveToken(
        userId: user.uid,
        token: token,
        deviceId: deviceId,
      );
      
      // 4. Setup listener para token refresh
      print('\n🔍 [FCM Token] Passo 4: Configurando listener de refresh...');
      _setupTokenRefreshListener();
      
      print('\n╔═══════════════════════════════════════════════════════');
      print('║ ✅ [FCM Token Service] INICIALIZADO COM SUCESSO');
      print('╠═══════════════════════════════════════════════════════');
      print('║ 👤 User: ${user.uid}');
      print('║ 📱 Device: $deviceId');
      print('║ 🔑 Token: ${token.substring(0, 20)}...');
      print('╚═══════════════════════════════════════════════════════');
      
    } catch (e, stack) {
      print('❌ [FCM Token] Erro ao inicializar: $e');
      print('Stack: $stack');
    }
  }
  
  /// 🔄 Atualiza o token FCM (manual)
  Future<void> refreshToken() async {
    try {
      final user = fire_auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ [FCM Token] Usuário não autenticado');
        return;
      }
      
      // Força obtenção de novo token
      await _messaging.deleteToken();
      final newToken = await _getToken();
      
      if (newToken == null) {
        print('❌ [FCM Token] Não foi possível obter novo token');
        return;
      }
      
      final deviceId = await _getDeviceId();
      await _saveToken(
        userId: user.uid,
        token: newToken,
        deviceId: deviceId,
      );
      
      print('✅ [FCM Token] Token atualizado manualmente');
      
    } catch (e) {
      print('❌ [FCM Token] Erro ao atualizar token: $e');
    }
  }
  
  /// 🗑️ Remove todos os tokens do usuário atual (logout)
  Future<void> clearTokens() async {
    try {
      final user = fire_auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ [FCM Token] clearTokens: Usuário não autenticado');
        return;
      }
      
      print('\n╔═══════════════════════════════════════════════════════');
      print('║ 🗑️ [FCM Token] REMOVENDO TOKENS (LOGOUT)');
      print('╚═══════════════════════════════════════════════════════');
      print('👤 [FCM Token] User ID: ${user.uid}');
      
      // Busca todos os tokens do usuário
      print('🔍 [FCM Token] Buscando tokens do usuário...');
      final snapshot = await _firestore
          .collection('DeviceTokens')
          .where('userId', isEqualTo: user.uid)
          .get();
      
      print('📊 [FCM Token] ${snapshot.docs.length} token(s) encontrado(s)');
      
      if (snapshot.docs.isEmpty) {
        print('✓ [FCM Token] Nenhum token para remover');
        return;
      }
      
      // Remove em batch
      print('🗑️ [FCM Token] Removendo tokens em batch...');
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        print('  - Removendo: ${doc.id}');
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      
      // Cancela listener de token refresh (CRÍTICO: evita push duplicado)
      print('🔔 [FCM Token] Cancelando listener de token refresh...');
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
      print('✅ [FCM Token] Listener cancelado');
      
      // Limpa cache local e reset de estado
      _currentToken = null;
      _currentDeviceId = null;
      _initialized = false; // Permite re-inicialização após novo login
      _saving = false; // Reset do mutex
      
      print('✅ [FCM Token] ${snapshot.docs.length} token(s) removido(s) com sucesso');
      print('💾 [FCM Token] Cache local e estado resetados');
      
    } catch (e) {
      print('❌ [FCM Token] Erro ao remover tokens: $e');
    }
  }
  
  /// 🔑 Obtém o FCM token do dispositivo
  Future<String?> _getToken() async {
    try {
      print('  ⏳ [FCM Token] Solicitando token ao Firebase Messaging...');
      
      // iOS: Solicitar permissões primeiro
      if (Platform.isIOS) {
        print('  🍎 [FCM Token] iOS detectado - solicitando permissões APNS...');
        final settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        
        print('  📋 [FCM Token] Status de autorização: ${settings.authorizationStatus}');
        
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          print('  ⚠️ [FCM Token] Permissões negadas pelo usuário');
          return null;
        }
        
        // Aguarda um pouco para o APNS token ser registrado
        print('  ⏳ [FCM Token] Aguardando registro do APNS token...');
        await Future.delayed(const Duration(seconds: 2));
      }
      
      final token = await _messaging.getToken();
      
      if (token != null) {
        _currentToken = token;
        print('  ✅ [FCM Token] Token obtido com sucesso');
        print('  📝 [FCM Token] Token (primeiros 40 chars): ${token.substring(0, token.length > 40 ? 40 : token.length)}...');
        print('  📏 [FCM Token] Tamanho total: ${token.length} caracteres');
      } else {
        print('  ⚠️ [FCM Token] Token retornado é null');
        
        // iOS: Tenta obter o APNS token diretamente para debug
        if (Platform.isIOS) {
          try {
            final apnsToken = await _messaging.getAPNSToken();
            if (apnsToken != null) {
              print('  🔍 [FCM Token] APNS token está disponível: ${apnsToken.substring(0, 20)}...');
              print('  ⏳ [FCM Token] Tentando obter FCM token novamente...');
              // Tenta novamente após pequeno delay
              await Future.delayed(const Duration(seconds: 1));
              final retryToken = await _messaging.getToken();
              if (retryToken != null) {
                _currentToken = retryToken;
                print('  ✅ [FCM Token] Token obtido na segunda tentativa');
                return retryToken;
              }
            } else {
              print('  ⚠️ [FCM Token] APNS token ainda não disponível');
              print('  💡 [FCM Token] Dica: Certifique-se que o app tem permissões de notificação');
            }
          } catch (apnsError) {
            print('  ⚠️ [FCM Token] Erro ao verificar APNS token: $apnsError');
          }
        }
      }
      
      return token;
      
    } catch (e) {
      print('❌ [FCM Token] Erro ao obter token: $e');
      
      // Informações adicionais para debug
      if (e.toString().contains('apns-token-not-set')) {
        print('💡 [FCM Token] SOLUÇÃO:');
        print('   1. Verifique se o app tem permissões de notificação no iOS');
        print('   2. Certifique-se que o certificado APNs está configurado no Firebase');
        print('   3. Aguarde alguns segundos após o app iniciar');
        print('   4. Em desenvolvimento, pode ser necessário reinstalar o app');
      }
      
      return null;
    }
  }
  
  /// 📱 Obtém o device ID único
  Future<String> _getDeviceId() async {
    if (_currentDeviceId != null) {
      print('  💾 [FCM Token] Device ID em cache: $_currentDeviceId');
      return _currentDeviceId!;
    }
    
    try {
      print('  ⏳ [FCM Token] Obtendo informações do dispositivo...');
      String deviceId;
      
      if (Platform.isAndroid) {
        print('  🤖 [FCM Token] Plataforma: Android');
        final androidInfo = await _deviceInfo.androidInfo;
        deviceId = androidInfo.id; // Android ID único
        print('  📱 [FCM Token] Device Info:');
        print('     - Brand: ${androidInfo.brand}');
        print('     - Model: ${androidInfo.model}');
        print('     - Android Version: ${androidInfo.version.release}');
        print('     - SDK: ${androidInfo.version.sdkInt}');
      } else if (Platform.isIOS) {
        print('  🍎 [FCM Token] Plataforma: iOS');
        final iosInfo = await _deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown_ios_device';
        print('  📱 [FCM Token] Device Info:');
        print('     - Name: ${iosInfo.name}');
        print('     - Model: ${iosInfo.model}');
        print('     - iOS Version: ${iosInfo.systemVersion}');
      } else {
        print('  ❓ [FCM Token] Plataforma desconhecida');
        deviceId = 'unknown_device';
      }
      
      _currentDeviceId = deviceId;
      print('  ✅ [FCM Token] Device ID obtido: $deviceId');
      
      return deviceId;
      
    } catch (e) {
      print('❌ [FCM Token] Erro ao obter device ID: $e');
      return 'unknown_device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
  
  /// 💾 Salva o token no Firestore
  /// 🔒 Mutex interno evita chamadas concorrentes
  Future<void> _saveToken({
    required String userId,
    required String token,
    required String deviceId,
  }) async {
    // 🔒 Mutex: evita chamadas concorrentes (initialize + retry + onTokenRefresh)
    if (_saving) {
      print('⚠️ [FCM Token] _saveToken já em execução, ignorando chamada concorrente');
      return;
    }
    _saving = true;
    
    try {
      print('  ⏳ [FCM Token] Preparando para salvar no Firestore...');
      print('  📋 [FCM Token] Dados:');
      print('     - User ID: $userId');
      print('     - Device ID: $deviceId');
      
      // Verifica se o usuário ainda está autenticado
      final currentUser = fire_auth.FirebaseAuth.instance.currentUser;
      if (currentUser == null || currentUser.uid != userId) {
        print('  ❌ [FCM Token] Usuário não autenticado ou UID não corresponde');
        print('     - Current User: ${currentUser?.uid ?? "null"}');
        print('     - Expected User: $userId');
        return;
      }
      
      // Aguarda o token de ID estar disponível (prova de autenticação válida)
      print('  🔐 [FCM Token] Verificando token de autenticação...');
      try {
        final idToken = await currentUser.getIdToken();
        if (idToken == null) {
          print('  ❌ [FCM Token] Token de autenticação é null');
          print('  ⏰ [FCM Token] Agendando retry em 3 segundos...');
          await Future.delayed(const Duration(seconds: 3));
          return _saveToken(userId: userId, token: token, deviceId: deviceId);
        }
        print('  ✅ [FCM Token] Token de autenticação válido');
      } catch (e) {
        print('  ⚠️ [FCM Token] Erro ao verificar token: $e');
        print('  ⏰ [FCM Token] Agendando retry em 3 segundos...');
        await Future.delayed(const Duration(seconds: 3));
        return _saveToken(userId: userId, token: token, deviceId: deviceId);
      }
      
      final deviceName = await _getDeviceName();
      final platform = Platform.isAndroid ? 'android' : 'ios';
      
      print('     - Device Name: $deviceName');
      print('     - Platform: $platform');
      
      // Usa deviceId como document ID para evitar duplicatas
      final docId = '${userId}_$deviceId';
      final docRef = _firestore
          .collection('DeviceTokens')
          .doc(docId);
      
      print('  📄 [FCM Token] Document ID: $docId');
      print('  🔍 [FCM Token] Verificando se documento já existe...');
      print('  📍 [FCM Token] Collection path: DeviceTokens');
      print('  📄 [FCM Token] Full path: DeviceTokens/$docId');
      
      final now = FieldValue.serverTimestamp();
      
      // Verifica se já existe
      try {
        print('  ⏳ [FCM Token] Executando docRef.get()...');
        final existingDoc = await docRef.get();
        print('  ✅ [FCM Token] docRef.get() executado - exists: ${existingDoc.exists}');
      
      if (existingDoc.exists) {
        print('  📋 [FCM Token] Documento existente encontrado');
        
        // Atualiza apenas se o token mudou
        final existingToken = existingDoc.data()?['token'] as String?;
        if (existingToken == token) {
          print('  ✓ [FCM Token] Token não mudou, apenas atualizando lastUsedAt...');
          await docRef.update({
            'lastUsedAt': now,
          });
          print('  ✅ [FCM Token] lastUsedAt atualizado com sucesso');
          return;
        }
        
        // Token mudou, atualiza tudo
        print('  🔄 [FCM Token] Token mudou, atualizando todos os campos...');
        await docRef.update({
          'token': token,
          'deviceName': deviceName,
          'platform': platform,
          'updatedAt': now,
          'lastUsedAt': now,
        });
        
        print('  ✅ [FCM Token] Token atualizado no Firestore com sucesso');
        
      } else {
        print('  ➕ [FCM Token] Documento não existe, criando novo...');
        await docRef.set({
          'userId': userId,
          'token': token,
          'deviceId': deviceId,
          'deviceName': deviceName,
          'platform': platform,
          'createdAt': now,
          'updatedAt': now,
          'lastUsedAt': now,
        });
        
        print('  ✅ [FCM Token] Novo documento criado no Firestore com sucesso');
      }
      
      } catch (e) {
        print('  ❌ [FCM Token] Erro específico na operação: $e');
        print('  🔍 [FCM Token] Tipo do erro: ${e.runtimeType}');
        if (e.toString().contains('permission-denied')) {
          print('  💡 [FCM Token] DIAGNÓSTICO DE PERMISSÃO:');
          print('     - Collection: DeviceTokens');
          print('     - Document ID: $docId');
          print('     - User ID: $userId');
          print('     - Auth UID: ${fire_auth.FirebaseAuth.instance.currentUser?.uid}');
          print('     - Match? ${userId == fire_auth.FirebaseAuth.instance.currentUser?.uid}');
        }
        rethrow;
      }
      
    } catch (e) {
      print('❌ [FCM Token] Erro ao salvar token: $e');
    } finally {
      _saving = false;
    }
  }
  
  /// 📱 Obtém o nome do dispositivo
  Future<String> _getDeviceName() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return '${iosInfo.name} (${iosInfo.model})';
      }
      return 'Unknown Device';
    } catch (e) {
      return 'Unknown Device';
    }
  }
  
  /// 🔄 Configura listener para token refresh automático
  /// ⚠️ IDÊMPOTENTE: só registra o listener uma vez
  void _setupTokenRefreshListener() {
    // 🔒 Guard: evita múltiplos listeners (CAUSA RAIZ de push duplicado)
    if (_tokenRefreshSub != null) {
      print('⚠️ [FCM Token] Listener de refresh já registrado, ignorando');
      return;
    }
    
    print('🧨 [FCM Token] Registrando token refresh listener (deve aparecer 1x por sessão)');
    
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
      print('🔄 [FCM Token] Token atualizado automaticamente');
      
      final user = fire_auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ [FCM Token] Usuário não autenticado, ignorando refresh');
        return;
      }
      
      final deviceId = await _getDeviceId();
      await _saveToken(
        userId: user.uid,
        token: newToken,
        deviceId: deviceId,
      );
    });
  }
  
  /// 📊 Obtém estatísticas de tokens do usuário
  Future<List<Map<String, dynamic>>> getTokensInfo() async {
    try {
      final user = fire_auth.FirebaseAuth.instance.currentUser;
      if (user == null) return [];
      
      final snapshot = await _firestore
          .collection('DeviceTokens')
          .where('userId', isEqualTo: user.uid)
          .orderBy('lastUsedAt', descending: true)
          .get();
      
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'deviceId': data['deviceId'] ?? '',
          'deviceName': data['deviceName'] ?? 'Unknown',
          'platform': data['platform'] ?? 'unknown',
          'createdAt': data['createdAt'],
          'lastUsedAt': data['lastUsedAt'],
        };
      }).toList();
      
    } catch (e) {
      print('❌ [FCM Token] Erro ao obter info de tokens: $e');
      return [];
    }
  }
}
