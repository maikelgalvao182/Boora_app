import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_variables.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/features/home/domain/models/user_with_meta.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/features/home/presentation/widgets/user_card/user_card_controller.dart';
import 'package:partiu/features/home/presentation/widgets/user_card_shimmer.dart';
import 'package:partiu/shared/widgets/star_badge.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

/// Card horizontal de usuário
/// 
/// Exibe:
/// - Avatar (StableAvatar)
/// - fullName
/// - from (localização)
/// - Interesses em comum (se fornecido via userWithMeta)
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

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard> {
  UserCardController? _controller;
  bool _needsRatingFromController = false;

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
        from: '', // UserWithMeta/UserModel não tem from
        distanceKm: u.distanceKm,
        commonInterests: u.commonInterests,
        photoUrl: u.user.photoUrl,
        overallRating: rating,
      );
    }

    // 2. Prioridade: User (se fornecido)
    if (widget.user != null) {
      final u = widget.user!;
      return _buildUserCard(
        fullName: u.fullName,
        from: u.from ?? '',
        distanceKm: u.distance,
        commonInterests: u.commonInterests ?? [],
        photoUrl: u.photoUrl,
        overallRating: rating,
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
      from: user.from ?? '',
      distanceKm: user.distance,
      commonInterests: user.commonInterests ?? [],
      photoUrl: user.photoUrl,
      overallRating: rating,
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
    required String from,
    double? distanceKm,
    List<String> commonInterests = const [],
    String? photoUrl,
    double? overallRating,
  }) {
    final distanceText = distanceKm != null 
        ? '${distanceKm.toStringAsFixed(1)} km' 
        : null;

    // Process common interests
    String commonInterestsText = '0 matchs';
    String commonInterestsEmojis = '';
    if (commonInterests.isNotEmpty) {
      final count = commonInterests.length;
      final emojis = commonInterests
          .take(6)
          .map((id) => getInterestById(id)?.icon ?? '')
          .where((icon) => icon.isNotEmpty)
          .join(' ');
      
      if (emojis.isNotEmpty) {
        commonInterestsText = '$count matchs: ';
        commonInterestsEmojis = emojis;
      } else {
        commonInterestsText = '$count matchs';
      }
    }

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
            // Avatar
            StableAvatar(
              userId: widget.userId,
              photoUrl: photoUrl ?? _controller?.photoUrl,
              size: 56,
              borderRadius: BorderRadius.circular(8),
              enableNavigation: true,
            ),
            
            const SizedBox(width: 12),
            
            // Informações
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Nome completo + Rating badge
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
                      if (overallRating != null && overallRating > 0) ...[
                        const SizedBox(width: 8),
                        StarBadge(rating: overallRating),
                      ],
                    ],
                  ),

                  // Interesses em comum + Distância + Trailing na mesma linha
                  if (commonInterestsText.isNotEmpty || distanceText != null || widget.trailingWidget != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Interesses em comum
                        if (commonInterestsText.isNotEmpty)
                          Expanded(
                            child: commonInterestsEmojis.isEmpty
                                ? Text(
                                    commonInterestsText,
                                    style: GoogleFonts.getFont(
                                      FONT_PLUS_JAKARTA_SANS,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: GlimpseColors.textSubTitle,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: commonInterestsText,
                                          style: GoogleFonts.getFont(
                                            FONT_PLUS_JAKARTA_SANS,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: GlimpseColors.textSubTitle,
                                          ),
                                        ),
                                        TextSpan(
                                          text: commonInterestsEmojis,
                                          style: const TextStyle(
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                        
                        // Distância alinhada à direita
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
                        
                        // Trailing widget na mesma linha (direita)
                        if (widget.trailingWidget != null) ...[
                          const SizedBox(width: 8),
                          widget.trailingWidget!,
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
