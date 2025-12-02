import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

/// Widget para exibir e editar foto de perfil
/// Otimizado com RepaintBoundary
class ProfilePhotoWidget extends StatelessWidget {
  final String userId;
  final VoidCallback onTap;
  final bool isUploading;
  
  const ProfilePhotoWidget({
    super.key,
    required this.userId,
    required this.onTap,
    this.isUploading = false,
  });
  
  @override
  Widget build(BuildContext context) {
    debugPrint('[ProfilePhotoWidget] 🏗️ Building widget - userId: $userId, isUploading: $isUploading');
    debugPrint('[ProfilePhotoWidget] 🔗 onTap callback type: ${onTap.runtimeType}');
    
    return RepaintBoundary(
      child: Center(
        child: GestureDetector(
          onTap: () {
            debugPrint('[ProfilePhotoWidget] 👆 Avatar tapped - userId: $userId, isUploading: $isUploading');
            debugPrint('[ProfilePhotoWidget] 🔍 onTap callback is: ${onTap.toString()}');
            if (!isUploading) {
              debugPrint('[ProfilePhotoWidget] ✅ Calling onTap callback');
              try {
                onTap();
                debugPrint('[ProfilePhotoWidget] ✅ onTap callback executed successfully');
              } catch (e) {
                debugPrint('[ProfilePhotoWidget] ❌ Error executing onTap callback: $e');
              }
            } else {
              debugPrint('[ProfilePhotoWidget] ⏳ Upload in progress, ignoring tap');
            }
          },
          child: Stack(
            children: [
              // Avatar
              SizedBox(
                width: 120,
                height: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: StableAvatar(
                    userId: userId,
                    size: 120,
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
              
              // Loading overlay
              if (isUploading)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.5),
                      child: const Center(
                        child: CupertinoActivityIndicator(
                          color: Colors.white,
                          radius: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              
              // Camera icon button
              if (!isUploading)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColorLight,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
