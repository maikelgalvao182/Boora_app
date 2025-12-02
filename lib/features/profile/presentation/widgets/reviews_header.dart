import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/review_stats_model.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Header da seção de avaliações com estatísticas agregadas
/// 
/// Features:
/// - Overall rating com estrelas grandes
/// - Total de avaliações
/// - Breakdown por critério (opcional)
/// - Design responsivo
class ReviewsHeader extends StatelessWidget {

  const ReviewsHeader({
    required this.stats, 
    super.key,
    this.showBreakdown = false,
    this.onTap,
  });
  
  final ReviewStats stats;
  final bool showBreakdown;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Overall Rating
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Ícone estrela dourada
                const Icon(
                  Iconsax.star5,
                  color: Color(0xFFFFB800),
                  size: 48,
                ),
                const SizedBox(width: 8),
                // Rating numérico grande
                Text(
                  stats.overallRating.toStringAsFixed(1),
                  style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: GlimpseColors.primaryColorLight,
                  ),
                ),
                const SizedBox(width: 16),
                // Rating text + total
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.translate('rating_label'),
                      style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: GlimpseColors.textSubTitle,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stats.totalReviews} ${stats.totalReviews == 1 ? i18n.translate('review_singular') : i18n.translate('reviews_plural')}',
                      style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: GlimpseColors.textSubTitle,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Breakdown por critério (opcional)
            if (showBreakdown && stats.ratingsBreakdown.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _buildBreakdown(i18n, stats.ratingsBreakdown),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdown(
    AppLocalizations i18n,
    Map<String, double> breakdown,
  ) {
    // Ordena os critérios por rating (melhor primeiro)
    final sortedEntries = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.translate('rating_by_criteria'),
          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: GlimpseColors.textSubTitle,
          ),
        ),
        const SizedBox(height: 8),
        ...sortedEntries.map((entry) {
          final criterionKey = entry.key;
          final rating = entry.value;
          
          // Traduz o critério
          final translatedLabel = i18n.translate(criterionKey);
          final displayLabel = translatedLabel.isNotEmpty ? translatedLabel : criterionKey;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                // Barra de progresso visual
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayLabel,
                        style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: GlimpseColors.textSubTitle,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: rating / 5.0,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getColorForRating(rating),
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Rating numérico
                SizedBox(
                  width: 32,
                  child: Text(
                    rating.toStringAsFixed(1),
                    textAlign: TextAlign.right,
                    style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _getColorForRating(rating),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Color _getColorForRating(double rating) {
    if (rating >= 4.5) {
      return Colors.green;
    } else if (rating >= 3.5) {
      return GlimpseColors.primaryColorLight;
    } else if (rating >= 2.5) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
}
