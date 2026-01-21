import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_more_menu_button.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

class EventPhotoFeedItem extends StatelessWidget {
  const EventPhotoFeedItem({
    super.key,
    required this.item,
    required this.onCommentsTap,
  required this.onDelete,
  });

  final EventPhotoModel item;
  final VoidCallback onCommentsTap;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.thumbnailUrl ?? item.imageUrl;
  final canDelete = (AppState.currentUser.value?.userId ?? '') == item.userId;

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
                    // Header row: nome + ícone de menu
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: GlimpseColors.primaryColorLight,
                            ),
                          ),
                        ),
                        if (canDelete)
                          EventPhotoMoreMenuButton(
                            title: 'Excluir publicação',
                            message: 'Tem certeza que deseja excluir esta publicação?',
                            destructiveText: 'excluir',
                            onConfirmed: onDelete,
                          ),
                      ],
                    ),
                    // Tag do evento logo abaixo do nome (dentro de Row)
                    Row(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: GlimpseColors.lightTextField,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${item.eventEmoji} ${item.eventTitle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: GlimpseColors.textSubTitle,
                            ),
                          ),
                        ),
                      ],
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 320,
                        placeholder: (_, __) => Container(
                          height: 320,
                          color: GlimpseColors.lightTextField,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: 320,
                          color: GlimpseColors.lightTextField,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: onCommentsTap,
                          child: Text(
                            'Comentários (${item.commentsCount})',
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: GlimpseColors.textSubTitle,
                            ),
                          ),
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
