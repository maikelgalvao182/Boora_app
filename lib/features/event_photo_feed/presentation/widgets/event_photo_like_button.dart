import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:like_button/like_button.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_like_controller.dart';

class EventPhotoLikeButton extends ConsumerWidget {
  const EventPhotoLikeButton({
    super.key,
    required this.photoId,
    required this.initialCount,
  });

  final String photoId;
  final int initialCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Usa provider síncrono (cache-only) - sem overhead de Stream/Future
    final isLikedFromCache = ref.watch(eventPhotoIsLikedSyncProvider(photoId));
    final countAsync = ref.watch(eventPhotoLikesCountProvider(photoId));
    final uiState = ref.watch(eventPhotoLikeUiProvider(photoId));

    // Prioridade: UI state > cache > initial value
    final isLiked = uiState.isLiked ?? isLikedFromCache;
    final likeCount = uiState.likesCount ?? (countAsync.value ?? initialCount);

    return LikeButton(
      size: 20,
      isLiked: isLiked,
      likeCount: likeCount,
      likeBuilder: (liked) {
        return Icon(
          liked ? Iconsax.heart5 : Iconsax.heart,
          color: liked ? Colors.red : GlimpseColors.textSubTitle,
          size: 20,
        );
      },
      countBuilder: (count, liked, text) {
        final display = text.isEmpty ? '0' : text;
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            display,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        );
      },
      onTap: (liked) async {
        final controller = ref.read(eventPhotoLikeUiProvider(photoId).notifier);
        return controller.toggle(
          currentlyLiked: liked,
          currentCount: likeCount,
        );
      },
    );
  }
}
