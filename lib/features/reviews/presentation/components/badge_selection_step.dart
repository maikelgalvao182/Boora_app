import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/reviews/domain/constants/review_badges.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Step de seleção de badges (Step 1)
class BadgeSelectionStep extends StatelessWidget {
  final List<String> selectedBadges;
  final Function(String) onBadgeToggle;

  const BadgeSelectionStep({
    required this.selectedBadges,
    required this.onBadgeToggle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título
        Text(
          'Quer deixar um elogio? Escolha um badge!',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: GlimpseColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        
        // Subtítulo
        Text(
          'Selecione quantos quiser (opcional)',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: GlimpseColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        
        // Grid de badges
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.5,
          ),
          itemCount: availableBadges.length,
          itemBuilder: (context, index) {
            final badge = availableBadges[index];
            final isSelected = selectedBadges.contains(badge.key);

            return _BadgeItem(
              badge: badge,
              isSelected: isSelected,
              onTap: () => onBadgeToggle(badge.key),
            );
          },
        ),
        
        const SizedBox(height: 16),
        
        // Contador de badges selecionados
        if (selectedBadges.isNotEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: GlimpseColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${selectedBadges.length} ${selectedBadges.length == 1 ? "badge selecionado" : "badges selecionados"}',
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
}

class _BadgeItem extends StatelessWidget {
  final ReviewBadge badge;
  final bool isSelected;
  final VoidCallback onTap;

  const _BadgeItem({
    required this.badge,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? badge.color.withOpacity(0.15)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? badge.color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Emoji
            Text(
              badge.emoji,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 8),
            
            // Título
            Flexible(
              child: Text(
                badge.title,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? badge.color.withOpacity(0.9)
                      : GlimpseColors.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            
            // Check icon (quando selecionado)
            if (isSelected) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check_circle,
                color: badge.color,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
