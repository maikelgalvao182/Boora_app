import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class SocialAuth {
  // Variables
  static final auth = FirebaseAuth.instance;
  
  // Google Sign-In Web Client ID (OAuth 2.0 Client ID do tipo Web)
  // Necessário para Android - obtido do google-services.json
  // Usando o Web Client ID (client_type: 3) como serverClientId
  static const String _googleWebClientId = '988152637100-ml129liekdajoaa85dtpsvj4opt3uudt.apps.googleusercontent.com';

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
          message: 'Token de identidade da Apple não disponível.',
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
          message: 'Login cancelado pelo usuário',
        ));
      } else {
        onError(FirebaseAuthException(
          code: 'unknown',
          message: 'Erro inesperado: $e',
        ));
      }
    }
  }

  //
  // LOGIN WITH FACEBOOK
  //
  static Future<void> signInWithFacebook({
    // Callback functions
    required Function() checkUserAccount,
    required Function(FirebaseAuthException error) onError,
  }) async {
    try {
      // Trigger the sign-in flow
      final loginResult = await FacebookAuth.instance.login();

      // Continues if not null
      if (loginResult.accessToken == null) return;

      // Create a credential from the access token
      final facebookAuthCredential =
          FacebookAuthProvider.credential(loginResult.accessToken!.tokenString);

      // Once signed in, return the Firebase UserCredential
      await auth.signInWithCredential(facebookAuthCredential);

      /// Check User Account in Database to take action
      checkUserAccount();
    } on FirebaseAuthException catch (error) {
      // Error callback
      onError(error);
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
      
      // Initialize Google Sign-In (required in v7.x)
      // No Android, é necessário passar o serverClientId (Web Client ID)
      if (Platform.isAndroid) {
        await GoogleSignIn.instance.initialize(
          serverClientId: _googleWebClientId,
        );
      } else {
        await GoogleSignIn.instance.initialize();
      }
      
      // Disconnect any existing user first
      try {
        await GoogleSignIn.instance.disconnect();
      } catch (e) {
        // Continue even if there's an error here
      }
      
      // Start interactive authentication
      
      // In v7.x, authenticate() returns a GoogleSignInAccount directly
      // It throws an exception if user cancels, so we need to catch it
      GoogleSignInAccount googleUser;
      try {
        googleUser = await GoogleSignIn.instance.authenticate();
      } on Exception catch (e) {
        final errorMsg = e.toString().toLowerCase();
        if (errorMsg.contains('sign_in_canceled') || 
            errorMsg.contains('cancelled') ||
            errorMsg.contains('cancel')) {
          onError(FirebaseAuthException(
            code: 'sign_in_canceled',
            message: 'Login cancelado pelo usuário',
          ));
        } else {
          onError(FirebaseAuthException(
            code: 'authentication-failed',
            message: 'Falha na autenticação: $e',
          ));
        }
        return;
      }
      
      // Obtain the auth details from the request
      final googleAuth = googleUser.authentication;

      // Check if the ID token is available
      if (googleAuth.idToken == null) {
        throw FirebaseAuthException(
          code: 'invalid-credential',
          message: 'Token de ID do Google não disponível',
        );
      }

      if (googleAuth.idToken != null) {
      }
      
      // For Firebase, we primarily need the ID token
      // In v7.x, access token is available via the authorization client if needed
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        // Access token can be obtained separately if needed via authorizationClient
      );

      // Once signed in, return the Firebase UserCredential
      final userCredential = await auth.signInWithCredential(credential);
      
      // Tenta obter nome de múltiplas fontes
      String? finalName;
      
      // 1. Primeiro tenta pegar do GoogleSignInAccount
      if (googleUser.displayName != null && googleUser.displayName!.isNotEmpty) {
        finalName = googleUser.displayName;
      } 
      // 2. Se não tem, tenta pegar do Firebase User
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
            } else {
            }
          } else {
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

      /// Check User Account in Database to take action
      checkUserAccount();
    } on FirebaseAuthException catch (error) {
      // Error callback
      onError(error);
    } catch (e) {
      
      // Check if it's a user cancellation (PlatformException from google_sign_in)
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('sign_in_canceled') || 
          errorString.contains('sign_in_cancelled') ||
          errorString.contains('user_canceled') ||
          errorString.contains('cancel')) {
        onError(FirebaseAuthException(
          code: 'sign_in_canceled',
          message: 'Login cancelado pelo usuário',
        ));
      } else {
        onError(FirebaseAuthException(
          code: 'unknown',
          message: 'Erro inesperado: $e',
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
      await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      /// Check User Account in Database to take action
      checkUserAccount();
    } on FirebaseAuthException catch (error) {
      // Error callback
      onError(error);
    } catch (e) {
      onError(FirebaseAuthException(
        code: 'unknown',
        message: 'Erro inesperado: $e',
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
      await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      /// Check User Account in Database to take action
      checkUserAccount();
    } on FirebaseAuthException catch (error) {
      // Error callback
      onError(error);
    } catch (e) {
      onError(FirebaseAuthException(
        code: 'unknown',
        message: 'Erro inesperado: $e',
      ));
    }
  }
}
