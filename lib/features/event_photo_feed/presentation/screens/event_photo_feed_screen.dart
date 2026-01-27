import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_feed_scope.dart';
import 'package:partiu/features/event_photo_feed/data/repositories/event_photo_repository.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_feed_controller.dart';
import 'package:partiu/features/event_photo_feed/presentation/screens/event_photo_composer_screen.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_comments_sheet.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_feed_item.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_feed_tabs.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_feed_onboarding.dart';
import 'package:partiu/features/event_photo_feed/presentation/services/feed_onboarding_service.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';

class EventPhotoFeedScreen extends ConsumerStatefulWidget {
  const EventPhotoFeedScreen({
    super.key,
    this.scope = const EventPhotoFeedScopeGlobal(),
  });

  final EventPhotoFeedScope scope;

  @override
  ConsumerState<EventPhotoFeedScreen> createState() => _EventPhotoFeedScreenState();
}

class _EventPhotoFeedScreenState extends ConsumerState<EventPhotoFeedScreen> {
  int _tabIndex = 0;
  EventPhotoFeedScope _scope = const EventPhotoFeedScopeGlobal();
  String _scopeUserId = '';

  void _updateScope({int? tabIndex, String? userId}) {
    final nextTab = tabIndex ?? _tabIndex;
    final nextUserId = userId ?? _scopeUserId;

    switch (nextTab) {
      case 1:
        _scope = EventPhotoFeedScopeFollowing(userId: nextUserId);
        break;
      case 2:
        _scope = EventPhotoFeedScopeUser(userId: nextUserId);
        break;
      default:
        _scope = const EventPhotoFeedScopeGlobal();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final userId = AppState.currentUser.value?.userId ?? '';
    if (userId != _scopeUserId) {
      _scopeUserId = userId;
      _updateScope(userId: userId);
    }

    final scope = _scope;
    final asyncState = ref.watch(eventPhotoFeedControllerProvider(scope));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: GlimpseAppBar(
        title: i18n.translate('event_photo_feed_title'),
        isBackEnabled: true,
        actionWidget: Container(
          padding: EdgeInsets.zero,
          child: TextButton.icon(
            onPressed: () {
              _handleCreateTap(context);
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ).copyWith(
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
            ),
            icon: const Icon(
              Icons.add,
              color: GlimpseColors.primary,
              size: 18,
            ),
            label: Text(
              i18n.translate('event_photo_create_button'),
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: GlimpseColors.primary,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          EventPhotoFeedTabs(
            currentIndex: _tabIndex,
            onChanged: (index) {
              if (_tabIndex == index) return;
              setState(() {
                _tabIndex = index;
                _updateScope(tabIndex: index, userId: _scopeUserId);
              });
            },
          ),
          Expanded(
            child: asyncState.when(
              data: (state) {
                if (state.items.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () => ref.read(eventPhotoFeedControllerProvider(scope).notifier).refresh(),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight),
                            child: Center(
                              child: GlimpseEmptyState.standard(
                                text: _tabIndex == 1
                                    ? i18n.translate('event_photo_empty_following')
                                    : _tabIndex == 2
                                        ? i18n.translate('event_photo_empty_mine')
                                        : i18n.translate('event_photo_empty_global'),
                              ),
                            ),
                          ),
                        );
                      },
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
                            child: Center(child: CupertinoActivityIndicator(radius: 14)),
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
                              onDeleteImage: (index) async {
                                final repo = ref.read(eventPhotoRepositoryProvider);
                                final controller = ref.read(
                                  eventPhotoFeedControllerProvider(scope).notifier,
                                );
                                controller.optimisticRemoveImage(
                                  photoId: item.id,
                                  index: index,
                                );
                                try {
                                  await repo.removePhotoImage(
                                    photoId: item.id,
                                    index: index,
                                    imageUrls: item.imageUrls,
                                    thumbnailUrls: item.thumbnailUrls,
                                  );
                                } catch (_) {
                                  await controller.refresh();
                                }
                              },
                              onCommentsTap: () {
                                showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => EventPhotoCommentsSheet(photo: item),
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
              loading: () => const Center(child: CupertinoActivityIndicator(radius: 14)),
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
                      i18n.translate('event_photo_error_loading_feed'),
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
                            i18n.translate('event_photo_error_details_label'),
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
                              i18n.translate('event_photo_error_stack_trace_label'),
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
                      i18n.translate('event_photo_pull_to_refresh'),
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
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  Future<void> _handleCreateTap(BuildContext context) async {
    final shouldShow = await FeedOnboardingService.instance.shouldShow();
    if (shouldShow && context.mounted) {
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => EventPhotoFeedOnboarding(
            onComplete: () => Navigator.of(context).pop(true),
          ),
        ),
      );

      if (completed == true && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EventPhotoComposerScreen()),
        );
      }
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EventPhotoComposerScreen()),
    );
  }
}
