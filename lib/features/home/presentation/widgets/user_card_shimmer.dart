import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer placeholder para UserCard
class UserCardShimmer extends StatelessWidget {
  const UserCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GlimpseColors.lightTextField,
          width: 1,
        ),
      ),
      child: Shimmer.fromColors(
        baseColor: GlimpseColors.lightTextField,
        highlightColor: Colors.white,
        child: Row(
          children: [
            // Avatar shimmer
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: GlimpseColors.lightTextField,
                shape: BoxShape.circle,
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Textos shimmer
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: GlimpseColors.lightTextField,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 120,
                    height: 14,
                    decoration: BoxDecoration(
                      color: GlimpseColors.lightTextField,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
