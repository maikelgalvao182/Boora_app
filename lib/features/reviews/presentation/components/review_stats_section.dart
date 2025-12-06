import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/reviews/data/models/review_stats_model.dart';
import 'package:partiu/features/reviews/domain/constants/review_badges.dart';

/// Widget que exibe as estatísticas agregadas de reviews no perfil
/// 
/// Features:
/// - Overall rating com estrelas
/// - Total de reviews
/// - Breakdown por critério
/// - Top badges recebidos
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GlimpseColors.primary.withOpacity(0.1),
            GlimpseColors.primary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: GlimpseColors.primary.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.star_rounded,
                color: GlimpseColors.warning,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                'Avaliações',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: GlimpseColors.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Overall Rating
          Row(
            children: [
              Text(
                stats.overallRating.toStringAsFixed(1),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: GlimpseColors.primary,
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
                      '${stats.totalReviews} ${stats.totalReviews == 1 ? "avaliação" : "avaliações"}',
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
            const Divider(),
            const SizedBox(height: 16),
            ...stats.ratingsBreakdown.entries.map((entry) {
              return _buildCriterionBar(
                entry.key,
                entry.value,
              );
            }).toList(),
          ],

          // Top Badges
          if (stats.badgesCount.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Elogios mais recebidos',
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: GlimpseColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _buildTopBadges(),
          ],
        ],
      ),
    );
  }

  Widget _buildStars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return Icon(
            Icons.star_rounded,
            color: GlimpseColors.warning,
            size: 20,
          );
        } else if (index < rating) {
          return Icon(
            Icons.star_half_rounded,
            color: GlimpseColors.warning,
            size: 20,
          );
        } else {
          return Icon(
            Icons.star_outline_rounded,
            color: Colors.grey.shade300,
            size: 20,
          );
        }
      }),
    );
  }

  Widget _buildCriterionBar(String key, double rating) {
    final label = _getCriterionLabel(key);
    final emoji = _getCriterionEmoji(key);
    final percentage = (rating / 5) * 100;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: GlimpseColors.textSecondary,
                  ),
                ),
              ),
              Text(
                rating.toStringAsFixed(1),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: GlimpseColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rating / 5,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(GlimpseColors.primary),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBadges() {
    // Ordena badges por count (top 3)
    final sortedBadges = stats.badgesCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topBadges = sortedBadges.take(3).toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: topBadges.map((entry) {
        final badge = ReviewBadge.fromKey(entry.key);
        if (badge == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: badge.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: badge.color.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                badge.emoji,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 8),
              Text(
                badge.title,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: badge.color,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badge.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${entry.value}',
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: badge.color,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
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
        return 'Papo & Conexão';
      case 'energy':
        return 'Energia & Presença';
      case 'coexistence':
        return 'Convivência';
      case 'participation':
        return 'Participação';
      default:
        return key;
    }
  }
}
