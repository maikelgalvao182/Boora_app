import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer placeholder para ListCard
class ListCardShimmer extends StatelessWidget {
  const ListCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Topo: Emoji Avatar + Texto
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Emoji Avatar Placeholder
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: GlimpseColors.lightTextField,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                
                // Texto Placeholder (3 linhas)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Container(
                        height: 14,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: GlimpseColors.lightTextField,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 14,
                        width: 200,
                        decoration: BoxDecoration(
                          color: GlimpseColors.lightTextField,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 14,
                        width: 120,
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
            
            const SizedBox(height: 16),
            
            // Base: Participantes Empilhados
            SizedBox(
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Avatar 1
                  Positioned(
                    left: 0,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: GlimpseColors.lightTextField,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  // Avatar 2
                  Positioned(
                    left: 28,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: GlimpseColors.lightTextField,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  // Avatar 3
                  Positioned(
                    left: 56,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: GlimpseColors.lightTextField,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
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
