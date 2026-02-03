import 'dart:async';

import 'package:el_tooltip/el_tooltip.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_feed_scope.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/event_photo_feed/data/models/unified_feed_item.dart';
import 'package:partiu/features/event_photo_feed/data/repositories/event_photo_repository.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_feed_controller.dart';
import 'package:partiu/features/event_photo_feed/presentation/screens/event_photo_composer_screen.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_comments_sheet.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_edit_caption_sheet.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_feed_shimmer.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_feed_item.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_feed_tabs.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/event_photo_feed_onboarding.dart';
import 'package:partiu/features/event_photo_feed/presentation/services/feed_onboarding_service.dart';
import 'package:partiu/features/feed/presentation/widgets/activity_feed_item.dart';
import 'package:partiu/features/home/presentation/coordinators/home_navigation_coordinator.dart';
import 'package:partiu/features/home/presentation/widgets/create_button.dart';
import 'package:partiu/shared/widgets/report_hint_wrapper.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/glimpse_tab_app_bar.dart';

/// Garante tempo mínimo de exibição do spinner (estilo Instagram)
Future<void> _delayedRefresh(Future<void> Function() refresh) async {
  final start = DateTime.now();
  await refresh();
  final elapsed = DateTime.now().difference(start);
  if (elapsed < const Duration(milliseconds: 800)) {
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));
}

/// Builder do Cupertino spinner com animação suave
Widget _cupertinoRefreshBuilder(
  BuildContext context,
  RefreshIndicatorMode mode,
  double pulledExtent,
  double triggerDistance,
  double indicatorExtent,
) {
  final percentage = (pulledExtent / triggerDistance).clamp(0.0, 1.0);
  final isRefreshing = mode == RefreshIndicatorMode.refresh ||
      mode == RefreshIndicatorMode.armed;
  final spinnerOpacity = isRefreshing ? 1.0 : percentage;
  final spinnerOffset = (1 - percentage) * 20;

  return SizedBox(
    height: pulledExtent,
    child: Center(
      child: Transform.translate(
        offset: Offset(0, spinnerOffset),
        child: Opacity(
          opacity: spinnerOpacity,
          child: const CupertinoActivityIndicator(radius: 14),
        ),
      ),
    ),
  );
}

class EventPhotoFeedScreen extends ConsumerStatefulWidget {
  const EventPhotoFeedScreen({
    super.key,
    this.scope = const EventPhotoFeedScopeGlobal(),
    this.isMainTab = false,
  });

  final EventPhotoFeedScope scope;
  final bool isMainTab;

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

  void _showEditCaptionSheet(EventPhotoModel photo, EventPhotoFeedScope scope) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventPhotoEditCaptionSheet(
        photo: photo,
        onSave: (newCaption) async {
          // Atualiza no Firestore
          final repo = ref.read(eventPhotoRepositoryProvider);
          await repo.updateCaption(photoId: photo.id, caption: newCaption);
          
          // Atualiza estado local imediatamente (sem precisar de network fetch)
          ref.read(eventPhotoFeedControllerProvider(scope).notifier).optimisticUpdateCaption(
            photoId: photo.id,
            caption: newCaption,
          );
        },
      ),
    );
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
      floatingActionButton: AutoShowTooltip(
        message: i18n.translate('feed_post_photos_hint'),
        position: ElTooltipPosition.topEnd,
        color: GlimpseColors.primary,
        duration: const Duration(seconds: 3),
        child: CreateButton(
          onPressed: () => _handleCreateTap(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlimpseTabAppBar(
              title: i18n.translate('event_photo_feed_title'),
            ),
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
                final unifiedItems = state.unifiedItems;
                if (unifiedItems.isEmpty) {
                  // Empty state com Cupertino pull-to-refresh
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return CustomScrollView(
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        slivers: [
                          CupertinoSliverRefreshControl(
                            onRefresh: () => _delayedRefresh(
                              () => ref.read(eventPhotoFeedControllerProvider(scope).notifier).refresh(),
                            ),
                            refreshTriggerPullDistance: 120,
                            refreshIndicatorExtent: 80,
                            builder: _cupertinoRefreshBuilder,
                          ),
                          SliverFillRemaining(
                            hasScrollBody: false,
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
                        ],
                      );
                    },
                  );
                }

                // Lista de feed com Cupertino pull-to-refresh
                return NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                      ref.read(eventPhotoFeedControllerProvider(scope).notifier).loadMore();
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      CupertinoSliverRefreshControl(
                        onRefresh: () => _delayedRefresh(
                          () => ref.read(eventPhotoFeedControllerProvider(scope).notifier).refresh(),
                        ),
                        refreshTriggerPullDistance: 120,
                        refreshIndicatorExtent: 80,
                        builder: _cupertinoRefreshBuilder,
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            if (i >= unifiedItems.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CupertinoActivityIndicator(radius: 14)),
                              );
                            }

                            final unifiedItem = unifiedItems[i];
                            
                            // Renderiza ActivityFeedItem ou EventPhotoFeedItem
                            if (unifiedItem.type == UnifiedFeedItemType.activity) {
                              return Column(
                                children: [
                                  ActivityFeedItem(
                                    item: unifiedItem.activity!,
                                    onTap: () {
                                      // Navega para o evento no mapa (tab Descobrir) e abre o card
                                      // Usa addPostFrameCallback para garantir que a UI está estável
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        HomeNavigationCoordinator.instance.openEventOnMap(
                                          unifiedItem.eventId,
                                        );
                                      });
                                    },
                                  ),
                                  const Divider(height: 1, color: GlimpseColors.borderColorLight),
                                ],
                              );
                            }
                            
                            // EventPhotoFeedItem
                            final item = unifiedItem.photo!;
                            return Column(
                              children: [
                                EventPhotoFeedItem(
                                  item: item,
                                  onDelete: () async {
                                    // Optimistic UI: remove imediatamente da lista
                                    ref.read(eventPhotoFeedControllerProvider(scope).notifier)
                                        .optimisticRemovePhoto(photoId: item.id);
                                    
                                    // Depois deleta no servidor
                                    final repo = ref.read(eventPhotoRepositoryProvider);
                                    await repo.deletePhoto(photoId: item.id);
                                  },
                                  onEditCaption: () async {
                                    _showEditCaptionSheet(item, scope);
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
                          childCount: unifiedItems.length + (state.isLoadingMore ? 1 : 0),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const EventPhotoFeedShimmerList(),
              // Error state com Cupertino pull-to-refresh
              error: (e, stack) => CustomScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  CupertinoSliverRefreshControl(
                    onRefresh: () => _delayedRefresh(
                      () => ref.read(eventPhotoFeedControllerProvider(scope).notifier).refresh(),
                    ),
                    refreshTriggerPullDistance: 120,
                    refreshIndicatorExtent: 80,
                    builder: _cupertinoRefreshBuilder,
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(20),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
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
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ],
        ),
      ),
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
