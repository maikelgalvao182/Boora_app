import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_comment_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_comment_reply_model.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_feed_controller.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_more_menu_button.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';

final eventPhotoCommentRepliesProvider = FutureProvider.family<List<EventPhotoCommentReplyModel>, ({String photoId, String commentId})>(
  (ref, args) async {
    final repo = ref.read(eventPhotoRepositoryProvider);
    return repo.fetchCommentReplies(photoId: args.photoId, commentId: args.commentId);
  },
);

class EventPhotoCommentThreadSheet extends ConsumerStatefulWidget {
  const EventPhotoCommentThreadSheet({
    super.key,
    required this.photoId,
    required this.comment,
  });

  final String photoId;
  final EventPhotoCommentModel comment;

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

    _controller.clear();
    ref.invalidate(
      eventPhotoCommentRepliesProvider((photoId: widget.photoId, commentId: widget.comment.id)),
    );
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
  }

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: GlimpseColors.borderColorLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            const GlimpseAppBar(title: 'Respostas'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: InkWell(
                onTap: _focusInput,
                child: _ThreadRootComment(comment: widget.comment),
              ),
            ),
            const Divider(height: 1, color: GlimpseColors.borderColorLight),
            Expanded(
              child: asyncReplies.when(
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        'Seja o primeiro a responder',
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
                        canDelete: (AppState.currentUser.value?.userId ?? '') == r.userId,
                        onDelete: () => _deleteReply(r),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erro: $e')),
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
                        hintText: 'Responder…',
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
  const _ThreadRootComment({required this.comment});

  final EventPhotoCommentModel comment;

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
              Text(
                comment.userName,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
              const SizedBox(height: 2),
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
    required this.canDelete,
    required this.onDelete,
  });

  final EventPhotoCommentReplyModel reply;
  final bool canDelete;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
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
                    child: Text(
                      reply.userName,
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: GlimpseColors.primaryColorLight,
                      ),
                    ),
                  ),
                  if (canDelete)
                    EventPhotoMoreMenuButton(
                      title: 'Excluir resposta',
                      message: 'Tem certeza que deseja excluir esta resposta?',
                      destructiveText: 'excluir',
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
    );
  }
}
