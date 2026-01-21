import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_composer_controller.dart';
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
                'Selecionar evento',
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
                  if (events.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Nenhum evento recente disponível',
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: GlimpseColors.textSubTitle,
                        ),
                      ),
                    );
                  }

                  return Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = events[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: GlimpseColors.lightTextField,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              e.emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                          title: Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: GlimpseColors.primaryColorLight,
                            ),
                          ),
                          subtitle: e.scheduleDate == null
                              ? null
                              : Text(
                                  '${e.scheduleDate}',
                                  style: GoogleFonts.getFont(
                                    FONT_PLUS_JAKARTA_SANS,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: GlimpseColors.textSubTitle,
                                  ),
                                ),
                          onTap: () {
                            ref.read(eventPhotoComposerControllerProvider.notifier).setSelectedEvent(e);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, stack) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Erro ao carregar eventos',
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
                              'Detalhes do erro:',
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
                            if (stack != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Stack trace:',
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
