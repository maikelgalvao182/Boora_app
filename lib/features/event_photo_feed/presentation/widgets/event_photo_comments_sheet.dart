import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_comment_model.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_feed_controller.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_comment_thread_sheet.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_more_menu_button.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';

final eventPhotoCommentsProvider = FutureProvider.family<List<EventPhotoCommentModel>, String>((ref, photoId) async {
  final repo = ref.read(eventPhotoRepositoryProvider);
  return repo.fetchComments(photoId: photoId);
});

class EventPhotoCommentsSheet extends ConsumerStatefulWidget {
  const EventPhotoCommentsSheet({
    super.key,
    required this.photoId,
  });

  final String photoId;

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
      photoId: widget.photoId,
      comment: EventPhotoCommentModel(
        id: '',
        photoId: widget.photoId,
        userId: user.userId,
        userName: user.fullName,
        userPhotoUrl: user.photoUrl,
        text: text,
        createdAt: null,
      ),
    );

    _controller.clear();
    ref.invalidate(eventPhotoCommentsProvider(widget.photoId));
    _focusInput();
  }

  Future<void> _openThread(EventPhotoCommentModel comment) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventPhotoCommentThreadSheet(
        photoId: widget.photoId,
        comment: comment,
      ),
    );
  }

  Future<void> _deleteComment(EventPhotoCommentModel comment) async {
    final user = AppState.currentUser.value;
    if (user == null) return;
    if (comment.userId != user.userId) return;

    final repo = ref.read(eventPhotoRepositoryProvider);
    await repo.deleteComment(photoId: widget.photoId, commentId: comment.id);
    ref.invalidate(eventPhotoCommentsProvider(widget.photoId));
  }

  @override
  Widget build(BuildContext context) {
    final asyncComments = ref.watch(eventPhotoCommentsProvider(widget.photoId));

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
            const GlimpseAppBar(title: 'Comentários'),
            Expanded(
              child: asyncComments.when(
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        'Seja o primeiro a comentar',
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = items[i];

                      return InkWell(
                        onTap: _focusInput,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: GlimpseColors.lightTextField,
                              backgroundImage: c.userPhotoUrl.isEmpty ? null : NetworkImage(c.userPhotoUrl),
                              child: c.userPhotoUrl.isEmpty
                                  ? const Icon(Icons.person, size: 16, color: Colors.grey)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.userName,
                                          style: GoogleFonts.getFont(
                                            FONT_PLUS_JAKARTA_SANS,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: GlimpseColors.primaryColorLight,
                                          ),
                                        ),
                                      ),
                                      if ((AppState.currentUser.value?.userId ?? '') == c.userId)
                                        EventPhotoMoreMenuButton(
                                          title: 'Excluir comentário',
                                          message: 'Tem certeza que deseja excluir este comentário?',
                                          destructiveText: 'excluir',
                                          onConfirmed: () => _deleteComment(c),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    c.text,
                                    style: GoogleFonts.getFont(
                                      FONT_PLUS_JAKARTA_SANS,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: GlimpseColors.primaryColorLight,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 0),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () {
                                        _focusInput();
                                        _openThread(c);
                                      },
                                      child: Text(
                                        'Responder',
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
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        hintText: 'Adicionar um comentário...',
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
