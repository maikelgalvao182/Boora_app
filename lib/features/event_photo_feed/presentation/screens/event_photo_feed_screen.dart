import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/event_photo_feed/data/repositories/event_photo_repository.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_feed_controller.dart';
import 'package:partiu/features/event_photo_feed/presentation/screens/event_photo_composer_screen.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_comments_sheet.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_feed_item.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';

class EventPhotoFeedScreen extends ConsumerWidget {
  const EventPhotoFeedScreen({
    super.key,
    this.scope = const EventPhotoFeedScopeGlobal(),
  });

  final EventPhotoFeedScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(eventPhotoFeedControllerProvider(scope));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: GlimpseAppBar(
        title: 'Feed',
        isBackEnabled: true,
        actionWidget: IconButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EventPhotoComposerScreen()),
            );
          },
          icon: const Icon(IconsaxPlusLinear.edit_2, color: GlimpseColors.textSubTitle),
        ),
      ),
      body: asyncState.when(
        data: (state) {
          if (state.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.read(eventPhotoFeedControllerProvider(scope).notifier).refresh(),
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Seja o primeiro a postar')),
                ],
              ),
            );
          }

          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                ref.read(eventPhotoFeedControllerProvider(scope).notifier).loadMore();
              }
              return false;
            },
            child: RefreshIndicator(
              onRefresh: () => ref.read(eventPhotoFeedControllerProvider(scope).notifier).refresh(),
              child: ListView.builder(
                itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= state.items.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final item = state.items[i];
                  return Column(
                    children: [
                      EventPhotoFeedItem(
                        item: item,
                                      onDelete: () async {
                                        final repo = ref.read(eventPhotoRepositoryProvider);
                                        await repo.deletePhoto(photoId: item.id);
                                        await ref.read(eventPhotoFeedControllerProvider(scope).notifier).refresh();
                                      },
                        onCommentsTap: () {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => EventPhotoCommentsSheet(photoId: item.id),
                          );
                        },
                      ),
                      const Divider(height: 1, color: GlimpseColors.borderColorLight),
                    ],
                  );
                },
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, stack) => RefreshIndicator(
          onRefresh: () => ref.read(eventPhotoFeedControllerProvider(scope).notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 40),
              Icon(
                IconsaxPlusLinear.warning_2,
                size: 64,
                color: Colors.red[400],
              ),
              const SizedBox(height: 20),
              Text(
                'Erro ao carregar feed',
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detalhes do erro:',
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.red[900],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$e',
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.red[800],
                      ).merge(const TextStyle(fontFamily: 'monospace')),
                    ),
                    if (stack != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Stack trace (primeiras linhas):',
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.red[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$stack',
                        maxLines: 15,
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
              const SizedBox(height: 24),
              Text(
                'Arraste para baixo para tentar novamente',
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: GlimpseColors.textSubTitle,
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: GlimpseColors.primary,
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EventPhotoComposerScreen()),
          );
        },
        child: const Icon(IconsaxPlusLinear.add, color: Colors.white),
      ),
    );
  }
}
