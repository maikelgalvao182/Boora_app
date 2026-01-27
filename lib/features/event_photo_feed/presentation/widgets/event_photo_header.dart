import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/core/services/cache/media_cache_manager.dart';
import 'package:partiu/features/event_photo_feed/data/models/tagged_participant_model.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_images_slider.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/tagged_participants_avatars.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

/// Widget reutilizável para o header de um post de foto de evento
/// Exibe: avatar, nome > activity name time ago, participantes marcados, legenda e imagem(ns)
class EventPhotoHeader extends StatelessWidget {
  const EventPhotoHeader({
    super.key,
    required this.userId,
    this.userPhotoUrl,
    required this.eventEmoji,
    required this.eventTitle,
    this.createdAt,
    this.taggedParticipants = const [],
    this.caption,
    required this.imageUrl,
    this.thumbnailUrl,
    this.imageUrls = const [],
    this.thumbnailUrls = const [],
    this.trailingWidget,
  });

  final String userId;
  final String? userPhotoUrl;
  final String eventEmoji;
  final String eventTitle;
  final Timestamp? createdAt;
  final List<TaggedParticipantModel> taggedParticipants;
  final String? caption;
  final String imageUrl;
  final String? thumbnailUrl;
  final List<String> imageUrls;
  final List<String> thumbnailUrls;
  final Widget? trailingWidget;

  @override
  Widget build(BuildContext context) {
    final displayImageUrl = thumbnailUrl ?? imageUrl;
    final isThumbnail = thumbnailUrl != null && thumbnailUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar + Nome + Menu
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StableAvatar(
              userId: userId,
              size: 38,
              photoUrl: userPhotoUrl,
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
                                  userId: userId,
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
                                text: '$eventEmoji $eventTitle',
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: GlimpseColors.primary,
                                ),
                              ),
                              // Time ago
                              if (createdAt != null)
                                TextSpan(
                                  text: ' ${TimeAgoHelper.format(context, timestamp: createdAt!.toDate())}',
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
                      if (trailingWidget != null) trailingWidget!,
                    ],
                  ),
                  // Avatares dos participantes marcados
                  if (taggedParticipants.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          TaggedParticipantsAvatars(
                            participants: taggedParticipants,
                            maxVisible: 3,
                            avatarSize: 22,
                            overlap: 8,
                          ),
                        ],
                      ),
                    ),
                  // Legenda
                  if ((caption ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      caption!.trim(),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: GlimpseColors.primaryColorLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        // Imagem(ns) do post
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: 200,
                child: imageUrls.isNotEmpty
                    ? EventPhotoImagesSlider(
                        imageUrls: imageUrls,
                        thumbnailUrls: thumbnailUrls,
                        height: 200,
                      )
                    : CachedNetworkImage(
                        imageUrl: displayImageUrl,
                        cacheManager: MediaCacheManager.forThumbnail(isThumbnail),
                        width: 200,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => Container(
                          height: 200,
                          color: GlimpseColors.lightTextField,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: 200,
                          color: GlimpseColors.lightTextField,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
