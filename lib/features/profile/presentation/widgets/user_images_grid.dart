import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/config/dependency_provider.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/profile/presentation/viewmodels/image_upload_view_model.dart';
import 'package:partiu/features/profile/presentation/widgets/media_delete_button.dart';
import 'package:partiu/features/profile/presentation/widgets/gallery_skeleton.dart';
import 'package:partiu/shared/screens/media_viewer_screen.dart';
import 'package:partiu/shared/services/toast_service.dart';

class UserImagesGrid extends StatefulWidget {
  const UserImagesGrid({super.key});

  @override
  State<UserImagesGrid> createState() => _UserImagesGridState();
}

class _UserImagesGridState extends State<UserImagesGrid> {
  final List<bool> _isUploading = List<bool>.filled(9, false);
  List<MediaViewerItem> _viewerItemsCache = <MediaViewerItem>[];
  Map<String, dynamic> _rawGalleryCache = <String, dynamic>{};
  
  @override
  void initState() {
    super.initState();
    debugPrint('=== [UserImagesGrid] 🚀 INIT STATE ===');
  }

  Future<void> _handleDeleteImage(BuildContext context, int index) async {
    debugPrint('[UserImagesGrid] 🗑️ handleDeleteImage called for index: $index');
    
    final serviceLocator = DependencyProvider.of(context).serviceLocator;
    final i18n = AppLocalizations.of(context);
    final vm = serviceLocator.get<ImageUploadViewModel>();
    
    // Captura traduções antes do await
    final imageDeletedMsg = i18n.translate('image_deleted');
    final imageRemovedMsg = i18n.translate('image_removed_successfully');
    final deleteFailedMsg = i18n.translate('delete_failed');
    
    final result = await vm.deleteGalleryImageAtIndex(index: index);
    
    if (!mounted) {
      debugPrint('[UserImagesGrid] ⚠️ Widget unmounted before delete completed');
      return;
    }
    
    if (result.success) {
      debugPrint('[UserImagesGrid] ✅ Delete SUCCESS for index: $index');
      if (!context.mounted) return;
      ToastService.showError(
        context: context,
        title: imageDeletedMsg,
        subtitle: imageRemovedMsg,
      );
    } else {
      debugPrint('[UserImagesGrid] ❌ Delete FAILED for index: $index - ${result.errorMessage}');
      if (!context.mounted) return;
      ToastService.showError(
        context: context,
        title: deleteFailedMsg,
        subtitle: 'Failed to remove image: ${result.errorMessage}',
      );
    }
  }

  Future<void> _handleAddImage(BuildContext context, int index) async {
    debugPrint('[UserImagesGrid] 🖼️ handleAddImage called for index: $index');
    
    // Captura dependências antes de qualquer await
    final i18n = AppLocalizations.of(context);
    final serviceLocator = DependencyProvider.of(context).serviceLocator;
    final vm = serviceLocator.get<ImageUploadViewModel>();
    
    try {
      final picker = ImagePicker();
      debugPrint('[UserImagesGrid] 📸 Opening image picker...');
      
      final picked = await picker.pickImage(
        source: ImageSource.gallery, 
        imageQuality: 90,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      
      if (picked == null) {
        debugPrint('[UserImagesGrid] ❌ No image picked (user cancelled)');
        return;
      }
      
      debugPrint('[UserImagesGrid] ✅ Image picked: ${picked.path}');
      final file = File(picked.path);
      
      // Verificar se arquivo existe e tem tamanho válido
      if (!await file.exists()) {
        debugPrint('[UserImagesGrid] ❌ Selected file does not exist');
        if (!context.mounted) return;
        _showErrorToastWithI18n(context, i18n, 'Arquivo selecionado não foi encontrado');
        return;
      }
      
      final fileSize = await file.length();
      debugPrint('[UserImagesGrid] 📏 File size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)}MB');
      
      if (fileSize == 0) {
        debugPrint('[UserImagesGrid] ❌ File size is zero');
        if (!context.mounted) return;
        _showErrorToastWithI18n(context, i18n, 'Arquivo inválido (tamanho zero)');
        return;
      }
      
      // Mostrar loading IMEDIATAMENTE
      if (mounted) {
        setState(() => _isUploading[index] = true);
        debugPrint('[UserImagesGrid] ⏳ Loading state set for index: $index');
      }
      
      debugPrint('[UserImagesGrid] 🚀 Starting upload for index: $index with ViewModel');
      debugPrint('[UserImagesGrid] 🔍 ServiceLocator obtained: ${serviceLocator.runtimeType}');
      
      final result = await vm.uploadGalleryImageAtIndex(originalFile: file, index: index);
      
      if (!mounted) {
        debugPrint('[UserImagesGrid] ⚠️ Widget unmounted before upload completed');
        return;
      }
      
      if (result.success) {
        debugPrint('[UserImagesGrid] ✅ Upload SUCCESS for index: $index');
        if (!context.mounted) return;
        ToastService.showSuccess(
          context: context,
          title: i18n.translate('image_uploaded'),
          subtitle: i18n.translate('image_uploaded_successfully'),
        );
      } else {
        debugPrint('[UserImagesGrid] ❌ Upload FAILED for index: $index - ${result.errorMessage}');
        if (!context.mounted) return;
        _showErrorToastWithI18n(context, i18n, '${i18n.translate('failed_to_upload_image')}: ${result.errorMessage}');
      }
    } catch (e, stackTrace) {
      debugPrint('[UserImagesGrid] 💥 Exception in _handleAddImage: $e');
      debugPrint('[UserImagesGrid] 📚 StackTrace: $stackTrace');
      if (!context.mounted) return;
      _showErrorToastWithI18n(context, i18n, 'Erro inesperado: $e');
    } finally {
      // Garantir que loading seja removido
      if (mounted) {
        setState(() => _isUploading[index] = false);
        debugPrint('[UserImagesGrid] 🏁 Loading state cleared for index: $index');
      }
    }
  }

  void _showErrorToastWithI18n(BuildContext context, AppLocalizations i18n, String message) {
    ToastService.showError(
      context: context,
      title: i18n.translate('upload_failed'),
      subtitle: message,
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('=== [UserImagesGrid] 🏗️ BUILD CALLED ===');
    debugPrint('[UserImagesGrid] 🏗️ Building widget - ${DateTime.now()}');
    final uid = AppState.currentUserId;
    debugPrint('[UserImagesGrid] 👤 Current userId: $uid');
    
    if (uid == null) {
      debugPrint('[UserImagesGrid] ❌ No authenticated user');
      return const Center(child: Text('Usuário não autenticado'));
    }

    // ✅ REATIVO: Usa StreamBuilder para atualizações em tempo real
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _getUserStream(uid),
      builder: (context, snap) {
        debugPrint('[UserImagesGrid] 📡 StreamBuilder rebuild - hasData: ${snap.hasData}');
        
        if (!snap.hasData) {
          debugPrint('[UserImagesGrid] ⏳ Waiting for Firestore data...');
          return const GallerySkeleton();
        }
        
        final data = snap.data?.data();
        var imgs = <String, dynamic>{};
        
        if (data != null && data.containsKey('user_gallery')) {
          final gallery = data['user_gallery'];
          debugPrint('[UserImagesGrid] 🖼️ Processing user gallery - type: ${gallery.runtimeType}');
          
          if (gallery is Map) {
            imgs = Map<String, dynamic>.from(gallery);
            debugPrint('[UserImagesGrid] 📝 Gallery is Map with ${imgs.length} items');
          } else if (gallery is List) {
            debugPrint('[UserImagesGrid] 📝 Gallery is List with ${gallery.length} items');
            for (var i = 0; i < gallery.length; i++) {
              final v = gallery[i];
              if (v != null) imgs['image_$i'] = v;
            }
          }
        } else {
          debugPrint('[UserImagesGrid] ❌ Gallery is null or missing');
        }

        // Atualiza caches somente se mapa mudou
        if (imgs.length != _rawGalleryCache.length || 
            !_rawGalleryCache.keys.toSet().containsAll(imgs.keys)) {
          _rawGalleryCache = imgs;
          _viewerItemsCache = _buildViewerItems(imgs);
        }

        return GridView.builder(
          physics: const ScrollPhysics(),
          itemCount: 9,
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 4 / 5,
          ),
          itemBuilder: (context, index) {
            final key = 'image_$index';
            final item = imgs[key];
            final url = item is Map<String, dynamic> ? (item['url'] as String?) : null;
            return _UserImageCell(
              key: ValueKey(key),
              url: url,
              index: index,
              isUploading: _isUploading[index],
              onAdd: () => _handleAddImage(context, index),
              onDelete: () => _handleDeleteImage(context, index),
              onOpenViewer: url == null
                  ? null
                  : () {
                      final startIndex = _viewerItemsCache.indexWhere((it) => it.url == url);
                      if (startIndex < 0) return;
                      Navigator.of(context).push(
                        PageRouteBuilder<void>(
                          pageBuilder: (context, animation, secondaryAnimation) => MediaViewerScreen(
                            items: _viewerItemsCache,
                            initialIndex: startIndex,
                            disableHero: true,
                          ),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                        ),
                      );
                    },
            );
          },
        );
      },
    );
  }

  List<MediaViewerItem> _buildViewerItems(Map<String, dynamic> imgs) {
    final orderedEntries = imgs.entries
        .where((e) => e.value is Map<String, dynamic>)
        .map((e) => MapEntry(e.key, e.value as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return orderedEntries
        .where((e) => (e.value['url'] ?? '').toString().isNotEmpty)
        .map((e) => MediaViewerItem(
              url: e.value['url'] as String,
              heroTag: 'media_${e.value['url']}',
            ))
        .toList(growable: false);
  }
  
  /// Stream do documento do usuário no Firestore para atualizações em tempo real
  Stream<DocumentSnapshot<Map<String, dynamic>>> _getUserStream(String userId) {
    debugPrint('[UserImagesGrid] 📡 Creating Firestore stream for user: $userId');
    return FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .snapshots();
  }
}

class _UserImageCell extends StatelessWidget {
  const _UserImageCell({
    required this.url,
    required this.index,
    required this.isUploading,
    required this.onAdd,
    required this.onDelete,
    this.onOpenViewer,
    super.key,
  });
  final String? url;
  final int index;
  final bool isUploading;
  final VoidCallback onAdd;
  final VoidCallback onDelete;
  final VoidCallback? onOpenViewer;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            debugPrint('[_UserImageCell] 👆 Cell tapped - index: $index, hasUrl: ${url != null && url!.isNotEmpty}, isUploading: $isUploading');
            
            if (url != null && url!.isNotEmpty) {
              debugPrint('[_UserImageCell] 🖼️ Opening image viewer for: ${url!.substring(0, 50)}...');
              onOpenViewer?.call();
            } else {
              debugPrint('[_UserImageCell] ➕ Calling onAdd for empty cell at index: $index');
              onAdd();
            }
          },
          borderRadius: _cellRadius,
          child: Ink(
            decoration: const BoxDecoration(
              color: GlimpseColors.lightTextField,
              borderRadius: _cellRadius,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: url == null
                      ? Center(
                          child: Icon(
                            CupertinoIcons.plus_circle,
                            color: GlimpseColors.textSubTitle,
                            size: 35,
                          ),
                        )
                      : ClipRRect(
                          borderRadius: _cellRadius,
                          child: CachedNetworkImage(
                            imageUrl: url!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorWidget: (context, u, error) => const Icon(
                              Icons.broken_image,
                              color: GlimpseColors.textSubTitle,
                            ),
                          ),
                        ),
                ),
                if (isUploading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: _cellRadius,
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (url != null && url!.isNotEmpty && !isUploading)
                  MediaDeleteButton(
                    onDelete: onDelete,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const BorderRadius _cellRadius = BorderRadius.all(Radius.circular(8));
