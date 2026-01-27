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
import 'package:partiu/features/event_photo_feed/data/models/event_photo_comment_reply_model.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_feed_controller.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/comment_header.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_comments_sheet.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_more_menu_button.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

final eventPhotoCommentRepliesProvider = FutureProvider.family<List<EventPhotoCommentReplyModel>, ({String photoId, String commentId})>(
  (ref, args) async {
    final repo = ref.read(eventPhotoRepositoryProvider);
    return repo.fetchCommentRepliesCached(photoId: args.photoId, commentId: args.commentId);
  },
);

class EventPhotoCommentThreadSheet extends ConsumerStatefulWidget {
  const EventPhotoCommentThreadSheet({
    super.key,
    required this.photoId,
    required this.comment,
    required this.eventEmoji,
    required this.eventTitle,
    this.eventCreatedAt,
  });

  final String photoId;
  final EventPhotoCommentModel comment;
  final String eventEmoji;
  final String eventTitle;
  final Timestamp? eventCreatedAt;

  @override
  ConsumerState<EventPhotoCommentThreadSheet> createState() => _EventPhotoCommentThreadSheetState();
}

class _EventPhotoCommentThreadSheetState extends ConsumerState<EventPhotoCommentThreadSheet> {
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

  Future<void> _sendReply() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final user = AppState.currentUser.value;
    if (user == null) return;

    final repo = ref.read(eventPhotoRepositoryProvider);
    try {
      await repo.addCommentReply(
        photoId: widget.photoId,
        commentId: widget.comment.id,
        reply: EventPhotoCommentReplyModel(
          id: '',
          photoId: widget.photoId,
          commentId: widget.comment.id,
          userId: user.userId,
          userName: user.fullName,
          userPhotoUrl: user.photoUrl,
          text: text,
          createdAt: null,
        ),
      );
    } catch (e, stack) {
      debugPrint('❌ [EventPhotoReply] Erro ao criar reply: $e');
      debugPrint('❌ [EventPhotoReply] Stack: $stack');
      rethrow;
    }

    _controller.clear();
    ref.invalidate(
      eventPhotoCommentRepliesProvider((photoId: widget.photoId, commentId: widget.comment.id)),
    );
    // Invalidar comentários para atualizar preview de replies
    ref.invalidate(eventPhotoCommentsProvider(widget.photoId));
    // Invalidar o feed para atualizar o contador
    ref.invalidate(eventPhotoFeedControllerProvider);
  }

  Future<void> _deleteReply(EventPhotoCommentReplyModel reply) async {
    final user = AppState.currentUser.value;
    if (user == null) return;
    if (reply.userId != user.userId) return;

    final repo = ref.read(eventPhotoRepositoryProvider);
    await repo.deleteCommentReply(
      photoId: widget.photoId,
      commentId: widget.comment.id,
      replyId: reply.id,
    );

    ref.invalidate(
      eventPhotoCommentRepliesProvider((photoId: widget.photoId, commentId: widget.comment.id)),
    );
    // Invalidar comentários para atualizar preview de replies
    ref.invalidate(eventPhotoCommentsProvider(widget.photoId));
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
    final asyncReplies = ref.watch(
      eventPhotoCommentRepliesProvider((photoId: widget.photoId, commentId: widget.comment.id)),
    );

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
            GlimpseAppBar(title: i18n.translate('event_photo_replies_title')),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: InkWell(
                onTap: _focusInput,
                child: _ThreadRootComment(
                  comment: widget.comment,
                  eventEmoji: widget.eventEmoji,
                  eventTitle: widget.eventTitle,
                  eventCreatedAt: widget.eventCreatedAt,
                ),
              ),
            ),
            const Divider(height: 1, color: GlimpseColors.borderColorLight),
            Expanded(
              child: asyncReplies.when(
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        i18n.translate('event_photo_replies_empty'),
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: GlimpseColors.textSubTitle,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final r = items[i];
                      return _ReplyTile(
                        reply: r,
                        eventEmoji: widget.eventEmoji,
                        eventTitle: widget.eventTitle,
                        eventCreatedAt: widget.eventCreatedAt,
                        canDelete: (AppState.currentUser.value?.userId ?? '') == r.userId,
                        onDelete: () => _deleteReply(r),
                      );
                    },
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
                top: 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        hintText: i18n.translate('event_photo_reply_hint'),
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
                    onPressed: _sendReply,
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

class _ThreadRootComment extends StatelessWidget {
  const _ThreadRootComment({
    required this.comment,
    required this.eventEmoji,
    required this.eventTitle,
    this.eventCreatedAt,
  });

  final EventPhotoCommentModel comment;
  final String eventEmoji;
  final String eventTitle;
  final Timestamp? eventCreatedAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: GlimpseColors.lightTextField,
          backgroundImage: comment.userPhotoUrl.isEmpty ? null : NetworkImage(comment.userPhotoUrl),
          child: comment.userPhotoUrl.isEmpty ? const Icon(Icons.person, size: 16, color: Colors.grey) : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CommentHeader(
                userId: comment.userId,
                createdAt: comment.createdAt ?? eventCreatedAt,
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
            ],
          ),
        ),
      ],
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({
    required this.reply,
    required this.eventEmoji,
    required this.eventTitle,
    this.eventCreatedAt,
    required this.canDelete,
    required this.onDelete,
  });

  final EventPhotoCommentReplyModel reply;
  final String eventEmoji;
  final String eventTitle;
  final Timestamp? eventCreatedAt;
  final bool canDelete;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: GlimpseColors.lightTextField,
            backgroundImage: reply.userPhotoUrl.isEmpty ? null : NetworkImage(reply.userPhotoUrl),
            child: reply.userPhotoUrl.isEmpty ? const Icon(Icons.person, size: 14, color: Colors.grey) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: CommentHeader(
                        userId: reply.userId,
                        createdAt: reply.createdAt ?? eventCreatedAt,
                      ),
                    ),
                    if (canDelete)
                      EventPhotoMoreMenuButton(
                        title: i18n.translate('event_photo_delete_reply_title'),
                        message: i18n.translate('event_photo_delete_reply_message'),
                        destructiveText: i18n.translate('delete'),
                        onConfirmed: onDelete,
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
