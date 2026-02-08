import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';
import 'package:partiu/features/reviews/domain/constants/review_badges.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:intl/intl.dart';

/// Card que exibe uma review individual no perfil
/// 
/// Compatível com o novo sistema de reviews:
/// - Ratings por critério
/// - Badges de elogios
/// - Comentário expandível
class ReviewCardV2 extends StatefulWidget {
  const ReviewCardV2({
    required this.review,
    super.key,
    this.onTap,
  });

  final ReviewModel review;
  final VoidCallback? onTap;

  @override
  State<ReviewCardV2> createState() => _ReviewCardV2State();
}

class _ReviewCardV2State extends State<ReviewCardV2> {
  bool _showFullComment = false;

  @override
  Widget build(BuildContext context) {
    final reviewDate = _formatDate(widget.review.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Avatar + Nome + Rating
              Row(
                children: [
                  // Avatar
                  StableAvatar(
                    userId: widget.review.reviewerId,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  
                  // Nome e Data
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ReactiveUserNameWithBadge(
                          userId: widget.review.reviewerId,
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: GlimpseColors.textPrimary,
                          ),
                          iconSize: 16,
                          spacing: 4,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          reviewDate,
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: GlimpseColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Rating geral
                  _buildRatingBadge(),
                ],
              ),

              // Badges (se existirem)
              if (widget.review.badges.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildBadges(),
              ],

              // Ratings detalhados
              const SizedBox(height: 12),
              _buildDetailedRatings(),

              // Comentário (se existir)
              if (widget.review.hasComment) ...[
                const SizedBox(height: 12),
                _buildComment(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: GlimpseColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star,
            size: 16,
            color: GlimpseColors.warning,
          ),
          const SizedBox(width: 4),
          Text(
            widget.review.overallRating.toStringAsFixed(1),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: GlimpseColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadges() {
    final i18n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.review.badges.map((badgeKey) {
        final badge = ReviewBadge.fromKey(badgeKey);
        if (badge == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: badge.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: badge.color.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                badge.emoji,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 6),
              Text(
                badge.localizedTitle(i18n),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: badge.color,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDetailedRatings() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: widget.review.criteriaRatings.entries.map((entry) {
        final criterionKey = entry.key;
        final rating = entry.value;

        // Mapeia critérios para emojis
        final emoji = _getCriterionEmoji(criterionKey);
        final label = _getCriterionLabel(criterionKey);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              ...List.generate(5, (index) {
                return Icon(
                  index < rating ? Icons.star : Icons.star_border,
                  size: 12,
                  color: index < rating
                      ? GlimpseColors.warning
                      : Colors.grey.shade300,
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildComment() {
    final comment = widget.review.comment!;
    final maxLines = _showFullComment ? null : 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: GlimpseColors.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Text(
            comment,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: GlimpseColors.textPrimary,
              height: 1.5,
            ),
            maxLines: maxLines,
            overflow: maxLines != null ? TextOverflow.ellipsis : null,
          ),
        ),
        
        // Botão "Ver mais" se o texto for longo
        if (comment.length > 150)
          GestureDetector(
            onTap: () {
              setState(() {
                _showFullComment = !_showFullComment;
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _showFullComment ? 'Mostrar menos' : 'Ver mais',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Hoje';
    } else if (diff.inDays == 1) {
      return 'Ontem';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} dias atrás';
    } else if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? "semana" : "semanas"} atrás';
    } else if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return '$months ${months == 1 ? "mês" : "meses"} atrás';
    } else {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }

  String _getCriterionEmoji(String key) {
    switch (key) {
      case 'conversation':
        return '💬';
      case 'energy':
        return '⚡';
      case 'coexistence':
        return '🤝';
      case 'participation':
        return '🎯';
      default:
        return '⭐';
    }
  }

  String _getCriterionLabel(String key) {
    switch (key) {
      case 'conversation':
        return 'Papo';
      case 'energy':
        return 'Energia';
      case 'coexistence':
        return 'Convivência';
      case 'participation':
        return 'Participação';
      default:
        return key;
    }
  }
}
