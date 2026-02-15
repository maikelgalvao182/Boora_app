import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:partiu/features/profile/presentation/styles/edit_profile_styles.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:iconsax/iconsax.dart';

/// StatelessWidget for profile photo display and editing
/// Optimized for performance with RepaintBoundary isolation
class ProfilePhotoComponent extends StatelessWidget {

  const ProfilePhotoComponent({
    required this.userId, 
    required this.onTap, 
    super.key,
    this.photoUrl,
    this.isUploading = false,
  });
  final String userId;
  final String? photoUrl;
  final VoidCallback onTap;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: isUploading ? null : () {
          onTap();
        },
        child: Center(
          child: SizedBox(
            width: EditProfileStyles.profilePhotoSize,
            height: EditProfileStyles.profilePhotoSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Circular avatar with stable base
                // Key muda quando photoUrl muda para forçar rebuild
                ClipOval(
                  child: StableAvatar(
                    key: ValueKey('profile-$userId-${photoUrl ?? ""}'),
                    userId: userId,
                    size: EditProfileStyles.profilePhotoSize,
                    borderRadius: BorderRadius.all(
                      Radius.circular(EditProfileStyles.profilePhotoBorderRadius),
                    ),
                  ),
                ),
                
                // Loading overlay with Cupertino spinner
                if (isUploading)
                  Positioned.fill(
                    child: ClipOval(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.5),
                        child: const Center(
                          child: CupertinoActivityIndicator(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                
                // Camera button overlay (bottom-right)
                if (!isUploading)
                  Positioned(
                    right: EditProfileStyles.cameraButtonRight,
                    bottom: EditProfileStyles.cameraButtonBottom,
                    child: Container(
                      width: EditProfileStyles.cameraButtonSize,
                      height: EditProfileStyles.cameraButtonSize,
                      decoration: EditProfileStyles.cameraButtonDecoration,
                      child: Center(
                        child: Icon(
                          Iconsax.edit_2,
                          color: Colors.white,
                          size: EditProfileStyles.cameraIconSize,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
