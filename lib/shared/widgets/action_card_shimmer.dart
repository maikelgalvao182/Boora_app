import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer placeholder para ActionCard
/// 
/// Replica a estrutura visual do ActionCard com efeito shimmer
class ActionCardShimmer extends StatelessWidget {
  const ActionCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GlimpseColors.lightTextField,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar shimmer
          Shimmer.fromColors(
            baseColor: GlimpseColors.lightTextField,
            highlightColor: Colors.white,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: GlimpseColors.lightTextField,
                shape: BoxShape.circle,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Conteúdo shimmer
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Texto principal (2 linhas)
                Shimmer.fromColors(
                  baseColor: GlimpseColors.lightTextField,
                  highlightColor: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 15,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: GlimpseColors.lightTextField,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 15,
                        width: 180,
                        decoration: BoxDecoration(
                          color: GlimpseColors.lightTextField,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Tempo relativo
                Shimmer.fromColors(
                  baseColor: GlimpseColors.lightTextField,
                  highlightColor: Colors.white,
                  child: Container(
                    height: 13,
                    width: 80,
                    decoration: BoxDecoration(
                      color: GlimpseColors.lightTextField,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Botões shimmer
                Row(
                  children: [
                    Expanded(
                      child: Shimmer.fromColors(
                        baseColor: GlimpseColors.lightTextField,
                        highlightColor: Colors.white,
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: GlimpseColors.lightTextField,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Shimmer.fromColors(
                        baseColor: GlimpseColors.lightTextField,
                        highlightColor: Colors.white,
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: GlimpseColors.lightTextField,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
