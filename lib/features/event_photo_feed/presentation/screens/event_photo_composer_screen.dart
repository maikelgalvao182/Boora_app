import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_composer_controller.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_action_row.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_composer_header.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_event_selector_sheet.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_image_preview.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';

class EventPhotoComposerScreen extends ConsumerWidget {
  const EventPhotoComposerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(eventPhotoComposerControllerProvider);
    final controller = ref.read(eventPhotoComposerControllerProvider.notifier);

    final user = AppState.currentUser.value;
  final username = user?.fullName ?? 'Você';

    final selectedEvent = state.selectedEvent;
    final topicText = selectedEvent == null
        ? 'Adicionar um tópico'
        : '${selectedEvent.emoji} ${selectedEvent.title}';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: GlimpseAppBar(
        title: 'Nova thread',
        onBack: () => Navigator.of(context).pop(),
        actionWidget: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextButton(
            onPressed: state.isSubmitting
                ? null
                : () async {
                    await controller.submit();
                    if (context.mounted && ref.read(eventPhotoComposerControllerProvider).error == null) {
                      Navigator.of(context).pop();
                    }
                  },
            style: TextButton.styleFrom(
              backgroundColor: GlimpseColors.primaryColorLight,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.black12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: state.isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Postar'),
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
                username: username,
                topicText: topicText,
                onSelectEvent: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const EventPhotoEventSelectorSheet(),
                  );
                },
              ),
              const SizedBox(height: 10),
              TextField(
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Quais são as novidades?',
                  border: InputBorder.none,
                  hintStyle: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black38,
                  ),
                ),
                onChanged: controller.setCaption,
              ),
              const SizedBox(height: 12),
              if (state.image != null)
                EventPhotoImagePreview(
                  image: state.image!,
                  onRemove: controller.removeImage,
                ),
              const SizedBox(height: 6),
              if (state.progress != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(value: state.progress),
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
                          state.error!,
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
