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
import 'package:partiu/core/services/cache/app_cache_service.dart';
import 'package:partiu/shared/screens/media_viewer_screen.dart';
import 'package:partiu/core/services/toast_service.dart';

class UserImagesGrid extends StatefulWidget {
  const UserImagesGrid({super.key});

  @override
  State<UserImagesGrid> createState() => _UserImagesGridState();
}

class _UserImagesGridState extends State<UserImagesGrid> {
  final List<bool> _isUploading = List<bool>.filled(9, false);
  List<MediaViewerItem> _viewerItemsCache = <MediaViewerItem>[];
  Map<String, dynamic> _rawGalleryCache = <String, dynamic>{};
  
  /// ✅ State local da galeria (substitui StreamBuilder)
  Map<String, dynamic> _gallery = {};
  bool _loading = true;
  
  /// ✅ Flag para evitar múltiplas chamadas ao ImagePicker simultaneamente
  bool _isPickerActive = false;
  
  @override
  void initState() {
    super.initState();
    debugPrint('=== [UserImagesGrid] 🚀 INIT STATE ===');
    _loadGalleryOnce();
  }

  /// ✅ Carrega galeria uma vez do Firestore
  Future<void> _loadGalleryOnce() async {
    final uid = AppState.currentUserId;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .get();

      if (!mounted) return;

      final data = doc.data();
      var imgs = <String, dynamic>{};

      if (data != null && data.containsKey('user_gallery')) {
        final gallery = data['user_gallery'];

        if (gallery is Map) {
          imgs = Map<String, dynamic>.from(gallery);
        } else if (gallery is List) {
          for (var i = 0; i < gallery.length; i++) {
            final v = gallery[i];
            if (v != null) imgs['image_$i'] = v;
          }
        }
      }

      setState(() {
        _gallery = imgs;
        _rawGalleryCache = imgs;
        _viewerItemsCache = _buildViewerItems(imgs);
        _loading = false;
      });

      debugPrint('[UserImagesGrid] ✅ Galeria carregada: ${imgs.length} imagens');
    } catch (e) {
      debugPrint('[UserImagesGrid] ❌ Erro ao carregar galeria: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// ✅ Atualiza galeria localmente após upload bem-sucedido (optimistic update)
  void _updateGalleryLocally(int index, String url) {
    final key = 'image_$index';
    final updated = Map<String, dynamic>.from(_gallery);
    updated[key] = {'url': url};
    
    setState(() {
      _gallery = updated;
      _rawGalleryCache = updated;
      _viewerItemsCache = _buildViewerItems(updated);
    });
    
    debugPrint('[UserImagesGrid] ✅ Galeria atualizada localmente: index=$index');
  }

  /// ✅ Remove imagem localmente após delete bem-sucedido (optimistic update)
  void _removeImageLocally(int index) {
    final key = 'image_$index';
    final updated = Map<String, dynamic>.from(_gallery);
    updated.remove(key);
    
    setState(() {
      _gallery = updated;
      _rawGalleryCache = updated;
      _viewerItemsCache = _buildViewerItems(updated);
    });
    
    debugPrint('[UserImagesGrid] ✅ Imagem removida localmente: index=$index');
  }

  Future<void> _handleDeleteImage(BuildContext context, int index) async {
    debugPrint('[UserImagesGrid] 🗑️ handleDeleteImage called for index: $index');
    
    final serviceLocator = DependencyProvider.of(context).serviceLocator;
    final i18n = AppLocalizations.of(context);
    final vm = serviceLocator.get<ImageUploadViewModel>();
    
    // Captura traduções antes do await
    final imageDeletedMsg = i18n.translate('image_deleted');
    final imageRemovedMsg = i18n.translate('image_removed');
    final deleteFailedMsg = i18n.translate('delete_failed');
    final failedToRemoveMsg = i18n.translate('failed_to_remove_image');
    
    final result = await vm.deleteGalleryImageAtIndex(index: index);
    
    if (!mounted) {
      debugPrint('[UserImagesGrid] ⚠️ Widget unmounted before delete completed');
      return;
    }
    
    if (result.success) {
      debugPrint('[UserImagesGrid] ✅ Delete SUCCESS for index: $index');
      // ✅ Atualizar UI localmente (optimistic update)
      _removeImageLocally(index);
      if (!context.mounted) return;
      ToastService.showSuccess(
        message: imageDeletedMsg.isNotEmpty ? imageDeletedMsg : imageRemovedMsg,
      );
    } else {
      debugPrint('[UserImagesGrid] ❌ Delete FAILED for index: $index - ${result.errorMessage}');
      if (!context.mounted) return;
      ToastService.showError(
        message: deleteFailedMsg.isNotEmpty ? deleteFailedMsg : failedToRemoveMsg,
      );
    }
  }

  Future<void> _handleAddImage(BuildContext context, int index) async {
    debugPrint('[UserImagesGrid] 🖼️ handleAddImage called for index: $index');
    
    // ✅ Bloqueia se já há um picker ativo ou upload em andamento
    if (_isPickerActive || _isUploading.any((uploading) => uploading)) {
      debugPrint('[UserImagesGrid] ⚠️ Picker already active or upload in progress, ignoring tap');
      return;
    }
    
    // Captura dependências antes de qualquer await
    final i18n = AppLocalizations.of(context);
    final serviceLocator = DependencyProvider.of(context).serviceLocator;
    final vm = serviceLocator.get<ImageUploadViewModel>();
    
    // ✅ Marca picker como ativo
    _isPickerActive = true;
    
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
        _showErrorToastWithI18n(context, i18n, i18n.translate('selected_file_not_found'));
        return;
      }
      
      final fileSize = await file.length();
      debugPrint('[UserImagesGrid] 📏 File size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)}MB');
      
      if (fileSize == 0) {
        debugPrint('[UserImagesGrid] ❌ File size is zero');
        if (!context.mounted) return;
        _showErrorToastWithI18n(context, i18n, i18n.translate('invalid_file_zero_size'));
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
        // ✅ Recarregar galeria para obter nova URL
        await _loadGalleryOnce();
        if (!context.mounted) return;
        ToastService.showSuccess(
          message: i18n.translate('image_uploaded'),
        );
      } else {
        debugPrint('[UserImagesGrid] ❌ Upload FAILED for index: $index - ${result.errorMessage}');
        if (!context.mounted) return;
        ToastService.showError(
          message: '${i18n.translate('failed_to_upload_image')}: ${result.errorMessage}',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[UserImagesGrid] 💥 Exception in _handleAddImage: $e');
      debugPrint('[UserImagesGrid] 📚 StackTrace: $stackTrace');
      if (!context.mounted) return;
      ToastService.showError(
        message: '${i18n.translate('unexpected_error')}: $e',
      );
    } finally {
      // ✅ Liberar picker e garantir que loading seja removido
      _isPickerActive = false;
      if (mounted) {
        setState(() => _isUploading[index] = false);
        debugPrint('[UserImagesGrid] 🏁 Loading state cleared for index: $index');
      }
    }
  }

  void _showErrorToastWithI18n(BuildContext context, AppLocalizations i18n, String messageKey) {
    ToastService.showError(
      message: i18n.translate(messageKey),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('=== [UserImagesGrid] 🏗️ BUILD CALLED ===');
    debugPrint('[UserImagesGrid] 🏗️ Building widget - ${DateTime.now()}');
    final i18n = AppLocalizations.of(context);
    final uid = AppState.currentUserId;
    debugPrint('[UserImagesGrid] 👤 Current userId: $uid');
    
    if (uid == null) {
      debugPrint('[UserImagesGrid] ❌ No authenticated user');
      return Center(child: Text(i18n.translate('user_not_authenticated')));
    }

    // ✅ Carregando pela primeira vez
    if (_loading) {
      debugPrint('[UserImagesGrid] ⏳ Loading gallery...');
      return const GallerySkeleton();
    }

    final imgs = _gallery;

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
        // ✅ Verifica se alguma operação está em andamento (picker ativo ou upload)
        final isAnyOperationActive = _isPickerActive || _isUploading.any((u) => u);
        return _UserImageCell(
          key: ValueKey(key),
          url: url,
          index: index,
          isUploading: _isUploading[index],
          isAnyOperationActive: isAnyOperationActive,
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
}

class _UserImageCell extends StatelessWidget {
  const _UserImageCell({
    required this.url,
    required this.index,
    required this.isUploading,
    required this.isAnyOperationActive,
    required this.onAdd,
    required this.onDelete,
    this.onOpenViewer,
    super.key,
  });
  final String? url;
  final int index;
  final bool isUploading;
  /// ✅ Indica se alguma operação (picker/upload) está ativa em qualquer célula
  final bool isAnyOperationActive;
  final VoidCallback onAdd;
  final VoidCallback onDelete;
  final VoidCallback? onOpenViewer;

  @override
  Widget build(BuildContext context) {
    // ✅ Desabilita interação em células vazias quando há operação ativa
    final hasImage = url != null && url!.isNotEmpty;
    final canTap = hasImage || !isAnyOperationActive;
    
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canTap
              ? () {
                  debugPrint('[_UserImageCell] 👆 Cell tapped - index: $index, hasUrl: $hasImage, isUploading: $isUploading');
                  
                  if (hasImage) {
                    debugPrint('[_UserImageCell] 🖼️ Opening image viewer for: ${url!.substring(0, 50)}...');
                    onOpenViewer?.call();
                  } else {
                    debugPrint('[_UserImageCell] ➕ Calling onAdd for empty cell at index: $index');
                    onAdd();
                  }
                }
              : null,
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
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Icons.image_outlined,
                                color: GlimpseColors.textSubTitle,
                                size: 38,
                              ),
                              Positioned(
                                right: -6,
                                bottom: -6,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(1.5),
                                  child: Icon(
                                    Icons.add_circle,
                                    color: GlimpseColors.primary,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ClipRRect(
                          borderRadius: _cellRadius,
                          child: CachedNetworkImage(
                            imageUrl: url!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            cacheManager: AppCacheService.instance.galleryCacheManager,
                            cacheKey: AppCacheService.instance.galleryCacheKey(url!),
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
