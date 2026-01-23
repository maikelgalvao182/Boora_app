import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:partiu/features/subscription/services/simple_revenue_cat_service.dart';
import 'package:partiu/core/services/analytics_service.dart';

class SocialAuth {
  // Variables
  static final auth = FirebaseAuth.instance;
  
  // Google Sign-In Web Client ID (OAuth 2.0 Client ID do tipo Web)
  // Necessário para Android - obtido do google-services.json (client_type: 3)
  // Este é o Web Client ID do projeto partiu-479902
  static const String _googleWebClientId = '13564294004-nvddc415cn467vtps7rlm2jcr077o2ri.apps.googleusercontent.com';

  //
  // LOGIN WITH APPLE - SECTION
  //
  /// Generates a cryptographically secure random nonce, to be included in a
  /// credential request.
  static String _generateNonce([int length = 32]) {
    // Define 64 characters string
    const charset64 =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    // Creates a cryptographically secure random number generator.
    final random = Random.secure();
    return List.generate(
        length, (_) => charset64[random.nextInt(charset64.length)]).join();
  }

  /// Returns the sha256 hash of [input] in hex notation.
  static String _sha256ofString(String input) {
    final List<int> bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Login with Apple - method
  static Future<void> signInWithApple({
    // Callback functions
    required Function() checkUserAccount,
    required Function(FirebaseAuthException error) onError,
    required Function() onNotAvailable,
    Function(String displayName)? onNameReceived, // [OK] NOVO: Captura nome do Apple
  }) async {
    try {
      if (!await SignInWithApple.isAvailable()) {
        onNotAvailable();
        return; //Break the program
      }
      // To prevent replay attacks with the credential returned from Apple, we
      // include a nonce in the credential request. When signing in in with
      // Firebase, the nonce in the id token returned by Apple, is expected to
      // match the sha256 hash of `rawNonce`.
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      // Request credential for the currently signed in Apple account.
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      // Verifique se o token de identidade está disponível
      if (appleCredential.identityToken == null) {
        throw FirebaseAuthException(
          code: 'invalid-credential',
        );
      }

      // Get Apple User Fullname
      final appleUserName =
          "${appleCredential.givenName ?? ''} ${appleCredential.familyName ?? ''}".trim();

      
      // Create an `OAuthCredential` from the credential returned by Apple.
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        // Adiciona o token de autorização como accessToken, que pode ser necessário para a validação
        accessToken: appleCredential.authorizationCode,
      );

      
      // Sign in the user with Firebase. If the nonce we generated earlier does
      // not match the nonce in `appleCredential.identityToken`, sign in will fail.
      // Once signed in, return the Firebase UserCredential
      final userCredential = await auth.signInWithCredential(oauthCredential);

      // Tenta obter nome de múltiplas fontes
      String? finalName;
      
      // 1. Primeiro tenta pegar do appleCredential (só funciona na primeira vez)
      if (appleUserName.isNotEmpty) {
        finalName = appleUserName;
        // Salva no Firebase displayName para logins futuros
        await userCredential.user!.updateDisplayName(appleUserName);
      } 
      // 2. Se não tem, tenta pegar do Firebase User displayName (logins subsequentes)
      else if (userCredential.user?.displayName != null && 
               userCredential.user!.displayName!.isNotEmpty) {
        finalName = userCredential.user!.displayName;
      }
      // 3. Última tentativa: buscar do Firestore se o usuário já existe
      else {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(userCredential.user!.uid)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data();
            final firestoreName = userData?['fullname'] as String?;
            if (firestoreName != null && firestoreName.isNotEmpty) {
              finalName = firestoreName;
              // Atualiza também o displayName para próximas vezes
              await userCredential.user!.updateDisplayName(finalName);
            }
          }
        } catch (e) {
          // Silently ignore Firestore name fetch errors
        }
      }
      
      // [OK] CRÍTICO: Notifica o nome ANTES de checkUserAccount para garantir que seja salvo
      if (finalName != null && finalName.isNotEmpty) {
        onNameReceived?.call(finalName);
      } else {
      }

      // 🔐 INTEGRAÇÃO REVENUECAT: Vincula user ID Firebase ao RevenueCat
      try {
        await SimpleRevenueCatService.login(userCredential.user!.uid);
      } catch (e) {
        // Ignora erros do RevenueCat para não bloquear o login
      }

      // 📊 ANALYTICS: Loga evento de login/signup com Apple
      final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
      if (isNewUser) {
        AnalyticsService.instance.logSignUp(method: 'apple');
      } else {
        AnalyticsService.instance.logLogin(method: 'apple');
      }
      AnalyticsService.instance.setUserId(userCredential.user!.uid);

      /// Check User Account in Database to take action
      checkUserAccount();
    } on FirebaseAuthException catch (error) {
      // Error callback
      onError(error);
    } catch (e) {
      // Check if it's a user cancellation
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('canceled') || 
          errorString.contains('cancelled') ||
          errorString.contains('user_canceled')) {
        onError(FirebaseAuthException(
          code: 'sign_in_canceled',
        ));
      } else {
        onError(FirebaseAuthException(
          code: 'unknown',
        ));
      }
    }
  }

  //
  // LOGIN WITH GOOGLE
  //
  static Future<void> signInWithGoogle({
    // Callback functions
    required Function() checkUserAccount,
    required Function(FirebaseAuthException error) onError,
    Function(String displayName)? onNameReceived, // [OK] NOVO: Captura nome do Google
  }) async {
    try {
      debugPrint('🔵 [GOOGLE_AUTH] Iniciando processo de autenticação');
      
      // Initialize Google Sign-In (required in v7.x)
      // No Android, é necessário passar o serverClientId (Web Client ID)
      if (Platform.isAndroid) {
        debugPrint('🔵 [GOOGLE_AUTH] Android detectado - usando serverClientId');
        await GoogleSignIn.instance.initialize(
          serverClientId: _googleWebClientId,
        );
      } else {
        debugPrint('🔵 [GOOGLE_AUTH] iOS/Web detectado');
        await GoogleSignIn.instance.initialize();
      }
      
      debugPrint('✅ [GOOGLE_AUTH] GoogleSignIn inicializado');
      
      // Disconnect any existing user first
      try {
        debugPrint('🔵 [GOOGLE_AUTH] Desconectando usuário existente...');
        await GoogleSignIn.instance.disconnect();
      } catch (e) {
        debugPrint('⚠️ [GOOGLE_AUTH] Erro ao desconectar (ignorando): $e');
        // Continue even if there's an error here
      }
      
      // Start interactive authentication
      debugPrint('🔵 [GOOGLE_AUTH] Iniciando autenticação interativa...');
      
      // In v7.x, authenticate() returns a GoogleSignInAccount directly
      // It throws an exception if user cancels, so we need to catch it
      GoogleSignInAccount googleUser;
      try {
        googleUser = await GoogleSignIn.instance.authenticate();
        debugPrint('✅ [GOOGLE_AUTH] Autenticação interativa concluída');
        debugPrint('🔵 [GOOGLE_AUTH] User: ${googleUser.email} | ${googleUser.displayName}');
      } on Exception catch (e) {
        debugPrint('❌ [GOOGLE_AUTH] Erro na autenticação: $e');
        debugPrint('❌ [GOOGLE_AUTH] Tipo: ${e.runtimeType}');
        final errorMsg = e.toString().toLowerCase();
        if (errorMsg.contains('sign_in_canceled') || 
            errorMsg.contains('cancelled') ||
            errorMsg.contains('cancel')) {
          debugPrint('❌ [GOOGLE_AUTH] Cancelado pelo usuário');
          onError(FirebaseAuthException(
            code: 'sign_in_canceled',
          ));
        } else {
          debugPrint('❌ [GOOGLE_AUTH] Falha de autenticação');
          onError(FirebaseAuthException(
            code: 'authentication-failed',
          ));
        }
        return;
      }
      
      // Obtain the auth details from the request
      debugPrint('🔵 [GOOGLE_AUTH] Obtendo tokens...');
      final googleAuth = googleUser.authentication;

      // Check if the ID token is available
      if (googleAuth.idToken == null) {
        debugPrint('❌ [GOOGLE_AUTH] ID Token ausente');
        throw FirebaseAuthException(
          code: 'invalid-credential',
        );
      }

      debugPrint('✅ [GOOGLE_AUTH] ID Token obtido');
      
      // For Firebase, we primarily need the ID token
      // In v7.x, access token is available via the authorization client if needed
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        // Access token can be obtained separately if needed via authorizationClient
      );

      debugPrint('🔵 [GOOGLE_AUTH] Autenticando com Firebase...');
      // Once signed in, return the Firebase UserCredential
      final userCredential = await auth.signInWithCredential(credential);
      debugPrint('✅ [GOOGLE_AUTH] Autenticado com Firebase: ${userCredential.user?.uid}');
      
      // Tenta obter nome de múltiplas fontes
      String? finalName;
      
      // 1. Primeiro tenta pegar do GoogleSignInAccount
      if (googleUser.displayName != null && googleUser.displayName!.isNotEmpty) {
        finalName = googleUser.displayName;
        debugPrint('🔵 [GOOGLE_AUTH] Nome obtido do GoogleSignInAccount: $finalName');
      } 
      // 2. Se não tem, tenta pegar do Firebase User
      else if (userCredential.user?.displayName != null && 
               userCredential.user!.displayName!.isNotEmpty) {
        finalName = userCredential.user!.displayName;
        debugPrint('🔵 [GOOGLE_AUTH] Nome obtido do Firebase User: $finalName');
      }
      // 3. Última tentativa: buscar do Firestore se o usuário já existe
      else {
        debugPrint('🔵 [GOOGLE_AUTH] Buscando nome no Firestore...');
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(userCredential.user!.uid)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data();
            final firestoreName = userData?['fullname'] as String?;
            if (firestoreName != null && firestoreName.isNotEmpty) {
              finalName = firestoreName;
              debugPrint('🔵 [GOOGLE_AUTH] Nome obtido do Firestore: $finalName');
              // Atualiza também o displayName para próximas vezes
              await userCredential.user!.updateDisplayName(finalName);
            } else {
              debugPrint('⚠️ [GOOGLE_AUTH] Nome não encontrado no Firestore');
            }
          } else {
            debugPrint('⚠️ [GOOGLE_AUTH] Documento de usuário não existe no Firestore');
          }
        } catch (e) {
          debugPrint('❌ [GOOGLE_AUTH] Erro ao buscar nome no Firestore: $e');
        }
      }
      
      // [OK] CRÍTICO: Notifica o nome ANTES de checkUserAccount para garantir que seja salvo
      if (finalName != null && finalName.isNotEmpty) {
        debugPrint('✅ [GOOGLE_AUTH] Notificando nome: $finalName');
        onNameReceived?.call(finalName);
      } else {
        debugPrint('⚠️ [GOOGLE_AUTH] Nenhum nome disponível para notificar');
      }

      // 🔐 INTEGRAÇÃO REVENUECAT: Vincula user ID Firebase ao RevenueCat
      try {
        debugPrint('🔵 [GOOGLE_AUTH] Integrando com RevenueCat...');
        await SimpleRevenueCatService.login(userCredential.user!.uid);
        debugPrint('✅ [GOOGLE_AUTH] RevenueCat integrado');
      } catch (e) {
        debugPrint('⚠️ [GOOGLE_AUTH] Erro no RevenueCat (ignorando): $e');
      }

      // 📊 ANALYTICS: Loga evento de login/signup com Google
      final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
      if (isNewUser) {
        AnalyticsService.instance.logSignUp(method: 'google');
      } else {
        AnalyticsService.instance.logLogin(method: 'google');
      }
      AnalyticsService.instance.setUserId(userCredential.user!.uid);

      debugPrint('🔵 [GOOGLE_AUTH] Verificando conta do usuário...');
      /// Check User Account in Database to take action
      checkUserAccount();
      debugPrint('✅ [GOOGLE_AUTH] Processo concluído');
    } on FirebaseAuthException catch (error) {
      debugPrint('❌ [GOOGLE_AUTH] FirebaseAuthException: ${error.code} - ${error.message}');
      // Error callback
      onError(error);
    } catch (e, stackTrace) {
      debugPrint('❌ [GOOGLE_AUTH] Exceção inesperada: $e');
      debugPrint('❌ [GOOGLE_AUTH] StackTrace: $stackTrace');
      
      // Check if it's a user cancellation (PlatformException from google_sign_in)
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('sign_in_canceled') || 
          errorString.contains('sign_in_cancelled') ||
          errorString.contains('user_canceled') ||
          errorString.contains('cancel')) {
        debugPrint('❌ [GOOGLE_AUTH] Identificado como cancelamento');
        onError(FirebaseAuthException(
          code: 'sign_in_canceled',
        ));
      } else {
        debugPrint('❌ [GOOGLE_AUTH] Erro desconhecido');
        onError(FirebaseAuthException(
          code: 'unknown',
        ));
      }
    }
  }

  //
  // LOGIN WITH EMAIL/PASSWORD - SECTION
  //
  
  /// Login with Email and Password
  static Future<void> signInWithEmail({
    required String email,
    required String password,
    required Function() checkUserAccount,
    required Function(FirebaseAuthException error) onError,
  }) async {
    try {
      // Sign in with email and password
      final userCredential = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // 🔒 Requer verificação de e-mail antes de prosseguir
      // (válido apenas para fluxo Email/Senha; provedores OAuth já validam)
      final user = userCredential.user;
      if (user != null && user.emailVerified == false) {
        try {
          await user.sendEmailVerification();
        } catch (_) {
          // Não bloquear por falha ao reenviar e-mail
        }

        onError(FirebaseAuthException(code: 'email_not_verified'));
        return;
      }

      // 🔐 INTEGRAÇÃO REVENUECAT: Vincula user ID Firebase ao RevenueCat (Email)
      try {
        await SimpleRevenueCatService.login(userCredential.user!.uid);
      } catch (e) {
        // Ignora erros do RevenueCat para não bloquear o login
      }

      // 📊 ANALYTICS: Loga evento de login com Email
      AnalyticsService.instance.logLogin(method: 'email');
      AnalyticsService.instance.setUserId(userCredential.user!.uid);

      /// Check User Account in Database to take action
      checkUserAccount();
    } on FirebaseAuthException catch (error) {
      // Error callback
      onError(error);
    } catch (e) {
      onError(FirebaseAuthException(
        code: 'unknown',
      ));
    }
  }

  /// Create User with Email and Password
  static Future<void> createUserWithEmail({
    required String email,
    required String password,
    required Function() checkUserAccount,
    required Function(FirebaseAuthException error) onError,
  }) async {
    try {
      // Create user with email and password
      final userCredential = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // 📊 ANALYTICS: Loga evento de signup com Email
      AnalyticsService.instance.logSignUp(method: 'email');
      AnalyticsService.instance.setUserId(userCredential.user!.uid);

      // ✅ Envia verificação e impede prosseguir até o e-mail estar verificado
      final user = userCredential.user;
      if (user != null) {
        try {
          await user.sendEmailVerification();
        } catch (_) {
          // Não bloquear por falha ao enviar e-mail de verificação
        }
      }

      // Desloga para forçar login somente após verificação
      // Sinaliza para UI mostrar mensagem amigável (não é erro técnico)
      onError(FirebaseAuthException(code: 'email_verification_sent'));
      return;
    } on FirebaseAuthException catch (error) {
      // Error callback
      onError(error);
    } catch (e) {
      onError(FirebaseAuthException(
        code: 'unknown',
      ));
    }
  }
}
