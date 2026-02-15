import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_composer_controller.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_participant_selector_sheet.dart';
import 'package:partiu/features/home/data/models/event_model.dart';

final recentEligibleEventsProvider = FutureProvider<List<EventModel>>((ref) async {
  print('🎯 [recentEligibleEventsProvider] Iniciando carregamento de eventos...');
  try {
    final events = await ref.read(recentEventsServiceProvider).fetchRecentEligibleEvents();
    print('✅ [recentEligibleEventsProvider] Eventos carregados: ${events.length}');
    return events;
  } catch (e, stack) {
    print('❌ [recentEligibleEventsProvider] ERRO ao carregar eventos: $e');
    print('📚 Stack trace: $stack');
    rethrow;
  }
});

class EventPhotoEventSelectorSheet extends ConsumerWidget {
  const EventPhotoEventSelectorSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = AppLocalizations.of(context);
    final asyncEvents = ref.watch(recentEligibleEventsProvider);

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
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: GlimpseColors.borderColorLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                i18n.translate('event_photo_select_event_title'),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
              const SizedBox(height: 12),
              asyncEvents.when(
                data: (events) {
                  final visibleEvents = events;
                  if (visibleEvents.isEmpty) {
                    return SizedBox(
                      height: 120,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            i18n.translate('event_photo_no_events_message'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: GlimpseColors.textSubTitle,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: visibleEvents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final e = visibleEvents[i];
                        return _EventListCardItem(
                          event: e,
                          onSelect: () {
                            ref.read(eventPhotoComposerControllerProvider.notifier).setSelectedEvent(e);
                            Navigator.of(context).pop();
                            showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => EventPhotoParticipantSelectorSheet(
                                eventId: e.id,
                                eventTitle: '${e.emoji} ${e.title}',
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CupertinoActivityIndicator(radius: 14)),
                ),
                error: (e, stack) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i18n.translate('event_photo_error_loading_events'),
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.red[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              i18n.translate('event_photo_error_details_label'),
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.red[900],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$e',
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: Colors.red[800],
                              ).merge(const TextStyle(fontFamily: 'monospace')),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              i18n.translate('event_photo_error_stack_trace_label'),
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.red[900],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$stack',
                              maxLines: 10,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                                color: Colors.red[700],
                              ).merge(const TextStyle(fontFamily: 'monospace')),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventListCardItem extends StatefulWidget {
  const _EventListCardItem({
    required this.event,
    required this.onSelect,
  });

  final EventModel event;
  final VoidCallback onSelect;

  @override
  State<_EventListCardItem> createState() => _EventListCardItemState();
}

class _EventListCardItemState extends State<_EventListCardItem> {
  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final eventDate = event.scheduleDate;
    final locationName = event.locationName?.trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: GlimpseColors.borderColorLight),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: GlimpseColors.lightTextField,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  event.emoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: GlimpseColors.primaryColorLight,
                      ),
                    ),
                    if (locationName != null && locationName.isNotEmpty)
                      Text(
                        locationName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: GlimpseColors.textSubTitle,
                        ),
                      ),
                    if (eventDate != null)
                      Text(
                        '${eventDate.day.toString().padLeft(2, '0')}/${eventDate.month.toString().padLeft(2, '0')} • ${eventDate.hour.toString().padLeft(2, '0')}:${eventDate.minute.toString().padLeft(2, '0')}',
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: GlimpseColors.textSubTitle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
