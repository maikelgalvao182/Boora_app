import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_composer_controller.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_action_row.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_composer_header.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_event_selector_sheet.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_image_preview.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';
import 'package:partiu/shared/widgets/typing_indicator.dart';

class EventPhotoComposerScreen extends ConsumerStatefulWidget {
  const EventPhotoComposerScreen({super.key});

  @override
  ConsumerState<EventPhotoComposerScreen> createState() => _EventPhotoComposerScreenState();
}

class _EventPhotoComposerScreenState extends ConsumerState<EventPhotoComposerScreen> {
  final _focusNode = FocusNode();
  final _captionController = TextEditingController();
  bool _isFormattingCaption = false;

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
    _focusNode.dispose();
    _captionController.dispose();
    super.dispose();
  }

  String _ensureFirstLetterUppercase(String text) {
    if (text.isEmpty) return text;
    int index = -1;
    for (int i = 0; i < text.length; i++) {
      if (text[i].trim().isNotEmpty) {
        index = i;
        break;
      }
    }
    if (index < 0) return text;
    final char = text[index];
    final upper = char.toUpperCase();
    if (char == upper) return text;
    return text.substring(0, index) + upper + text.substring(index + 1);
  }

  void _handleCaptionChanged(String value, EventPhotoComposerController controller) {
    if (_isFormattingCaption) return;
    final formatted = _ensureFirstLetterUppercase(value);
    if (formatted != value) {
      _isFormattingCaption = true;
      final selection = _captionController.selection;
      _captionController.value = _captionController.value.copyWith(
        text: formatted,
        selection: selection,
        composing: TextRange.empty,
      );
      _isFormattingCaption = false;
    }
    controller.setCaption(formatted);
  }

  String _resolveErrorText(AppLocalizations i18n, String error) {
    final translated = i18n.translate(error);
    return translated.isNotEmpty ? translated : error;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final state = ref.watch(eventPhotoComposerControllerProvider);
    final controller = ref.read(eventPhotoComposerControllerProvider.notifier);

    final user = AppState.currentUser.value;

    final selectedEvent = state.selectedEvent;
    final topicText = selectedEvent == null
      ? i18n.translate('event_photo_add_event')
        : '${selectedEvent.emoji} ${selectedEvent.title}';

    final errorText = state.error == null ? null : _resolveErrorText(i18n, state.error!);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: GlimpseAppBar(
      title: i18n.translate('event_photo_new_post_title'),
        onBack: () => Navigator.of(context).pop(),
        actionWidget: TextButton(
            onPressed: state.isSubmitting
                ? null
                  : () async {
                    _focusNode.unfocus();
                    await controller.submit();
                    if (context.mounted && ref.read(eventPhotoComposerControllerProvider).error == null) {
                      Navigator.of(context).pop();
                    }
                  },
            style: TextButton.styleFrom(
              foregroundColor: GlimpseColors.primary,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ).copyWith(
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
            ),
            child: Container(
              padding: EdgeInsets.zero,
              child: state.isSubmitting
                  ? const TypingIndicator(color: GlimpseColors.primary, size: 6)
                  : Text(i18n.translate('event_photo_post_button')),
            ),
          ),
        ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EventPhotoComposerHeader(
                userId: user?.userId ?? '',
                userPhotoUrl: user?.photoUrl ?? '',
                topicText: topicText,
                taggedParticipants: state.taggedParticipants,
                onSelectEvent: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const EventPhotoEventSelectorSheet(),
                  );
                },
              ),
              TextField(
                focusNode: _focusNode,
                controller: _captionController,
                maxLines: null,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  letterSpacing: -0.3,
                  color: Colors.black,
                ),
                decoration: InputDecoration(
                  hintText: i18n.translate('event_photo_caption_hint'),
                  border: InputBorder.none,
                  hintStyle: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    letterSpacing: -0.3,
                    color: Colors.black38,
                  ),
                ),
                onChanged: (value) => _handleCaptionChanged(value, controller),
              ),
              const SizedBox(height: 12),
              if (state.images.isNotEmpty)
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: state.images.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: EdgeInsets.only(right: index < state.images.length - 1 ? 12 : 0),
                        child: EventPhotoImagePreview(
                          image: state.images[index],
                          onRemove: () async {
                            final confirmed = await GlimpseCupertinoDialog.showDestructive(
                              context: context,
                              title: i18n.translate('event_photo_remove_image_title'),
                              message: i18n.translate('event_photo_remove_image_message'),
                              destructiveText: i18n.translate('remove'),
                              cancelText: i18n.translate('cancel'),
                            );
                            if (confirmed == true) {
                              controller.removeImage(index);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 6),
              if (state.progress != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(
                    value: state.progress,
                    color: GlimpseColors.primary,
                    backgroundColor: GlimpseColors.primaryLight,
                  ),
                ),
              EventPhotoActionRow(
                onPickImage: controller.pickImage,
              ),
              if (state.error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(IconsaxPlusLinear.warning_2, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorText ?? '',
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
