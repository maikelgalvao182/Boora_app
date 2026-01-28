import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_comment_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_feed_controller.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/comment_header.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_comment_thread_sheet.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_header.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_more_menu_button.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

final eventPhotoCommentsProvider = FutureProvider.family<List<EventPhotoCommentModel>, String>((ref, photoId) async {
  final repo = ref.read(eventPhotoRepositoryProvider);
  return repo.fetchCommentsCached(photoId: photoId);
});

class EventPhotoCommentsSheet extends ConsumerStatefulWidget {
  const EventPhotoCommentsSheet({
    super.key,
    required this.photo,
  });

  final EventPhotoModel photo;

  @override
  ConsumerState<EventPhotoCommentsSheet> createState() => _EventPhotoCommentsSheetState();
}

class _EventPhotoCommentsSheetState extends ConsumerState<EventPhotoCommentsSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _focusInput() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final user = AppState.currentUser.value;
    if (user == null) return;

    final repo = ref.read(eventPhotoRepositoryProvider);
    await repo.addComment(
      photoId: widget.photo.id,
      comment: EventPhotoCommentModel(
        id: '',
        photoId: widget.photo.id,
        userId: user.userId,
        userName: user.fullName,
        userPhotoUrl: user.photoUrl,
        text: text,
        createdAt: null,
      ),
    );

    _controller.clear();
    ref.invalidate(eventPhotoCommentsProvider(widget.photo.id));
    // Invalidar o feed para atualizar o contador
    ref.invalidate(eventPhotoFeedControllerProvider);
    _focusInput();
  }

  Future<void> _openThread(EventPhotoCommentModel comment) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventPhotoCommentThreadSheet(
        photoId: widget.photo.id,
        comment: comment,
        eventEmoji: widget.photo.eventEmoji,
        eventTitle: widget.photo.eventTitle,
        eventCreatedAt: widget.photo.createdAt,
      ),
    );
  }

  Future<void> _deleteComment(EventPhotoCommentModel comment) async {
    final user = AppState.currentUser.value;
    if (user == null) return;
    if (comment.userId != user.userId) return;

    final repo = ref.read(eventPhotoRepositoryProvider);
    await repo.deleteComment(photoId: widget.photo.id, commentId: comment.id);
    ref.invalidate(eventPhotoCommentsProvider(widget.photo.id));
    // Invalidar o feed para atualizar o contador
    ref.invalidate(eventPhotoFeedControllerProvider);
  }

  String _resolveErrorText(AppLocalizations i18n, Object error) {
    final template = i18n.translate('event_photo_error_with_details');
    if (template.isEmpty) return error.toString();
    return template.replaceAll('{error}', error.toString());
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final asyncComments = ref.watch(eventPhotoCommentsProvider(widget.photo.id));

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: true,
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: GlimpseColors.borderColorLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            GlimpseAppBar(title: i18n.translate('event_photo_comments_title')),
            Expanded(
              child: asyncComments.when(
                data: (items) {
                  return CustomScrollView(
                    slivers: [
                      // Header com a foto e legenda do post
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: EventPhotoHeader(
                            userId: widget.photo.userId,
                            userPhotoUrl: widget.photo.userPhotoUrl,
                            eventEmoji: widget.photo.eventEmoji,
                            eventTitle: widget.photo.eventTitle,
                            createdAt: widget.photo.createdAt,
                            taggedParticipants: widget.photo.taggedParticipants,
                            caption: widget.photo.caption,
                            imageUrl: widget.photo.imageUrl,
                            thumbnailUrl: widget.photo.thumbnailUrl,
                            imageUrls: widget.photo.imageUrls,
                            thumbnailUrls: widget.photo.thumbnailUrls,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: Divider(height: 1, color: GlimpseColors.borderColorLight),
                      ),
                      // Lista de comentários
                      if (items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              i18n.translate('event_photo_comments_empty'),
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: GlimpseColors.textSubTitle,
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                if (i.isOdd) {
                                  return const SizedBox(height: 16);
                                }
                                final index = i ~/ 2;
                                final c = items[index];
                                return _CommentTile(
                                  comment: c,
                                  photoId: widget.photo.id,
                                  eventEmoji: widget.photo.eventEmoji,
                                  eventTitle: widget.photo.eventTitle,
                                  eventCreatedAt: widget.photo.createdAt,
                                  onFocusInput: _focusInput,
                                  onOpenThread: () => _openThread(c),
                                  onDelete: () => _deleteComment(c),
                                );
                              },
                              childCount: items.length * 2 - 1,
                            ),
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const Center(child: CupertinoActivityIndicator(radius: 14)),
                error: (e, _) => Center(child: Text(_resolveErrorText(i18n, e))),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        hintText: i18n.translate('event_photo_comment_hint'),
                        filled: true,
                        fillColor: GlimpseColors.lightTextField,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _send,
                    icon: const Icon(Iconsax.send_2, color: GlimpseColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({
    required this.comment,
    required this.photoId,
    required this.eventEmoji,
    required this.eventTitle,
    this.eventCreatedAt,
    required this.onFocusInput,
    required this.onOpenThread,
    required this.onDelete,
  });

  final EventPhotoCommentModel comment;
  final String photoId;
  final String eventEmoji;
  final String eventTitle;
  final Timestamp? eventCreatedAt;
  final VoidCallback onFocusInput;
  final VoidCallback onOpenThread;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = AppLocalizations.of(context);
    final asyncReplies = ref.watch(
      eventPhotoCommentRepliesProvider((photoId: photoId, commentId: comment.id)),
    );

    return InkWell(
      onTap: onFocusInput,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Comentário principal
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: GlimpseColors.lightTextField,
                backgroundImage: comment.userPhotoUrl.isEmpty ? null : NetworkImage(comment.userPhotoUrl),
                child: comment.userPhotoUrl.isEmpty
                    ? const Icon(Icons.person, size: 18, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: CommentHeader(
                            userId: comment.userId,
                            createdAt: comment.createdAt ?? eventCreatedAt,
                          ),
                        ),
                        if ((AppState.currentUser.value?.userId ?? '') == comment.userId)
                          EventPhotoMoreMenuButton(
                            title: i18n.translate('event_photo_delete_comment_title'),
                            message: i18n.translate('event_photo_delete_comment_message'),
                            destructiveText: i18n.translate('delete'),
                            onConfirmed: onDelete,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      comment.text,
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: GlimpseColors.primaryColorLight,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Botão responder com contador de replies
                    asyncReplies.when(
                      data: (replies) {
                        return TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                            onFocusInput();
                            onOpenThread();
                          },
                          child: Text(
                            replies.isEmpty
                              ? i18n.translate('event_photo_reply_action')
                              : (replies.length == 1
                                ? i18n
                                  .translate('event_photo_view_reply_singular')
                                  .replaceAll('{count}', replies.length.toString())
                                : i18n
                                  .translate('event_photo_view_reply_plural')
                                  .replaceAll('{count}', replies.length.toString())),
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: replies.isEmpty 
                                  ? GlimpseColors.textSubTitle 
                                  : GlimpseColors.primary,
                            ),
                          ),
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          onFocusInput();
                          onOpenThread();
                        },
                        child: Text(
                          i18n.translate('event_photo_reply_action'),
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: GlimpseColors.textSubTitle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Preview das replies (se houver)
          asyncReplies.when(
            data: (replies) {
              if (replies.isEmpty) return const SizedBox.shrink();
              
              // Mostrar até 2 replies como preview
              final previewReplies = replies.take(2).toList();
              
              return Padding(
                padding: const EdgeInsets.only(left: 42, top: 8),
                child: Column(
                  children: previewReplies.map((reply) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: GlimpseColors.lightTextField,
                            backgroundImage: reply.userPhotoUrl.isEmpty 
                                ? null 
                                : NetworkImage(reply.userPhotoUrl),
                            child: reply.userPhotoUrl.isEmpty
                                ? const Icon(Icons.person, size: 12, color: Colors.grey)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        reply.userName,
                                        style: GoogleFonts.getFont(
                                          FONT_PLUS_JAKARTA_SANS,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: GlimpseColors.primaryColorLight,
                                        ),
                                      ),
                                    ),
                                    if (reply.createdAt != null)
                                      Text(
                                        TimeAgoHelper.format(context, timestamp: reply.createdAt!.toDate()),
                                        style: GoogleFonts.getFont(
                                          FONT_PLUS_JAKARTA_SANS,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: GlimpseColors.textSubTitle,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  reply.text,
                                  style: GoogleFonts.getFont(
                                    FONT_PLUS_JAKARTA_SANS,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: GlimpseColors.primaryColorLight,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
