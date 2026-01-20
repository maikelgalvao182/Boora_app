import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/presentation/widgets/category/activity_category.dart';

/// Widget de seleção de categoria em grid 2 colunas
class CategorySelector extends StatelessWidget {
  const CategorySelector({
    required this.selectedCategory,
    required this.onCategorySelected,
    super.key,
  });

  final ActivityCategory? selectedCategory;
  final ValueChanged<ActivityCategory> onCategorySelected;

  static const List<Color> _cardPalette = <Color>[
    GlimpseColors.categoryCard1,
    GlimpseColors.categoryCard2,
    GlimpseColors.categoryCard3,
    GlimpseColors.categoryCard4,
    GlimpseColors.categoryCard5,
    GlimpseColors.categoryCard6,
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: activityCategories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final categoryInfo = activityCategories[index];
        final isSelected = selectedCategory == categoryInfo.category;

        final baseColor = _cardPalette[index % _cardPalette.length];

        return _CategoryCard(
          categoryInfo: categoryInfo,
          isSelected: isSelected,
          baseColor: baseColor,
          onTap: () => onCategorySelected(categoryInfo.category),
        );
      },
    );
  }
}

/// Card individual de categoria
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.categoryInfo,
    required this.isSelected,
  required this.baseColor,
    required this.onTap,
  });

  final ActivityCategoryInfo categoryInfo;
  final bool isSelected;
  final Color baseColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          // Mantém a cor de fundo original do card; a paleta fica só no emoji.
          color: isSelected
              ? GlimpseColors.primaryLight
              : GlimpseColors.lightTextField,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? GlimpseColors.primary : GlimpseColors.lightTextField,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            // Emoji dentro de container redondo à esquerda
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
        color: isSelected
          ? GlimpseColors.primary.withValues(alpha: 0.12)
          : baseColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                categoryInfo.emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
            const SizedBox(width: 12),

            // Textos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    i18n.translate(categoryInfo.titleKey),
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: GlimpseColors.primaryColorLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    i18n.translate(categoryInfo.subtitleKey),
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: GlimpseColors.textSubTitle,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Espaço do indicador removido
          ],
        ),
      ),
    );
  }
}
