import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/review_model.dart';
import 'package:partiu/core/utils/date_helper.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/star_rating_display.dart';

/// Card que exibe uma avaliação individual no perfil
/// 
/// Features:
/// - Avatar do avaliador com fallback
/// - Nome e data da avaliação
/// - Rating com estrelas
/// - Comentário com expansão "Ver mais"
class ReviewCard extends StatefulWidget {

  const ReviewCard({
    required this.review, 
    super.key,
    this.onTap,
  });
  
  final Review review;
  final VoidCallback? onTap;

  @override
  State<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<ReviewCard> {
  bool _showFullComment = false;

  @override
  Widget build(BuildContext context) {
    final reviewDate = DateHelper.formatRelativeDate(
      widget.review.createdAt,
      context: context,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: GlimpseColors.textSubTitle.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Avatar + Nome + Job Title
              Row(
                children: [
                  // Avatar
                  StableAvatar(
                    userId: widget.review.reviewerId,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  // Nome e Job Title
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ReactiveUserNameWithBadge(
                          userId: widget.review.reviewerId,
                          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: GlimpseColors.textSubTitle,
                          ),
                          iconSize: 14,
                          spacing: 4,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.review.userJobTitle,
                          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: GlimpseColors.textSubTitle,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Rating e Data
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StarRatingDisplay(
                        rating: widget.review.overallRating,
                        size: 18,
                        showNumber: false,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reviewDate,
                        style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: GlimpseColors.textSubTitle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Comentário (se existir)
              if (widget.review.comment != null &&
                  widget.review.comment!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildComment(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComment() {
    final comment = widget.review.comment!;
    final maxLines = _showFullComment ? null : 3;

    final commentText = Text(
      comment,
      style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: GlimpseColors.textSubTitle,
        height: 1.5,
      ),
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
      softWrap: true,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        commentText,
        // Botão "Ver mais" se o texto for longo
        if (comment.length > 100)
          GestureDetector(
            onTap: () {
              setState(() {
                _showFullComment = !_showFullComment;
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _showFullComment ? 'Mostrar menos' : 'Ver mais',
                style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.primaryColorLight,
                ),
                softWrap: true,
              ),
            ),
          ),
      ],
    );
  }
}
