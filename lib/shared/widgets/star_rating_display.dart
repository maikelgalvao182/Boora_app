import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Display read-only de rating com estrelas + nota
/// 
/// Mostra:
/// - Estrelas preenchidas/vazias baseado no rating
/// - Nota numérica opcional (0.0 - 5.0)
class StarRatingDisplay extends StatelessWidget {
  
  const StarRatingDisplay({
    required this.rating, 
    super.key,
    this.size = 16,
    this.showNumber = true,
    this.color,
    this.emptyColor,
    this.mainAxisSize = MainAxisSize.min,
  });
  
  final double rating; // 0.0 - 5.0
  final double size;
  final bool showNumber;
  final Color? color;
  final Color? emptyColor;
  final MainAxisSize mainAxisSize;
  
  @override
  Widget build(BuildContext context) {
    final starColor = color ?? const Color(0xFFFFB800); // Dourado
    final emptyStarColor = emptyColor ?? Colors.grey[300]!;
    
    return Row(
      mainAxisSize: mainAxisSize,
      children: [
        // Estrelas
        ...List.generate(5, (index) {
          final starValue = index + 1;
          final isFilled = rating >= starValue;
          final isPartiallyFilled = rating > index && rating < starValue;
          
          return Icon(
            isFilled ? Icons.star : (isPartiallyFilled ? Icons.star_half : Icons.star_border),
            size: size,
            color: (isFilled || isPartiallyFilled) ? starColor : emptyStarColor,
          );
        }),
        
        // Nota numérica
        if (showNumber) ...[
          SizedBox(width: size * 0.4),
          Text(
            rating.toStringAsFixed(1),
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              fontSize: size * 0.875,
              fontWeight: FontWeight.w600,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ],
      ],
    );
  }
}
