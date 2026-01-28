import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_feed_controller.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_header.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';

class EventPhotoEditCaptionSheet extends ConsumerStatefulWidget {
  const EventPhotoEditCaptionSheet({
    super.key,
    required this.photo,
    required this.onSave,
  });

  final EventPhotoModel photo;
  final Future<void> Function(String newCaption) onSave;

  @override
  ConsumerState<EventPhotoEditCaptionSheet> createState() => _EventPhotoEditCaptionSheetState();
}

class _EventPhotoEditCaptionSheetState extends ConsumerState<EventPhotoEditCaptionSheet> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.photo.caption ?? '');
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

  Future<void> _save() async {
    if (_isSaving) return;
    
    final newCaption = _controller.text.trim();
    
    setState(() => _isSaving = true);
    
    try {
      await widget.onSave(newCaption);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('❌ [EventPhotoEditCaptionSheet] Erro ao salvar: $e');
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

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
            GlimpseAppBar(title: i18n.translate('event_photo_edit_caption_title')),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Preview do post (sem imagens)
                    EventPhotoHeader(
                      userId: widget.photo.userId,
                      userPhotoUrl: widget.photo.userPhotoUrl,
                      eventEmoji: widget.photo.eventEmoji,
                      eventTitle: widget.photo.eventTitle,
                      createdAt: widget.photo.createdAt,
                      taggedParticipants: widget.photo.taggedParticipants,
                      caption: null, // Não mostra caption aqui, vai no campo de edição
                      imageUrl: widget.photo.imageUrl,
                      thumbnailUrl: widget.photo.thumbnailUrl,
                      imageUrls: widget.photo.imageUrls,
                      thumbnailUrls: widget.photo.thumbnailUrls,
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: GlimpseColors.borderColorLight),
                    const SizedBox(height: 12),
                    // Campo de texto
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: i18n.translate('event_photo_caption_placeholder'),
                          hintStyle: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: GlimpseColors.textSubTitle,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.only(bottom: 16),
                        ),
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: GlimpseColors.primaryColorLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Botão salvar
            Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: GlimpseButton(
                text: i18n.translate('save'),
                onPressed: _save,
                isProcessing: _isSaving,
                height: 48,
                noPadding: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
