import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/shared/repositories/auth_repository_interface.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/shared/services/auth/social_auth.dart';
import 'package:partiu/core/models/user.dart' as app_user;
import 'package:partiu/core/managers/session_manager.dart';
import 'package:partiu/core/services/image_compress_service.dart';

class AuthRepository implements IAuthRepository {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final ImageCompressService _compressor;

  AuthRepository({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    ImageCompressService? compressor,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _compressor = compressor ?? const ImageCompressService();

  // Stream para acompanhar mudanças do usuário atual
  Stream<app_user.User?> get userStream {
    return _firebaseAuth.authStateChanges().asyncMap((user) async {
      if (user == null) return null;
      
      final doc = await _firestore.collection('Users').doc(user.uid).get();
      if (!doc.exists || doc.data() == null) return null;
      
      return app_user.User.fromDocument(doc.data()!);
    });
  }

  // Usuário atual (em memória via SessionManager)
  app_user.User? get currentUser {
    return SessionManager.instance.currentUser;
  }

  /// Busca dados atualizados do usuário diretamente do Firestore
  /// Use quando precisar garantir dados frescos (ex: tela de edição de perfil)
  Future<app_user.User?> fetchCurrentUserFromFirestore() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) {
        AppLogger.warning('No authenticated user', tag: 'AUTH_REPOSITORY');
        return null;
      }

      final doc = await _firestore.collection('Users').doc(user.uid).get();
      if (!doc.exists || doc.data() == null) {
        AppLogger.warning('User document not found', tag: 'AUTH_REPOSITORY');
        return null;
      }

      final userData = app_user.User.fromDocument(doc.data()!);
      
      // ✅ CRÍTICO: Atualiza SessionManager E AppState com dados frescos
      // Isso dispara notifyListeners() no AppState.currentUser ValueNotifier
      // Permitindo que widgets reativos (ProfileTab, ProfileCompletenessRing) atualizem
      SessionManager.instance.currentUser = userData;
      
      return userData;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error fetching user from Firestore: $e',
        tag: 'AUTH_REPOSITORY',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
  Future<void> authUserAccount({
    required VoidCallback updateLocationScreen,
    required VoidCallback signUpScreen,
    required VoidCallback homeScreen,
    required VoidCallback blockedScreen,
  }) async {
    bool isUnmountedContextError(Object error) {
      final message = error.toString();
      return message.contains('unmounted') && message.contains('context');
    }

    void safeInvoke(VoidCallback callback, String name) {
      try {
        callback();
      } catch (e, stackTrace) {
        if (isUnmountedContextError(e)) {
          AppLogger.warning(
            'Navigation callback ignorado (widget desmontado): $name',
            tag: 'AUTH_REPOSITORY',
          );
          return;
        }

        AppLogger.error(
          'Navigation callback falhou: $name',
          tag: 'AUTH_REPOSITORY',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    try {
      // Aguarda um momento para garantir que o Firebase Auth atualizou o estado
      // Isso é necessário porque o callback checkUserAccount pode ser chamado
      // antes do FirebaseAuth.instance.currentUser ser atualizado
      User? user = _firebaseAuth.currentUser;
      
      // Se currentUser ainda é null, aguarda um pouco e tenta novamente
      if (user == null) {
        AppLogger.info('Waiting for Firebase Auth state to update...', tag: 'AUTH_REPOSITORY');
        await Future.delayed(const Duration(milliseconds: 500));
        user = _firebaseAuth.currentUser;
      }
      
      // Ainda null? Tenta aguardar o authStateChanges
      if (user == null) {
        AppLogger.info('Waiting for authStateChanges...', tag: 'AUTH_REPOSITORY');
        user = await _firebaseAuth.authStateChanges().first.timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        );
      }
      
      if (user == null) {
        AppLogger.warning('No authenticated user found', tag: 'AUTH_REPOSITORY');
        safeInvoke(signUpScreen, 'signUpScreen');
        return;
      }

      AppLogger.info('Checking user profile for: ${user.uid}', tag: 'AUTH_REPOSITORY');

      // Tenta buscar o documento com retry para lidar com erros temporários
      DocumentSnapshot? userDoc;
      int retryCount = 0;
      const maxRetries = 3;
      const retryDelay = Duration(seconds: 2);

      while (retryCount < maxRetries) {
        try {
          userDoc = await _firestore.collection('Users').doc(user.uid).get();
          break; // Sucesso, sai do loop
        } catch (e) {
          retryCount++;
          if (retryCount >= maxRetries) {
            rethrow; // Último retry falhou, propaga o erro
          }
          AppLogger.warning(
            'Firestore error (attempt $retryCount/$maxRetries): $e. Retrying...',
            tag: 'AUTH_REPOSITORY',
          );
          await Future.delayed(retryDelay);
        }
      }

      if (userDoc == null || !userDoc.exists) {
        AppLogger.info('User document not found - redirecting to signup wizard', tag: 'AUTH_REPOSITORY');
        safeInvoke(signUpScreen, 'signUpScreen');
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      
      // Verifica se o perfil está completo (tem nome e tipo de usuário)
      // Verifica tanto o campo moderno quanto o legado para compatibilidade
      final hasFullName = (userData['fullName'] != null && (userData['fullName'] as String).isNotEmpty) ||
                          (userData['fullname'] != null && (userData['fullname'] as String).isNotEmpty);
      
      if (!hasFullName) {
        AppLogger.info('User profile incomplete - redirecting to signup wizard', tag: 'AUTH_REPOSITORY');
        safeInvoke(signUpScreen, 'signUpScreen');
        return;
      }

      // Verifica se está bloqueado
      final isBlocked = (userData['status'] ?? userData['user_status']) == 'blocked';
      if (isBlocked) {
        AppLogger.warning('User is blocked', tag: 'AUTH_REPOSITORY');
        safeInvoke(blockedScreen, 'blockedScreen');
        return;
      }

      // Perfil completo - vai para home
      // NOTA: Removida verificação de localização - usuário pode adicionar depois
      AppLogger.success('User profile complete - redirecting to home', tag: 'AUTH_REPOSITORY');
      safeInvoke(homeScreen, 'homeScreen');
    } catch (e, stackTrace) {
      if (isUnmountedContextError(e)) {
        AppLogger.warning(
          'Auth flow abortado: widget desmontado durante verificação',
          tag: 'AUTH_REPOSITORY',
        );
        return;
      }

      AppLogger.error(
        'Error checking user account',
        tag: 'AUTH_REPOSITORY',
        error: e,
        stackTrace: stackTrace,
      );
      // Em caso de erro, assume que é um novo usuário e vai para signup
      safeInvoke(signUpScreen, 'signUpScreen (fallback)');
    }
  }

  @override
  Future<void> signInWithGoogle({
    required VoidCallback checkUserAccount,
    required Function(dynamic) onError,
    Function(String)? onNameReceived,
  }) async {
    try {
      AppLogger.info('Starting Google Sign In', tag: 'AUTH_REPOSITORY');
      
      await SocialAuth.signInWithGoogle(
        checkUserAccount: () {
          AppLogger.success('Google Sign In successful', tag: 'AUTH_REPOSITORY');
          checkUserAccount();
        },
        onError: (FirebaseAuthException error) {
          AppLogger.error('Google Sign In error: ${error.code}', tag: 'AUTH_REPOSITORY');
          onError(error);
        },
        onNameReceived: onNameReceived,
      );
    } catch (e) {
      AppLogger.error('Google Sign In unexpected error: $e', tag: 'AUTH_REPOSITORY');
      onError({'code': 'unknown', 'message': e.toString()});
    }
  }

  @override
  Future<void> signInWithApple({
    required VoidCallback checkUserAccount,
    required VoidCallback onNotAvailable,
    required Function(dynamic) onError,
    Function(String)? onNameReceived,
  }) async {
    try {
      AppLogger.info('Starting Apple Sign In', tag: 'AUTH_REPOSITORY');
      
      await SocialAuth.signInWithApple(
        checkUserAccount: () {
          AppLogger.success('Apple Sign In successful', tag: 'AUTH_REPOSITORY');
          checkUserAccount();
        },
        onNotAvailable: () {
          AppLogger.warning('Apple Sign In not available', tag: 'AUTH_REPOSITORY');
          onNotAvailable();
        },
        onError: (FirebaseAuthException error) {
          AppLogger.error('Apple Sign In error: ${error.code} - ${error.message}', tag: 'AUTH_REPOSITORY');
          onError(error);
        },
        onNameReceived: onNameReceived,
      );
    } catch (e) {
      AppLogger.error('Apple Sign In unexpected error: $e', tag: 'AUTH_REPOSITORY');
      onError({'code': 'unknown', 'message': e.toString()});
    }
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
    required VoidCallback checkUserAccount,
    required Function(dynamic) onError,
  }) async {
    try {
      AppLogger.info('Starting Email Sign In for: $email', tag: 'AUTH_REPOSITORY');
      
      await SocialAuth.signInWithEmail(
        email: email,
        password: password,
        checkUserAccount: () {
          AppLogger.success('Email Sign In successful', tag: 'AUTH_REPOSITORY');
          checkUserAccount();
        },
        onError: (FirebaseAuthException error) {
          AppLogger.error('Email Sign In error: ${error.code}', tag: 'AUTH_REPOSITORY');
          onError(error);
        },
      );
    } catch (e) {
      AppLogger.error('Email Sign In unexpected error: $e', tag: 'AUTH_REPOSITORY');
      onError({'code': 'unknown', 'message': e.toString()});
    }
  }

  @override
  Future<void> createUserWithEmail({
    required String email,
    required String password,
    required VoidCallback checkUserAccount,
    required Function(dynamic) onError,
  }) async {
    try {
      AppLogger.info('Creating user with email: $email', tag: 'AUTH_REPOSITORY');
      
      await SocialAuth.createUserWithEmail(
        email: email,
        password: password,
        checkUserAccount: () {
          AppLogger.success('User created successfully', tag: 'AUTH_REPOSITORY');
          checkUserAccount();
        },
        onError: (FirebaseAuthException error) {
          AppLogger.error('Create user error: ${error.code}', tag: 'AUTH_REPOSITORY');
          onError(error);
        },
      );
    } catch (e) {
      AppLogger.error('Create user unexpected error: $e', tag: 'AUTH_REPOSITORY');
      onError({'code': 'unknown', 'message': e.toString()});
    }
  }

  // ==================== PROFILE METHODS ====================

  /// Atualiza dados do perfil do usuário
  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      AppLogger.info('Updating user profile: ${user.uid}', tag: 'AUTH_REPOSITORY');

      await _firestore.collection('Users').doc(user.uid).update(data);
      
      AppLogger.success('Profile updated successfully', tag: 'AUTH_REPOSITORY');
    } catch (e) {
      AppLogger.error('Failed to update profile: $e', tag: 'AUTH_REPOSITORY');
      rethrow;
    }
  }

  /// Faz upload da foto de perfil com compressão automática
  Future<String> uploadProfilePhoto(File imageFile) async {
    File? compressedFile;
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      AppLogger.info('Uploading profile photo for: ${user.uid}', tag: 'AUTH_REPOSITORY');

      // ✅ Comprimir imagem antes do upload (1080px, quality 75)
      compressedFile = await _compressor.compressFileToTempFile(imageFile);
      
      // Upload para o Storage usando path que match com as regras de segurança
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child('users').child(user.uid).child('profile').child('avatar_$timestamp.jpg');
      
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'private,max-age=31536000,immutable',
        customMetadata: {
          'userId': user.uid,
          'uploadTimestamp': timestamp.toString(),
          'source': 'flutter_app',
          'compressed': 'true',
        },
      );
      
      final uploadTask = ref.putFile(compressedFile, metadata);
      final snapshot = await uploadTask;
      
      // Obter URL de download
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      // Atualizar documento do usuário
      await _firestore.collection('Users').doc(user.uid).update({
        'photoUrl': downloadUrl,
      });

      AppLogger.success('Profile photo uploaded successfully', tag: 'AUTH_REPOSITORY');
      
      // Limpar arquivo comprimido temporário
      if (compressedFile.path != imageFile.path && await compressedFile.exists()) {
        await compressedFile.delete();
      }
      
      return downloadUrl;
    } catch (e) {
      AppLogger.error('Failed to upload profile photo: $e', tag: 'AUTH_REPOSITORY');
      
      // Limpar arquivo comprimido em caso de erro
      try {
        if (compressedFile != null && 
            compressedFile.path != imageFile.path && 
            await compressedFile.exists()) {
          await compressedFile.delete();
        }
      } catch (_) {}
      
      rethrow;
    }
  }

  /// Faz upload de imagem para a galeria
  Future<void> uploadGalleryImage(File imageFile, int index) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      AppLogger.info('Uploading gallery image $index for: ${user.uid}', tag: 'AUTH_REPOSITORY');

      // Upload para o Storage usando path que match com as regras de segurança
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child('users').child(user.uid).child('gallery').child('image_${index}_$timestamp.jpg');
      
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'private,max-age=31536000,immutable',
        customMetadata: {
          'userId': user.uid,
          'index': index.toString(),
          'uploadTimestamp': timestamp.toString(),
        },
      );
      
      final uploadTask = ref.putFile(imageFile, metadata);
      final snapshot = await uploadTask;
      
      // Obter URL de download
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      // Atualizar array de galeria
      await _firestore.collection('Users').doc(user.uid).update({
        'user_gallery.$index': downloadUrl,
      });

      AppLogger.success('Gallery image uploaded successfully', tag: 'AUTH_REPOSITORY');
    } catch (e) {
      AppLogger.error('Failed to upload gallery image: $e', tag: 'AUTH_REPOSITORY');
      rethrow;
    }
  }

  /// Remove imagem da galeria
  Future<void> removeGalleryImage(int index) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      AppLogger.info('Removing gallery image $index for: ${user.uid}', tag: 'AUTH_REPOSITORY');

      // Primeiro, obter a URL atual para deletar do Storage
      final doc = await _firestore.collection('Users').doc(user.uid).get();
      final data = doc.data();
      
      if (data != null && data['user_gallery'] != null) {
        final gallery = data['user_gallery'] as Map<String, dynamic>;
        final imageUrl = gallery[index.toString()] as String?;
        
        if (imageUrl != null) {
          // Deletar do Storage
          try {
            final ref = _storage.refFromURL(imageUrl);
            await ref.delete();
          } catch (e) {
            AppLogger.warning('Failed to delete from storage: $e', tag: 'AUTH_REPOSITORY');
          }
        }
      }

      // Remover do documento
      await _firestore.collection('Users').doc(user.uid).update({
        'user_gallery.$index': FieldValue.delete(),
      });

      AppLogger.success('Gallery image removed successfully', tag: 'AUTH_REPOSITORY');
    } catch (e) {
      AppLogger.error('Failed to remove gallery image: $e', tag: 'AUTH_REPOSITORY');
      rethrow;
    }
  }
}
