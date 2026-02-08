import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/reviews/domain/constants/review_criteria.dart';

/// Step de avaliação por critérios (Step 1)
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
      children: [
        // Lista de critérios
        ...ReviewCriteria.all(context).map((criterion) {
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
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: currentRating != null
              ? GlimpseColors.primary.withOpacity(0.3)
              : GlimpseColors.borderColorLight,
          width: currentRating != null ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Emoji e título
          Text(
            criterion['icon']!,
            style: const TextStyle(fontSize: 32),
          ),
          const SizedBox(height: 12),
          
          Text(
            criterion['title']!,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: GlimpseColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          
          Text(
            criterion['description']!,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: GlimpseColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          // Rating com estrelas (Iconsax)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final rating = index + 1;
              final isSelected = currentRating != null && rating <= currentRating!;

              return GestureDetector(
                onTap: () {
                  debugPrint('⭐ [RatingCriteria] Tap detectado!');
                  debugPrint('   - criterion: ${criterion['key']}');
                  debugPrint('   - rating: $rating');
                  debugPrint('   - currentRating: $currentRating');
                  onRatingChanged(rating);
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    isSelected ? Iconsax.star1 : Iconsax.star,
                    color: isSelected
                        ? const Color(0xFFFFC107) // Amarelo
                        : GlimpseColors.borderColorLight,
                    size: 32,
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
