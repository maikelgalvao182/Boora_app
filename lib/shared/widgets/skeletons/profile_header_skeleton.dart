import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Widget skeleton para o header do perfil
class ProfileHeaderSkeleton extends StatelessWidget {
  const ProfileHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Avatar skeleton
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: GlimpseColors.lightTextField,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 12),
        
        // Nome skeleton
        Container(
          width: 150,
          height: 20,
          decoration: BoxDecoration(
            color: GlimpseColors.lightTextField,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 16),
        
        // Chips skeleton
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 31,
              decoration: BoxDecoration(
                color: GlimpseColors.lightTextField,
                borderRadius: BorderRadius.circular(15.5),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 80,
              height: 31,
              decoration: BoxDecoration(
                color: GlimpseColors.lightTextField,
                borderRadius: BorderRadius.circular(15.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}