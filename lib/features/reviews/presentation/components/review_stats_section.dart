import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/reviews/data/models/review_stats_model.dart';
import 'package:partiu/shared/widgets/criteria_bars.dart';

/// Widget que exibe as estatísticas agregadas de reviews no perfil
/// 
/// Features:
/// - Overall rating com estrelas
/// - Total de reviews
/// - Breakdown por critério
class ReviewStatsSection extends StatelessWidget {
  const ReviewStatsSection({
    required this.stats,
    super.key,
  });

  final ReviewStatsModel stats;

  @override
  Widget build(BuildContext context) {
    if (!stats.hasReviews) {
      return const SizedBox.shrink();
    }

    final i18n = AppLocalizations.of(context);
    final countTemplate = stats.totalReviews == 1
        ? i18n.translate('review_stats_count_singular')
        : i18n.translate('review_stats_count_plural');
    final countText = countTemplate.replaceAll('{count}', stats.totalReviews.toString());

    return Container(
      padding: GlimpseStyles.profileSectionPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.translate('review_stats_title'),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: GlimpseColors.primaryColorLight,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: GlimpseColors.lightTextField,
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Overall Rating
              Row(
                children: [
                  Text(
                    stats.overallRating.toStringAsFixed(1),
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: GlimpseColors.primaryColorLight,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStars(stats.overallRating),
                        const SizedBox(height: 4),
                        Text(
                          countText,
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: GlimpseColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Breakdown por critério
              if (stats.ratingsBreakdown.isNotEmpty) ...[
                const SizedBox(height: 20),
                CriteriaBars(
                  criteriaRatings: stats.ratingsBreakdown,
                  showDivider: false,
                  showEmojis: true,
                ),
              ],
            ],
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildStars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return const Icon(
            Iconsax.star1,
            color: Colors.amber,
            size: 20,
          );
        } else if (index < rating) {
          return const Icon(
            Iconsax.star1, // Usando star1 para meia estrela também, já que Iconsax não tem meia
            color: Colors.amber,
            size: 20,
          );
        } else {
          return Icon(
            Iconsax.star,
            color: Colors.grey.shade300,
            size: 20,
          );
        }
      }),
    );
  }
}
