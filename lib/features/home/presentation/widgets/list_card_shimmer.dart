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
      height: 160,
      decoration: BoxDecoration(
        color: GlimpseColors.lightTextField,
        borderRadius: BorderRadius.circular(16), 
      ),
      child: Shimmer.fromColors(
        baseColor: GlimpseColors.lightTextField,
        highlightColor: Colors.white,
        child: Container(
          decoration: BoxDecoration(
            color: GlimpseColors.lightTextField,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
