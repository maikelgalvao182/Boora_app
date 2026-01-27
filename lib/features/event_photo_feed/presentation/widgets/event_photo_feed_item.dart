import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/core/services/cache/media_cache_manager.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_images_slider.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_like_button.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/tagged_participants_avatars.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

class EventPhotoFeedItem extends StatelessWidget {
  const EventPhotoFeedItem({
    super.key,
    required this.item,
    required this.onCommentsTap,
  required this.onDelete,
  this.onDeleteImage,
  });

  final EventPhotoModel item;
  final VoidCallback onCommentsTap;
  final Future<void> Function() onDelete;
  final Future<void> Function(int index)? onDeleteImage;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.thumbnailUrl ?? item.imageUrl;
    final isThumbnail = item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty;
    final canDelete = (AppState.currentUser.value?.userId ?? '') == item.userId;
    final canDeleteImages = canDelete && item.imageUrls.length > 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StableAvatar(
                userId: item.userId,
                size: 38,
                photoUrl: item.userPhotoUrl,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: nome > activity name time ago + menu
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                // Nome do usuário com badge
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: ReactiveUserNameWithBadge(
                                    userId: item.userId,
                                    style: GoogleFonts.getFont(
                                      FONT_PLUS_JAKARTA_SANS,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: GlimpseColors.primaryColorLight,
                                    ),
                                  ),
                                ),
                                // Separador >
                                TextSpan(
                                  text: ' > ',
                                  style: GoogleFonts.getFont(
                                    FONT_PLUS_JAKARTA_SANS,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: GlimpseColors.textSubTitle,
                                  ),
                                ),
                                // Emoji + Activity name
                                TextSpan(
                                  text: '${item.eventEmoji} ${item.eventTitle}',
                                  style: GoogleFonts.getFont(
                                    FONT_PLUS_JAKARTA_SANS,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: GlimpseColors.primary,
                                  ),
                                ),
                                // Time ago
                                if (item.createdAt != null)
                                  TextSpan(
                                    text: ' ${TimeAgoHelper.format(context, timestamp: item.createdAt!.toDate())}',
                                    style: GoogleFonts.getFont(
                                      FONT_PLUS_JAKARTA_SANS,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: GlimpseColors.textSubTitle,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // Avatares dos participantes marcados
                    if (item.taggedParticipants.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            TaggedParticipantsAvatars(
                              participants: item.taggedParticipants,
                              maxVisible: 3,
                              avatarSize: 22,
                              overlap: 8,
                            ),
                          ],
                        ),
                      ),
                    if ((item.caption ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.caption!.trim(),
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: GlimpseColors.primaryColorLight,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Imagens do post - slider horizontal se múltiplas
                    if (item.imageUrls.isNotEmpty)
                      EventPhotoImagesSlider(
                        imageUrls: item.imageUrls,
                        thumbnailUrls: item.thumbnailUrls,
                        height: 180,
                        imageWidth: 160,
                        spacing: 10,
                        onDeleteImage: canDeleteImages ? onDeleteImage : null,
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          cacheManager: MediaCacheManager.forThumbnail(isThumbnail),
                          width: 160,
                          height: 180,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 160,
                            height: 180,
                            color: GlimpseColors.lightTextField,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 160,
                            height: 180,
                            color: GlimpseColors.lightTextField,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: onCommentsTap,
                          borderRadius: BorderRadius.circular(999),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                IconsaxPlusLinear.message_2,
                                size: 18,
                                color: GlimpseColors.textSubTitle,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${item.commentsCount}',
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: GlimpseColors.textSubTitle,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        EventPhotoLikeButton(
                          photoId: item.id,
                          initialCount: item.likesCount,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
