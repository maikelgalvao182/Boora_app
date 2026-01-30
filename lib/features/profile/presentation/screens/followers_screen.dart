import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/glimpse_segmented_tabs.dart';
import 'package:partiu/shared/widgets/pull_to_refresh.dart';
import 'package:partiu/features/profile/presentation/controllers/follow_controller.dart';
import 'package:partiu/features/profile/presentation/screens/profile_screen_router.dart';
import 'package:partiu/features/profile/presentation/controllers/followers_controller.dart';
import 'package:partiu/features/profile/presentation/controllers/followers_controller_cache.dart';
import 'package:partiu/features/home/presentation/widgets/user_card.dart';
import 'package:partiu/features/home/presentation/widgets/user_card_shimmer.dart';
import 'package:partiu/common/state/app_state.dart';

class FollowersScreen extends StatefulWidget {
  const FollowersScreen({super.key});

  @override
  State<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends State<FollowersScreen> {
  FollowersController? _controller;
  late final ScrollController _followersScrollController;
  late final ScrollController _followingScrollController;
  String? _userId;
  int _tabIndex = 0;

  String _tr(AppLocalizations i18n, String key, String fallback) {
    final value = i18n.translate(key);
    return value.isNotEmpty ? value : fallback;
  }

  @override
  void initState() {
    super.initState();
    _followersScrollController = ScrollController();
    _followingScrollController = ScrollController();

    _userId = AppState.currentUserId;
    if (_userId != null && _userId!.isNotEmpty) {
      // ✅ OTIMIZADO: Usa cache em vez de criar novo controller
      _initController();
    }
  }

  /// Inicializa o controller de forma async
  Future<void> _initController() async {
    final controller = await FollowersControllerCache.instance.getOrCreate(_userId!);
    if (mounted) {
      setState(() {
        _controller = controller;
      });
    }
  }

  @override
  void dispose() {
    _followersScrollController.dispose();
    _followingScrollController.dispose();
    // ✅ OTIMIZADO: NÃO descarta o controller - mantém em cache
    // O cache gerencia o TTL e limpeza automática
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final userId = _userId;

    if (userId == null || userId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: GlimpseBackButton.iconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => Navigator.of(context).pop(),
            color: GlimpseColors.primaryColorLight,
          ),
          title: Text(
            _tr(i18n, 'followers', 'Seguidores'),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: GlimpseColors.primaryColorLight,
            ),
          ),
        ),
        body: Center(
          child: Text(
            _tr(i18n, 'user_not_authenticated', 'Usuário não autenticado'),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 14,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: GlimpseBackButton.iconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () => Navigator.of(context).pop(),
          color: GlimpseColors.primaryColorLight,
        ),
        title: Text(
          _tr(i18n, 'followers', 'Seguidores'),
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: GlimpseColors.primaryColorLight,
          ),
        ),
      ),
      body: Column(
        children: [
          GlimpseSegmentedTabs(
            labels: [
              _tr(i18n, 'followers', 'Seguidores'),
              _tr(i18n, 'following', 'Seguindo'),
            ],
            currentIndex: _tabIndex,
            onChanged: (index) {
              if (_tabIndex == index) return;
              setState(() {
                _tabIndex = index;
              });
            },
          ),
          Expanded(
            child: _controller == null
                ? const Center(child: CircularProgressIndicator())
                : IndexedStack(
              index: _tabIndex,
              children: [
                _FollowersListTab(
                  controller: _controller!,
                  currentUserId: userId,
                  scrollController: _followersScrollController,
                ),
                _FollowingListTab(
                  controller: _controller!,
                  currentUserId: userId,
                  scrollController: _followingScrollController,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowersListTab extends StatefulWidget {
  const _FollowersListTab({
    required this.controller,
    required this.currentUserId,
    required this.scrollController,
  });

  final FollowersController controller;
  final String currentUserId;
  final ScrollController scrollController;

  @override
  State<_FollowersListTab> createState() => _FollowersListTabState();
}

class _FollowersListTabState extends State<_FollowersListTab> {
  String _tr(AppLocalizations i18n, String key, String fallback) {
    final value = i18n.translate(key);
    return value.isNotEmpty ? value : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return ValueListenableBuilder<List<User>>(
      valueListenable: widget.controller.followers,
      builder: (context, users, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: widget.controller.isLoadingFollowers,
          builder: (context, isLoading, __) {
            if (isLoading && users.isEmpty) {
              return ListView.separated(
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                itemCount: 6,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) => const UserCardShimmer(),
              );
            }

            return ValueListenableBuilder<Object?>(
              valueListenable: widget.controller.followersError,
              builder: (context, error, ___) {
                if (error != null && users.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _tr(i18n, 'error_try_again', 'Erro, tente novamente'),
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 16,
                            color: GlimpseColors.textSubTitle,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: widget.controller.refreshFollowers,
                          child: Text(
                            _tr(i18n, 'try_again', 'Tentar novamente'),
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: GlimpseColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (users.isEmpty) {
                  return Center(
                    child: GlimpseEmptyState.standard(
                      text: _tr(i18n, 'no_followers', 'Nenhum seguidor ainda'),
                    ),
                  );
                }

                // ✅ OTIMIZADO: Infinite scroll com hasMore e isLoadingMore
                return ValueListenableBuilder<bool>(
                  valueListenable: widget.controller.hasMoreFollowers,
                  builder: (context, hasMore, ____) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: widget.controller.isLoadingMoreFollowers,
                      builder: (context, isLoadingMore, _____) {
                        return PlatformPullToRefresh(
                          onRefresh: widget.controller.refreshFollowers,
                          controller: widget.scrollController,
                          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                          itemCount: users.length,
                          onLoadMore: widget.controller.loadMoreFollowers,
                          hasMore: hasMore,
                          isLoadingMore: isLoadingMore,
                          itemBuilder: (context, index) {
                            final user = users[index].copyWith(distance: null);
                            return UserCard(
                              key: ValueKey(user.userId),
                              userId: user.userId,
                              user: user,
                              showRating: false,
                              trailingWidget: _FollowActionButton(
                                currentUserId: widget.currentUserId,
                                targetUserId: user.userId,
                              ),
                              onTap: () {
                                ProfileScreenRouter.navigateByUserId(
                                  context,
                                  userId: user.userId,
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FollowingListTab extends StatefulWidget {
  const _FollowingListTab({
    required this.controller,
    required this.currentUserId,
    required this.scrollController,
  });

  final FollowersController controller;
  final String currentUserId;
  final ScrollController scrollController;

  @override
  State<_FollowingListTab> createState() => _FollowingListTabState();
}

class _FollowingListTabState extends State<_FollowingListTab> {
  String _tr(AppLocalizations i18n, String key, String fallback) {
    final value = i18n.translate(key);
    return value.isNotEmpty ? value : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return ValueListenableBuilder<List<User>>(
      valueListenable: widget.controller.following,
      builder: (context, users, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: widget.controller.isLoadingFollowing,
          builder: (context, isLoading, __) {
            if (isLoading && users.isEmpty) {
              return ListView.separated(
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                itemCount: 6,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) => const UserCardShimmer(),
              );
            }

            return ValueListenableBuilder<Object?>(
              valueListenable: widget.controller.followingError,
              builder: (context, error, ___) {
                if (error != null && users.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _tr(i18n, 'error_try_again', 'Erro, tente novamente'),
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 16,
                            color: GlimpseColors.textSubTitle,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: widget.controller.refreshFollowing,
                          child: Text(
                            _tr(i18n, 'try_again', 'Tentar novamente'),
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: GlimpseColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (users.isEmpty) {
                  return Center(
                    child: GlimpseEmptyState.standard(
                      text: _tr(i18n, 'no_following', 'Nenhuma pessoa seguida'),
                    ),
                  );
                }

                // ✅ OTIMIZADO: Infinite scroll com hasMore e isLoadingMore
                return ValueListenableBuilder<bool>(
                  valueListenable: widget.controller.hasMoreFollowing,
                  builder: (context, hasMore, ____) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: widget.controller.isLoadingMoreFollowing,
                      builder: (context, isLoadingMore, _____) {
                        return PlatformPullToRefresh(
                          onRefresh: widget.controller.refreshFollowing,
                          controller: widget.scrollController,
                          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                          itemCount: users.length,
                          onLoadMore: widget.controller.loadMoreFollowing,
                          hasMore: hasMore,
                          isLoadingMore: isLoadingMore,
                          itemBuilder: (context, index) {
                            final user = users[index].copyWith(distance: null);
                            return UserCard(
                              key: ValueKey(user.userId),
                              userId: user.userId,
                              user: user,
                              showRating: false,
                              trailingWidget: _FollowActionButton(
                                currentUserId: widget.currentUserId,
                                targetUserId: user.userId,
                                onUnfollow: () {
                                  // Optimistic removal: esconde card instantaneamente
                                  widget.controller.optimisticRemoveFromFollowing(user.userId);
                                },
                              ),
                              onTap: () {
                                ProfileScreenRouter.navigateByUserId(
                                  context,
                                  userId: user.userId,
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FollowActionButton extends StatefulWidget {
  const _FollowActionButton({
    required this.currentUserId,
    required this.targetUserId,
    this.onUnfollow,
  });

  final String currentUserId;
  final String targetUserId;
  final VoidCallback? onUnfollow;

  @override
  State<_FollowActionButton> createState() => _FollowActionButtonState();
}

class _FollowActionButtonState extends State<_FollowActionButton> {
  late final FollowController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FollowController(
      myUid: widget.currentUserId,
      targetUid: widget.targetUserId,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _controller,
      builder: (context, isFollowing, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: _controller.isLoading,
          builder: (context, isLoading, __) {
            final label = isFollowing ? 'Seguindo' : 'Seguir';
            final outline = !isFollowing;
            final bgColor = isFollowing
                ? GlimpseColors.primaryLight
                : GlimpseColors.borderColorLight;

            return SizedBox(
              height: 36,
              width: 110,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: outline ? Colors.transparent : bgColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: outline
                        ? const BorderSide(
                            color: GlimpseColors.borderColorLight,
                            width: 1,
                          )
                        : BorderSide.none,
                  ),
                ),
                onPressed: isLoading ? null : () {
                  // Se está seguindo e vai dar unfollow, chama callback primeiro
                  if (isFollowing && widget.onUnfollow != null) {
                    widget.onUnfollow!();
                  }
                  _controller.toggleFollow();
                },
                child: Text(
                  label,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
