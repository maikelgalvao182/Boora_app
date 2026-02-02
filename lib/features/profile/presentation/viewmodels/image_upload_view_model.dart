import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/managers/session_manager.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/services/image_compress_service.dart';
import 'package:partiu/features/profile/data/services/profile_gallery_cache_service.dart';

class OperationResult {
  const OperationResult._(this.success, this.errorMessage);
  const OperationResult.success() : this._(true, null);
  const OperationResult.error(String? message) : this._(false, message);
  final bool success;
  final String? errorMessage;
}

/// ViewModel que orquestra upload e deleção de imagens da galeria do usuário
class ImageUploadViewModel {
  ImageUploadViewModel({ImageCompressService? compressor})
      : _compressor = compressor ?? const ImageCompressService();
      
  final ImageCompressService _compressor;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  Future<OperationResult> uploadGalleryImageAtIndex({
    required File originalFile,
    required int index,
  }) async {
    print('[ImageUploadVM] 🚀 uploadGalleryImageAtIndex START - index: $index');
    print('[ImageUploadVM] 📁 Original file path: ${originalFile.path}');
    print('[ImageUploadVM] 🔍 File exists: ${await originalFile.exists()}');
    File? compressed;
    try {
      final uid = AppState.currentUserId;
      print('[ImageUploadVM] 👤 Current userId: $uid');
      
      // Verificar autenticação Firebase
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      print('[ImageUploadVM] 🔐 Firebase Auth user: ${firebaseUser?.uid}');
      print('[ImageUploadVM] 🔐 Firebase Auth email: ${firebaseUser?.email}');
      
      if (uid == null || uid.isEmpty) {
        print('[ImageUploadVM] ❌ User not authenticated in AppState');
        return const OperationResult.error('Usuário não autenticado');
      }
      
      if (firebaseUser == null) {
        print('[ImageUploadVM] ❌ User not authenticated in Firebase Auth');
        return const OperationResult.error('Firebase Auth: usuário não autenticado');
      }

      // Validar tamanho da imagem (15MB)
      final imageSize = await originalFile.length();
      print('[ImageUploadVM] 📏 Image size: ${(imageSize / (1024 * 1024)).toStringAsFixed(2)}MB');
      
      const maxImageSize = 15 * 1024 * 1024;
      if (imageSize > maxImageSize) {
        final sizeMB = (imageSize / (1024 * 1024)).toStringAsFixed(1);
        print('[ImageUploadVM] ❌ Image too large: ${sizeMB}MB');
        return OperationResult.error('Imagem muito grande (${sizeMB}MB). Máximo permitido: 15MB.');
      }

      // Comprimir imagem
      print('[ImageUploadVM] 🗜️ Compressing image...');
      compressed = await _compressor.compressFileToTempFile(originalFile);
      print('[ImageUploadVM] ✅ Image compressed');

      // Upload para Storage
      final ts = DateTime.now().millisecondsSinceEpoch;
      final imagePath = 'users/$uid/gallery/image_$ts.jpg';
      print('[ImageUploadVM] 📤 Uploading to Storage: $imagePath');
      
      final imageRef = _storage.ref().child(imagePath);

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'userId': uid,
          'galleryIndex': index.toString(),
          'uploadTimestamp': ts.toString(),
          'source': 'flutter_app',
          'quality': '90',
        },
      );

      final imageTask = imageRef.putFile(compressed, metadata);
      final imageSnap = await imageTask;
      final imageUrl = await imageSnap.ref.getDownloadURL();
      print('[ImageUploadVM] ✅ Storage upload complete - URL: ${imageUrl.substring(0, 50)}...');

      // Salvar no Firestore
      final imageFieldKey = 'image_$index';
      print('[ImageUploadVM] 💾 Saving to Firestore: users/$uid/user_gallery/$imageFieldKey');
      
      await _firestore.collection('Users').doc(uid).set({
        'user_gallery': {
          imageFieldKey: {
            'url': imageUrl,
            'createdAt': FieldValue.serverTimestamp(),
            'fileName': 'image_$ts.jpg',
            'filePath': imagePath,
            'index': index,
          }
        }
      }, SetOptions(merge: true));
      print('[ImageUploadVM] ✅ Firestore save complete');

      // Invalida cache persistente da galeria (page 0)
      await ProfileGalleryCacheService.instance.invalidateUserGallery(uid);

      // Atualizar sessão local
      print('[ImageUploadVM] 🔄 Refreshing user data...');
      await _refreshUserData(uid);
      print('[ImageUploadVM] ✅ User data refreshed');

      print('[ImageUploadVM] 🎉 uploadGalleryImageAtIndex SUCCESS');
      return const OperationResult.success();
    } catch (e, stackTrace) {
      print('[ImageUploadVM] ❌ uploadGalleryImageAtIndex FAILED: $e');
      print('[ImageUploadVM] 📚 StackTrace: $stackTrace');
      return OperationResult.error(e.toString());
    } finally {
      try {
        if (compressed != null && 
            compressed.path != originalFile.path && 
            await compressed.exists()) {
          await compressed.delete();
        }
      } catch (_) {}
    }
  }

  Future<OperationResult> deleteGalleryImageAtIndex({
    required int index,
  }) async {
    String? existingImageUrl;
    try {
      final uid = AppState.currentUserId;
      if (uid == null || uid.isEmpty) {
        return const OperationResult.error('Usuário não autenticado');
      }

      final primaryKey = 'image_$index';
      final legacyKey = 'img_$index';

      // Buscar dados da imagem no Firestore
      final userDoc = await _firestore.collection('Users').doc(uid).get();
      
      if (!userDoc.exists || userDoc.data() == null) {
        return const OperationResult.error('Documento do usuário não encontrado');
      }

      final userData = userDoc.data()!;
      final userGallery = userData['user_gallery'] as Map<String, dynamic>?;
      Map<String, dynamic>? imageData;
      String? filePath;

      if (userGallery != null) {
        final rawPrimary = userGallery[primaryKey];
        final rawLegacy = userGallery[legacyKey];
        
        if (rawPrimary is Map<String, dynamic>) {
          imageData = rawPrimary;
          filePath = imageData['filePath'] as String?;
        } else if (rawLegacy is Map<String, dynamic>) {
          imageData = rawLegacy;
          filePath = imageData['filePath'] as String?;
        } else if (rawPrimary is String) {
          imageData = {'url': rawPrimary};
        } else if (rawLegacy is String) {
          imageData = {'url': rawLegacy};
        }
      }

      if (imageData == null) {
        return const OperationResult.success(); // Já deletada
      }

      existingImageUrl = imageData['url'] as String?;

      // Deletar do Storage
      if (existingImageUrl != null && existingImageUrl.isNotEmpty) {
        try {
          if (filePath != null && filePath.isNotEmpty) {
            await _storage.ref(filePath).delete();
          } else {
            await _storage.refFromURL(existingImageUrl).delete();
          }
        } catch (e) {
          // Ignora erro de arquivo já deletado
        }
      }

      // Remover do Firestore
      await _firestore.collection('Users').doc(uid).update({
        'user_gallery.$primaryKey': FieldValue.delete(),
        'user_gallery.$legacyKey': FieldValue.delete(),
      });

      // Invalida cache persistente da galeria (page 0)
      await ProfileGalleryCacheService.instance.invalidateUserGallery(uid);

      // Evict cache
      if (existingImageUrl != null && existingImageUrl.isNotEmpty) {
        try {
          await CachedNetworkImage.evictFromCache(existingImageUrl);
        } catch (_) {}
      }

      // Atualizar sessão local
      await _refreshUserData(uid);

      return const OperationResult.success();
    } catch (e) {
      return OperationResult.error(e.toString());
    }
  }

  Future<void> _refreshUserData(String uid) async {
    try {
      final userDoc = await _firestore.collection('Users').doc(uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data()!;
        final user = User.fromDocument(userData);
        SessionManager.instance.currentUser = user;
        AppState.currentUser.value = user;
      }
    } catch (e) {
      // Silently fail - não bloqueia operação principal
    }
  }
}
