import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
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
import 'package:partiu/features/home/presentation/widgets/user_card.dart';
import 'package:partiu/features/home/presentation/widgets/user_card_shimmer.dart';
import 'package:partiu/common/state/app_state.dart';

class FollowersScreen extends StatefulWidget {
  const FollowersScreen({super.key});

  @override
  State<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends State<FollowersScreen> {
  late final FollowersController _controller;
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
      _controller = FollowersController(userId: _userId!);
      _controller.initialize();
    }
  }

  @override
  void dispose() {
    _followersScrollController.dispose();
    _followingScrollController.dispose();
    if (_userId != null && _userId!.isNotEmpty) {
      _controller.dispose();
    }
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
              fontSize: 18,
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
            fontSize: 18,
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
            child: IndexedStack(
              index: _tabIndex,
              children: [
                _FollowersListTab(
                  controller: _controller,
                  currentUserId: userId,
                  scrollController: _followersScrollController,
                ),
                _FollowingListTab(
                  controller: _controller,
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

class _FollowersListTab extends StatelessWidget {
  const _FollowersListTab({
    required this.controller,
    required this.currentUserId,
    required this.scrollController,
  });

  final FollowersController controller;
  final String currentUserId;
  final ScrollController scrollController;

  String _tr(AppLocalizations i18n, String key, String fallback) {
    final value = i18n.translate(key);
    return value.isNotEmpty ? value : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return ValueListenableBuilder<List<User>>(
      valueListenable: controller.followers,
      builder: (context, users, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: controller.isLoadingFollowers,
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
              valueListenable: controller.followersError,
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
                          onPressed: controller.refreshFollowers,
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

                return PlatformPullToRefresh(
                  onRefresh: controller.refreshFollowers,
                  controller: scrollController,
                  padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index].copyWith(distance: null);
                    return UserCard(
                      key: ValueKey(user.userId),
                      userId: user.userId,
                      user: user,
                      trailingWidget: _FollowActionButton(
                        currentUserId: currentUserId,
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
  }
}

class _FollowingListTab extends StatelessWidget {
  const _FollowingListTab({
    required this.controller,
    required this.currentUserId,
    required this.scrollController,
  });

  final FollowersController controller;
  final String currentUserId;
  final ScrollController scrollController;

  String _tr(AppLocalizations i18n, String key, String fallback) {
    final value = i18n.translate(key);
    return value.isNotEmpty ? value : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return ValueListenableBuilder<List<User>>(
      valueListenable: controller.following,
      builder: (context, users, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: controller.isLoadingFollowing,
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
              valueListenable: controller.followingError,
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
                          onPressed: controller.refreshFollowing,
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

                return PlatformPullToRefresh(
                  onRefresh: controller.refreshFollowing,
                  controller: scrollController,
                  padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index].copyWith(distance: null);
                    return UserCard(
                      key: ValueKey(user.userId),
                      userId: user.userId,
                      user: user,
                      trailingWidget: _FollowActionButton(
                        currentUserId: currentUserId,
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
  }
}

class _FollowActionButton extends StatefulWidget {
  const _FollowActionButton({
    required this.currentUserId,
    required this.targetUserId,
  });

  final String currentUserId;
  final String targetUserId;

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
                  ),
                ),
                onPressed: isLoading ? null : _controller.toggleFollow,
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
