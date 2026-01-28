import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/features/profile/presentation/controllers/follow_controller.dart';

class ProfileActionsSection extends StatelessWidget {
  const ProfileActionsSection({
    super.key,
    this.onAddFriend,
    this.onMessage,
    this.showFollowButton = false,
    this.showMessageButton = true,
    this.followController,
  });

  final VoidCallback? onAddFriend;
  final VoidCallback? onMessage;
  final bool showFollowButton;
  final bool showMessageButton;
  final FollowController? followController;

  @override
  Widget build(BuildContext context) {
    debugPrint('🎨 [ProfileActionsSection] build() chamado');
    debugPrint('   showFollowButton: $showFollowButton, showMessageButton: $showMessageButton');
    
    // Se nenhum botão deve ser mostrado, retorna vazio
    if (!showFollowButton && !showMessageButton) {
      debugPrint('   ↩️ Retornando SizedBox.shrink');
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 22),
      child: Row(
        children: [
          if (showFollowButton && followController != null) ...[
            Expanded(
              child: _FollowButtonIsolated(controller: followController!),
            ),
            if (showMessageButton) const SizedBox(width: 8),
          ],
          if (showMessageButton)
            Expanded(
              child: GlimpseButton(
                text: 'Mensagem',
                backgroundColor: GlimpseColors.primary,
                textColor: Colors.white,
                icon: Iconsax.message,
                onTap: onMessage ?? () {},
                height: 52,
                fontSize: 14,
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget isolado para o botão de seguir - evita rebuild do pai
class _FollowButtonIsolated extends StatelessWidget {
  const _FollowButtonIsolated({required this.controller});
  
  final FollowController controller;

  @override
  Widget build(BuildContext context) {
    debugPrint('🔘 [_FollowButtonIsolated] build() chamado');
    return ValueListenableBuilder<bool>(
      valueListenable: controller,
      builder: (context, isFollowing, _) {
        debugPrint('🔘 [_FollowButtonIsolated] ValueListenable isFollowing builder: $isFollowing');
        return ValueListenableBuilder<bool>(
          valueListenable: controller.isLoading,
          builder: (context, isLoading, _) {
            debugPrint('🔘 [_FollowButtonIsolated] ValueListenable isLoading builder: $isLoading');
            final followLabel = isFollowing ? 'Seguindo' : 'Seguir';
            final followOutline = !isFollowing;
            final followBgColor = isFollowing 
                ? GlimpseColors.primaryLight 
                : GlimpseColors.borderColorLight;
            const followTextColor = Colors.black;
            final followIcon = isFollowing ? Iconsax.user_tick : Iconsax.user_add;

            debugPrint('🔘 [_FollowButtonIsolated] Renderizando GlimpseButton:');
            debugPrint('   label: $followLabel, outline: $followOutline, isLoading: $isLoading');

            return GlimpseButton(
              text: followLabel,
              backgroundColor: followBgColor,
              textColor: followTextColor,
              icon: followIcon,
              outline: followOutline,
              onTap: () {
                debugPrint('🔘 [_FollowButtonIsolated] GlimpseButton onTap() chamado');
                controller.toggleFollow();
              },
              height: 52,
              fontSize: 14,
            );
          },
        );
      },
    );
  }
}
