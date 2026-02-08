import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Badge com estrela e rating
/// 
/// ✅ const constructor para evitar rebuilds desnecessários
class StarBadge extends StatelessWidget {
  const StarBadge({
    required this.rating,
    super.key,
  });

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: GlimpseColors.bgColorLight,
        borderRadius: BorderRadius.circular(100.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Iconsax.star1,
            size: 16,
            color: Color(0xFFFFB800),
          ),
          SizedBox(width: 3.w),
          Text(
            rating.toStringAsFixed(1),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: GlimpseColors.primaryColorLight,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
