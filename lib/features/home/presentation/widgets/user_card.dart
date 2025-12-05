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
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final String userId;
  final UserWithMeta? userWithMeta;
  final User? user;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard> {
  late UserCardController _controller;

  @override
  void initState() {
    super.initState();
    debugPrint('🎴 UserCard iniciado para userId: ${widget.userId}');
    
    // Se userWithMeta ou user for fornecido, o controller pode não ser necessário para fetch,
    // mas mantemos para compatibilidade ou usamos dados diretos.
    _controller = UserCardController(userId: widget.userId);
    if (widget.userWithMeta == null && widget.user == null) {
      _controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    if (widget.userWithMeta == null) {
      _controller.removeListener(_onControllerChanged);
    }
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Prioridade: UserWithMeta (se fornecido)
    if (widget.userWithMeta != null) {
      final u = widget.userWithMeta!;
      return _buildUserCard(
        fullName: u.user.fullName ?? 'Usuário',
        from: '', // UserWithMeta/UserModel não tem from
        distanceKm: u.distanceKm,
        commonInterests: u.commonInterests,
        photoUrl: u.user.photoUrl,
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
        photoUrl: u.profilePhotoUrl,
      );
    }

    // 3. Fallback: Controller fetch
    if (_controller.isLoading) {
      return const UserCardShimmer();
    }

    if (_controller.error != null) {
      return _buildErrorCard();
    }

    final user = _controller.user;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return _buildUserCard(
      fullName: user.fullName,
      from: user.from ?? '',
      distanceKm: user.distance, // Controller deve fornecer distance se possível
      commonInterests: user.interests ?? [],
      photoUrl: user.profilePhotoUrl,
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
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          _controller.error ?? 'Erro',
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
  }) {
    final distanceText = distanceKm != null 
        ? '${distanceKm.toStringAsFixed(1)} km' 
        : null;

    // Process common interests
    String commonInterestsText = '';
    if (commonInterests.isNotEmpty) {
      final count = commonInterests.length;
      final emojis = commonInterests
          .take(5)
          .map((id) => getInterestById(id)?.icon ?? '')
          .where((icon) => icon.isNotEmpty)
          .join(' ');
      
      if (emojis.isNotEmpty) {
        commonInterestsText = '$count matchs: $emojis';
      }
    }

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: GlimpseColors.borderColorLight,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            StableAvatar(
              userId: widget.userId,
              photoUrl: photoUrl ?? _controller.photoUrl,
              size: 58,
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
                  // Nome completo
                  Text(
                    fullName,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: GlimpseColors.primaryColorLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  // Localização e Distância
                  if (from.isNotEmpty || distanceText != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (from.isNotEmpty) ...[
                          Flexible(
                            child: Text(
                              from,
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: GlimpseColors.textSubTitle,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        
                        if (from.isNotEmpty && distanceText != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: GlimpseColors.textSubTitle,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],

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

                  // Interesses em comum
                  if (commonInterestsText.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            commonInterestsText,
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: GlimpseColors.textSubTitle,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(width: 8),
            
            const Icon(
              Icons.chevron_right,
              color: GlimpseColors.textSubTitle,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
