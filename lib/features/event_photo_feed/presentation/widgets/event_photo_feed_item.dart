import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/core/services/cache/media_cache_manager.dart';
import 'package:partiu/core/utils/app_localizations.dart';
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
    this.onEditCaption,
  });

  final EventPhotoModel item;
  final VoidCallback onCommentsTap;
  final Future<void> Function() onDelete;
  final Future<void> Function(int index)? onDeleteImage;
  final Future<void> Function()? onEditCaption;

  void _showPostOptions(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final canEdit = (AppState.currentUser.value?.userId ?? '') == item.userId;
    
    debugPrint('🔧 [EventPhotoFeedItem] _showPostOptions chamado');
    debugPrint('   - photoId: ${item.id}');
    debugPrint('   - userId do post: ${item.userId}');
    debugPrint('   - currentUserId: ${AppState.currentUser.value?.userId}');
    debugPrint('   - canEdit: $canEdit');
    
    if (!canEdit) {
      debugPrint('   ❌ Usuário não pode editar, retornando');
      return;
    }
    
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              debugPrint('📝 [EventPhotoFeedItem] Editar caption selecionado');
              Navigator.of(context).pop();
              onEditCaption?.call();
            },
            child: Text(
              i18n.translate('event_photo_edit_caption'),
              style: const TextStyle(
                color: CupertinoColors.activeBlue,
                fontSize: 18,
              ),
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              debugPrint('🗑️ [EventPhotoFeedItem] Deletar post selecionado');
              Navigator.of(context).pop();
              _confirmDelete(context);
            },
            child: Text(
              i18n.translate('event_photo_delete_post'),
              style: const TextStyle(
                color: CupertinoColors.destructiveRed,
                fontSize: 18,
              ),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () {
            debugPrint('❎ [EventPhotoFeedItem] Cancelar selecionado');
            Navigator.of(context).pop();
          },
          child: Text(
            i18n.translate('cancel'),
            style: const TextStyle(
              color: CupertinoColors.activeBlue,
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    debugPrint('🗑️ [EventPhotoFeedItem] _confirmDelete chamado');
    debugPrint('   - photoId: ${item.id}');
    debugPrint('   - eventId: ${item.eventId}');
    
    showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(i18n.translate('event_photo_delete_post_title')),
        content: Text(i18n.translate('event_photo_delete_post_message')),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              debugPrint('   ❎ Cancelado pelo usuário');
              Navigator.of(context).pop(false);
            },
            child: Text(
              i18n.translate('cancel'),
              style: const TextStyle(color: CupertinoColors.activeBlue),
            ),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              debugPrint('   ✅ Confirmado pelo usuário, chamando onDelete...');
              Navigator.of(context).pop(true);
              debugPrint('   📤 Executando onDelete callback...');
              onDelete().then((_) {
                debugPrint('   ✅ onDelete completou com sucesso');
              }).catchError((e, stack) {
                debugPrint('   ❌ onDelete falhou: $e');
                debugPrint('   📋 Stack: $stack');
              });
            },
            child: Text(i18n.translate('delete')),
          ),
        ],
      ),
    );
  }

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
                    // Header row: nome > Foi activity name emoji time ago
                    GestureDetector(
                      onLongPress: canDelete ? () => _showPostOptions(context) : null,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                  // "Foi" + Activity name + Emoji
                                  TextSpan(
                                    text: '${AppLocalizations.of(context).translate('feed_action_went')} ${item.eventTitle} ${item.eventEmoji}',
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
                                      text: ' ${TimeAgoHelper.format(context, timestamp: item.createdAt!.toDate(), short: true)}',
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
                          if (canDelete)
                            GestureDetector(
                              onTap: () => _showPostOptions(context),
                              child: const Padding(
                                padding: EdgeInsets.only(left: 8, top: 2),
                                child: Icon(
                                  IconsaxPlusLinear.more,
                                  size: 18,
                                  color: GlimpseColors.textSubTitle,
                                ),
                              ),
                            ),
                        ],
                      ),
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
                            const SizedBox(width: 8),
                            Text(
                              item.taggedParticipants.length == 1
                                  ? AppLocalizations.of(context).translate('event_photo_one_participant_label')
                                  : AppLocalizations.of(context).translate('event_photo_participants_count_label').replaceAll('{count}', item.taggedParticipants.length.toString()),
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: GlimpseColors.textSubTitle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if ((item.caption ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        onLongPress: canDelete ? () => _showPostOptions(context) : null,
                        child: Text(
                          item.caption!.trim(),
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: GlimpseColors.primaryColorLight,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Imagens do post - slider horizontal se múltiplas
                    if (item.imageUrls.isNotEmpty)
                      EventPhotoImagesSlider(
                        imageUrls: item.imageUrls,
                        thumbnailUrls: item.thumbnailUrls,
                        // Height null para single image se adaptar.
                        // Para múltiplos, usa fallback do slider (220).
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
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  IconsaxPlusLinear.message_2,
                                  size: 20,
                                  color: GlimpseColors.textSubTitle,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${item.commentsCount}',
                                  style: GoogleFonts.getFont(
                                    FONT_PLUS_JAKARTA_SANS,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: GlimpseColors.textSubTitle,
                                  ),
                                ),
                              ],
                            ),
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
