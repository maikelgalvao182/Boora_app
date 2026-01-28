import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';
import 'package:partiu/features/profile/presentation/widgets/comment_card.dart';

class ReviewCommentsSection extends StatefulWidget {
  const ReviewCommentsSection({
    required this.reviews,
    super.key,
  });

  final List<ReviewModel> reviews;

  @override
  State<ReviewCommentsSection> createState() => _ReviewCommentsSectionState();
}

class _ReviewCommentsSectionState extends State<ReviewCommentsSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final topSpacing = isAndroid ? 16.0 : 0.0;

    // Filtrar apenas reviews que têm comentário
    final reviewsWithComments = widget.reviews.where((review) => 
      review.comment != null && review.comment!.trim().isNotEmpty
    ).toList();

    if (reviewsWithComments.isEmpty) {
      return const SizedBox.shrink();
    }

    // Lógica de exibição: 3 iniciais ou todas se expandido
    final displayedReviews = _isExpanded ? reviewsWithComments : reviewsWithComments.take(3).toList();
    final hasMoreReviews = reviewsWithComments.length > 3;

    return Container(
      padding: EdgeInsets.only(
        top: topSpacing,
        left: GlimpseStyles.horizontalMargin,
        right: GlimpseStyles.horizontalMargin,
        bottom: GlimpseStyles.profileSectionBottomSpacing,
      ),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.translate('review_comments_section_title'),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: GlimpseColors.primaryColorLight,
            ),
          ),
          const SizedBox(height: 12),
          
          ...displayedReviews.map((review) => CommentCard(review: review)),
          
          // Botão Ver mais / Ver menos
          if (hasMoreReviews)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  child: Text(
                    _isExpanded ? i18n.translate('see_less') : i18n.translate('see_more'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
