import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/data/models/user_ranking_model.dart';
import 'package:partiu/shared/widgets/animated_expandable.dart';
import 'package:partiu/shared/widgets/badge_card.dart';
import 'package:partiu/shared/widgets/criteria_bars.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

/// Card de ranking de pessoa
/// 
/// Exibe:
/// - Posição no ranking
/// - Avatar, nome e localização
/// - Rating geral com total de reviews
/// - Badges com scroll horizontal (expansível)
/// - Breakdown visual dos critérios (expansível)
/// - Número de comentários
class PeopleRankingCard extends StatefulWidget {
  const PeopleRankingCard({
    required this.ranking,
    required this.position,
    super.key,
    this.badgesCount = const {},
    this.criteriaRatings = const {},
    this.totalComments = 0,
  });

  final UserRankingModel ranking;
  final int position;
  final Map<String, int> badgesCount;
  final Map<String, double> criteriaRatings;
  final int totalComments;

  @override
  State<PeopleRankingCard> createState() => _PeopleRankingCardState();
}

class _PeopleRankingCardState extends State<PeopleRankingCard> {
  bool _isExpanded = false;

  bool get _isCompactScreen => MediaQuery.sizeOf(context).width <= 360;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1.w,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.all(16.r),
            child: _buildHeader(),
          ),
          
          // Conteúdo expansível
          AnimatedExpandable(
            isExpanded: _isExpanded,
            child: Padding(
              padding: EdgeInsets.only(left: 16.w, right: 16.w, bottom: 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges (se existirem)
                  if (widget.badgesCount.isNotEmpty) ...[
                    SizedBox(height: 8.h),
                    _buildBadges(context),
                  ],
                  
                  // Breakdown de critérios (se existirem)
                  if (widget.criteriaRatings.isNotEmpty) ...[
                    SizedBox(height: 12.h),
                    _buildCriteriaBreakdown(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar
            InkWell(
              onTap: () {
                context.push('/profile/${widget.ranking.userId}');
              },
              borderRadius: BorderRadius.circular(8.r),
              child: StableAvatar(
                userId: widget.ranking.userId,
                size: 58.w,
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            
            SizedBox(width: 12.w),
            
            // Informações
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nome
                  Padding(
                    padding: EdgeInsets.only(right: 48.w),
                    child: ReactiveUserNameWithBadge(
                      userId: widget.ranking.userId,
                      iconSize: (_isCompactScreen ? 11 : 13).sp,
                      spacing: (_isCompactScreen ? 3 : 4).w,
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: (_isCompactScreen ? 14 : 15).sp,
                        fontWeight: FontWeight.w700,
                        color: GlimpseColors.primaryColorLight,
                        height: 1.1,
                      ),
                    ),
                  ),
                  
                  SizedBox(height: (_isCompactScreen ? 2 : 4).h),
                  
                  // Localização
                  Text(
                    _getLocationText(),
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: (_isCompactScreen ? 11 : 12).sp,
                      fontWeight: FontWeight.w500,
                      color: GlimpseColors.textSubTitle,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                                    
                  // Rating + Reviews + Comentários
                  _buildRatingSummary(),
                ],
              ),
            ),
          ],
        ),
        
        // Posição no canto direito
        Positioned(
          top: 0,
          right: 0,
          child: _buildPosition(),
        ),
      ],
    );
  }

  Widget _buildPosition() {
    return Container(
      width: 28.w,
      height: 28.h,
      decoration: BoxDecoration(
        color: _getPositionBackgroundColor(),
        borderRadius: BorderRadius.circular(6.r),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.position.toString(),
        style: GoogleFonts.getFont(
          FONT_PLUS_JAKARTA_SANS,
          fontSize: 12.sp,
          fontWeight: FontWeight.w700,
          color: GlimpseColors.primaryColorLight,
        ),
      ),
    );
  }

  Color _getPositionBackgroundColor() {
    switch (widget.position) {
      case 1:
        return const Color(0xFFFFD700).withValues(alpha: 0.15); // Ouro claro
      case 2:
        return const Color(0xFFC0C0C0).withValues(alpha: 0.15); // Prata claro
      case 3:
        return const Color(0xFFCD7F32).withValues(alpha: 0.15); // Bronze claro
      default:
        return Colors.grey.shade100;
    }
  }

  Widget _buildRatingSummary() {
    final i18n = AppLocalizations.of(context);
    final totalReviews = widget.ranking.totalReviews;
    final totalComments = widget.totalComments;

    final reviewsText = (totalReviews == 1
            ? i18n.translate('reviews_count_singular')
            : i18n.translate('reviews_count_plural'))
        .replaceAll('{count}', totalReviews.toString());

    final commentsText = (totalComments == 1
            ? i18n.translate('comments_count_singular')
            : i18n.translate('comments_count_plural'))
        .replaceAll('{count}', totalComments.toString());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Container com os textos (sem chevron)
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Nota + Estrela
              Text(
                widget.ranking.overallRating.toStringAsFixed(1),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: (_isCompactScreen ? 11 : 12).sp,
                  fontWeight: FontWeight.w700,
                  color: GlimpseColors.primaryColorLight,
                  height: 1.1,
                ),
              ),
              SizedBox(width: 4.w),
              Icon(
                Iconsax.star1,
                size: (_isCompactScreen ? 16 : 18).w,
                color: const Color(0xFFFFB800),
              ),
              
              SizedBox(width: 4.w),
              
              // Separador
              Container(
                width: 3.w,
                height: 3.h,
                decoration: BoxDecoration(
                  color: GlimpseColors.textSubTitle.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
              ),
              
              SizedBox(width: 4.w),
              
              // Total de reviews
              Flexible(
                child: Text(
                  reviewsText,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: (_isCompactScreen ? 11 : 12).sp,
                    fontWeight: FontWeight.w500,
                    color: GlimpseColors.textSubTitle,
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              // Comentários (se houver)
              if (totalComments > 0) ...[
                SizedBox(width: 4.w),
                Container(
                  width: 3.w,
                  height: 3.h,
                  decoration: BoxDecoration(
                    color: GlimpseColors.textSubTitle.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 4.w),
                Flexible(
                  child: Text(
                    commentsText,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: (_isCompactScreen ? 11 : 12).sp,
                      fontWeight: FontWeight.w500,
                      color: GlimpseColors.textSubTitle,
                      height: 1.1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // Chevron expansível (se houver conteúdo expansivel)
        if (widget.badgesCount.isNotEmpty || widget.criteriaRatings.isNotEmpty) ...[
          SizedBox(width: 8.w),
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12.r),
            child: Padding(
              padding: EdgeInsets.all(4.r),
              child: SizedBox(
                width: 20.w,
                height: 20.h,
                child: AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    Iconsax.arrow_down_1,
                    size: 16.w,
                    color: GlimpseColors.textSubTitle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBadges(BuildContext context) {
    // Ordenar badges por frequência
    final sortedBadges = widget.badgesCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    if (sortedBadges.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Divider
        Container(
          height: 1.h,
          color: GlimpseColors.borderColorLight,
          margin: EdgeInsets.only(bottom: 12.h),
        ),
        
        // Badges com scroll horizontal
        SizedBox(
          height: 120.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sortedBadges.length,
            separatorBuilder: (context, index) => SizedBox(width: 8.w),
            itemBuilder: (context, index) {
              final entry = sortedBadges[index];
              return SizedBox(
                width: 115.w,
                child: BadgeCard(
                  badgeKey: entry.key,
                  count: entry.value,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCriteriaBreakdown() {
    return CriteriaBars(
      criteriaRatings: widget.criteriaRatings,
      showDivider: true,
    );
  }

  String _getLocationText() {
    if (widget.ranking.locality.isEmpty && (widget.ranking.state ?? '').isEmpty) {
      return AppLocalizations.of(context).translate('location_not_defined');
    }
    
    if (widget.ranking.state != null && widget.ranking.state!.isNotEmpty) {
      return '${widget.ranking.locality}, ${widget.ranking.state}';
    }
    
    return widget.ranking.locality;
  }
}
