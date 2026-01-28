import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
// import 'package:partiu/core/constants/glimpse_variables.dart'; // DESABILITADO - usado para flags
import 'package:partiu/core/models/user.dart';
import 'package:partiu/features/home/domain/models/user_with_meta.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/features/home/presentation/widgets/user_card/user_card_controller.dart';
import 'package:partiu/features/home/presentation/widgets/user_card_shimmer.dart';
import 'package:partiu/shared/widgets/star_badge.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/shared/stores/user_store.dart';
// import 'package:partiu/shared/widgets/country_flag_widget.dart'; // DESABILITADO - flag do avatar removido

/// Card horizontal de usuário
/// 
/// Exibe:
/// - Avatar (StableAvatar)
/// - fullName
/// - locality/state (localização)
/// - Interesses em comum (se fornecido via userWithMeta)
/// - Time ago (opcional, apenas para profile_visits)
class UserCard extends StatefulWidget {
  const UserCard({
    required this.userId,
    this.userWithMeta,
    this.user,
    this.overallRating,
    this.onTap,
    this.onLongPress,
    this.trailingWidget,
    this.index,
    this.showTimeAgo = false,
    this.showRating = true,
    super.key,
  });

  final String userId;
  final UserWithMeta? userWithMeta;
  final User? user;
  final double? overallRating;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailingWidget;
  final int? index;
  final bool showTimeAgo;
  final bool showRating;

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard> {
  UserCardController? _controller;
  bool _needsRatingFromController = false;

  String? _formatLocationText({
    String? locality,
    String? state,
    String? fallback,
  }) {
    final city = locality?.trim();
    final uf = state?.trim();

    if (city != null && city.isNotEmpty && uf != null && uf.isNotEmpty) {
      return '$city, $uf';
    }
    if (city != null && city.isNotEmpty) {
      return city;
    }

    final fb = fallback?.trim();
    if (fb != null && fb.isNotEmpty) {
      return fb.replaceAll(RegExp(r'\s*-\s*'), ', ');
    }

    return null;
  }

  String? _formatDistanceText(double? rawDistance) {
    if (rawDistance == null || !rawDistance.isFinite || rawDistance < 0) {
      return null;
    }

    // Heurística: em alguns fluxos o valor vem em METROS (ex.: Geolocator.distanceBetween)
    // mas a UI do card sempre assume KM. Se vier muito grande, converte para km.
    final distanceKm = rawDistance >= 1000 ? (rawDistance / 1000.0) : rawDistance;
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  @override
  void initState() {
    super.initState();
    
    // Só buscar rating via controller se não foi fornecido
    _needsRatingFromController = widget.overallRating == null && widget.user?.overallRating == null;
    
    if (_needsRatingFromController) {
      _controller = UserCardController(userId: widget.userId);
      _controller!.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    if (_needsRatingFromController && _controller != null) {
      _controller!.removeListener(_onControllerChanged);
      _controller!.dispose();
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determinar rating: fornecido ou do controller
    final rating = widget.overallRating ?? widget.user?.overallRating ?? _controller?.overallRating;
    
    // 1. Prioridade: UserWithMeta (se fornecido)
    if (widget.userWithMeta != null) {
      final u = widget.userWithMeta!;
      return _buildUserCard(
        fullName: u.user.fullName ?? 'Usuário',
        locality: u.user.locality,
        state: u.user.state,
        distanceKm: u.distanceKm,
        commonInterests: u.commonInterests,
        photoUrl: u.user.photoUrl,
        overallRating: rating,
        countryFlag: u.user.flag,
        countryName: null,
      );
    }

    // 2. Prioridade: User (se fornecido)
    if (widget.user != null) {
      final u = widget.user!;
      return _buildUserCard(
        fullName: u.userFullname,
        locality: u.locality,
        state: u.state,
        fallbackLocation: u.from,
        distanceKm: u.distance,
        commonInterests: u.commonInterests ?? [],
        photoUrl: u.photoUrl,
        overallRating: rating,
        visitedAt: u.visitedAt,
        countryFlag: u.flag,
        countryName: u.from,
      );
    }

    // 3. Fallback: Controller fetch (apenas se controller existir)
    if (_controller == null) {
      return const SizedBox.shrink();
    }

    if (_controller!.isLoading) {
      return const UserCardShimmer();
    }

    if (_controller!.error != null) {
      return _buildErrorCard();
    }

    final user = _controller!.user;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return _buildUserCard(
      fullName: user.fullName,
      locality: user.locality,
      state: user.state,
      fallbackLocation: user.from,
      distanceKm: user.distance,
      commonInterests: user.commonInterests ?? [],
      photoUrl: user.photoUrl,
      overallRating: rating,
      countryFlag: user.flag,
      countryName: user.from,
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GlimpseColors.borderColorLight,
          width: 0,
        ),
      ),
      child: Center(
        child: Text(
          _controller?.error ?? 'Erro',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 13,
            color: Colors.red,
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard({
    required String fullName,
    String? locality,
    String? state,
    String? fallbackLocation,
    double? distanceKm,
    List<String> commonInterests = const [],
    String? photoUrl,
    double? overallRating,
    DateTime? visitedAt,
    String? countryFlag,
    String? countryName,
  }) {
    final distanceText = _formatDistanceText(distanceKm);
    final initialLocationText = _formatLocationText(
      locality: locality,
      state: state,
      fallback: fallbackLocation,
    );

    // Process common interests - DESABILITADO (matches removidos da UI)
    // TODO: Reativar quando necessário
    // String commonInterestsText = '0 matchs ';
    // String commonInterestsEmojis = '🔍';
    // if (commonInterests.isNotEmpty) {
    //   final count = commonInterests.length;
    //   final emojis = commonInterests
    //       .take(6)
    //       .map((id) => getInterestById(id)?.icon ?? '')
    //       .where((icon) => icon.isNotEmpty)
    //       .join(' ');
    //   
    //   if (emojis.isNotEmpty) {
    //     commonInterestsText = '$count matchs: ';
    //     commonInterestsEmojis = emojis;
    //   } else {
    //     commonInterestsText = '$count matchs';
    //     commonInterestsEmojis = '';
    //   }
    // }

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar com flag
            Stack(
              clipBehavior: Clip.none,
              children: [
                StableAvatar(
                  userId: widget.userId,
                  photoUrl: photoUrl ?? _controller?.photoUrl,
                  size: 48,
                  borderRadius: BorderRadius.circular(8),
                  enableNavigation: true,
                ),
                
                // Country flag badge (parte inferior do avatar) - DESABILITADO
                // TODO: Reativar quando necessário
                // if ((countryName != null && countryName.isNotEmpty) ||
                //     (countryFlag != null && countryFlag.isNotEmpty))
                //   Positioned(
                //     bottom: -4,
                //     left: 0,
                //     right: 0,
                //     child: Center(
                //       child: CountryFlagWidget(
                //         countryName: countryName,
                //         flag: countryFlag,
                //         size: 20,
                //         borderWidth: 2,
                //       ),
                //     ),
                //   ),
              ],
            ),
            
            const SizedBox(width: 12),
            
            // Informações
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Nome completo + Rating badge + Time ago (se showTimeAgo)
                  Row(
                    children: [
                      Expanded(
                        child: ReactiveUserNameWithBadge(
                          userId: widget.userId,
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: GlimpseColors.primaryColorLight,
                          ),
                        ),
                      ),
                      if (widget.showTimeAgo && visitedAt != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          TimeAgoHelper.format(context, timestamp: visitedAt),
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: GlimpseColors.textSubTitle,
                          ),
                        ),
                      ],
                      if (widget.showRating && overallRating != null && overallRating > 0) ...[
                        const SizedBox(width: 8),
                        StarBadge(rating: overallRating),
                      ],
                    ],
                  ),

                  // Locality/State (esquerda) + Distância (direita)
                  ValueListenableBuilder<String?>(
                    valueListenable: UserStore.instance.getCityNotifier(widget.userId),
                    builder: (context, city, _) {
                      return ValueListenableBuilder<String?>(
                        valueListenable: UserStore.instance.getStateNotifier(widget.userId),
                        builder: (context, uf, __) {
                          final resolvedLocationText = _formatLocationText(
                            locality: city ?? locality,
                            state: uf ?? state,
                            fallback: initialLocationText,
                          );

                            final hasRow = (resolvedLocationText != null && resolvedLocationText.isNotEmpty) ||
                              distanceText != null;

                          if (!hasRow) {
                            return const SizedBox.shrink();
                          }

                          return Column(
                            children: [
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (resolvedLocationText != null && resolvedLocationText.isNotEmpty)
                                    Expanded(
                                      child: Text(
                                        resolvedLocationText,
                                        style: GoogleFonts.getFont(
                                          FONT_PLUS_JAKARTA_SANS,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: GlimpseColors.textSubTitle,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )
                                  else
                                    const Spacer(),

                                  if (distanceText != null)
                                    Text(
                                      distanceText,
                                      style: GoogleFonts.getFont(
                                        FONT_PLUS_JAKARTA_SANS,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: GlimpseColors.textSubTitle,
                                      ),
                                    ),

                                ],
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  // Interesses em comum (linha de baixo) - DESABILITADO
                  // TODO: Reativar quando necessário
                  // if (commonInterestsText.isNotEmpty) ...[
                  //   commonInterestsEmojis.isEmpty
                  //       ? Text(
                  //           commonInterestsText,
                  //           style: GoogleFonts.getFont(
                  //             FONT_PLUS_JAKARTA_SANS,
                  //             fontSize: 13,
                  //             fontWeight: FontWeight.w600,
                  //             color: GlimpseColors.textSubTitle,
                  //           ),
                  //           maxLines: 1,
                  //           overflow: TextOverflow.ellipsis,
                  //         )
                  //       : Text.rich(
                  //           TextSpan(
                  //             children: [
                  //               TextSpan(
                  //                 text: commonInterestsText,
                  //                 style: GoogleFonts.getFont(
                  //                   FONT_PLUS_JAKARTA_SANS,
                  //                   fontSize: 13,
                  //                   fontWeight: FontWeight.w600,
                  //                   color: GlimpseColors.textSubTitle,
                  //                 ),
                  //               ),
                  //               TextSpan(
                  //                 text: commonInterestsEmojis,
                  //                 style: const TextStyle(
                  //                   fontSize: 16,
                  //                 ),
                  //               ),
                  //             ],
                  //           ),
                  //           maxLines: 1,
                  //           overflow: TextOverflow.ellipsis,
                  //         ),
                  // ],
                ],
              ),
            ),
            if (widget.trailingWidget != null) ...[
              const SizedBox(width: 12),
              Center(child: widget.trailingWidget!),
            ],
          ],
        ),
      ),
    );
  }
}
