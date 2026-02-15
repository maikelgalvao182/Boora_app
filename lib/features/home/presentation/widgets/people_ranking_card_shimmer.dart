import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer loading para PeopleRankingCard
/// Replica EXATAMENTE a estrutura e espaçamentos do card real
class PeopleRankingCardShimmer extends StatelessWidget {
  const PeopleRankingCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: GlimpseColors.lightTextField,
          width: 1.w,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.r),
        child: Shimmer.fromColors(
          baseColor: GlimpseColors.lightTextField,
          highlightColor: Colors.white,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 58.w,
                height: 58.h,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8.r),
                ),
              ),
              
              SizedBox(width: 12.w),
              
              // Informações
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nome
                    Container(
                      width: double.infinity,
                      height: 18.h,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    ),
                    
                    SizedBox(height: 4.h),
                    
                    // Localização
                    Container(
                      width: 140.w,
                      height: 14.h,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    ),
                    
                    SizedBox(height: 4.h),
                    
                    // Rating summary
                    Container(
                      width: 200.w,
                      height: 14.h,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Posição
              Container(
                width: 28.w,
                height: 28.h,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6.r),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

