import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/reviews/domain/constants/review_criteria.dart';

/// Step de avaliação por critérios (Step 0)
class RatingCriteriaStep extends StatelessWidget {
  final Map<String, int> ratings;
  final Function(String, int) onRatingChanged;

  const RatingCriteriaStep({
    required this.ratings,
    required this.onRatingChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título
        Text(
          'Avalie os critérios',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: GlimpseColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        
        // Subtítulo
        Text(
          'Avalie pelo menos um critério',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: GlimpseColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        
        // Lista de critérios
        ...ReviewCriteria.all.map((criterion) {
          return _CriterionItem(
            criterion: criterion,
            currentRating: ratings[criterion['key']],
            onRatingChanged: (rating) =>
                onRatingChanged(criterion['key']!, rating),
          );
        }).toList(),
      ],
    );
  }
}

class _CriterionItem extends StatelessWidget {
  final Map<String, String> criterion;
  final int? currentRating;
  final Function(int) onRatingChanged;

  const _CriterionItem({
    required this.criterion,
    required this.currentRating,
    required this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: currentRating != null
            ? GlimpseColors.primary.withOpacity(0.05)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: currentRating != null
              ? GlimpseColors.primary.withOpacity(0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com ícone e título
          Row(
            children: [
              Text(
                criterion['icon']!,
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      criterion['title']!,
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: GlimpseColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      criterion['description']!,
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
            ],
          ),
          const SizedBox(height: 16),
          
          // Rating com estrelas
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final rating = index + 1;
              final isSelected = currentRating != null && rating <= currentRating!;

              return GestureDetector(
                onTap: () => onRatingChanged(rating),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    isSelected ? Icons.star : Icons.star_border,
                    color: isSelected
                        ? GlimpseColors.warning
                        : Colors.grey.shade300,
                    size: 36,
                  ),
                ),
              );
            }),
          ),
          
          // Label do rating
          if (currentRating != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _getRatingLabel(currentRating!),
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
      ),
    );
  }

  String _getRatingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Muito ruim';
      case 2:
        return 'Ruim';
      case 3:
        return 'Regular';
      case 4:
        return 'Bom';
      case 5:
        return 'Excelente';
      default:
        return '';
    }
  }
}
