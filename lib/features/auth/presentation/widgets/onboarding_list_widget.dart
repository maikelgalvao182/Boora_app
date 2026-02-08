import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class OnboardingListWidget extends StatelessWidget {
  final bool isBride;

  const OnboardingListWidget({
    super.key,
    required this.isBride,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    // Cores vibrantes para cada card
    final cardColors = [
      [const Color(0xFFFF6B9D), const Color(0xFFFF8FB3)], // Rosa vibrante
      [const Color(0xFF66BB6A), const Color(0xFF81C784)], // Verde claro
      [const Color(0xFFFFA726), const Color(0xFFFFCA28)], // Laranja dourado
      [const Color(0xFF26C6DA), const Color(0xFF4DD0E1)], // Ciano
    ];

    // Seleciona as traduções baseadas no tipo de usuário
    final titleKey = isBride ? 'onboarding_grid_title' : 'onboarding_vendor_grid_title';
    final subtitleKey = isBride ? 'onboarding_grid_subtitle' : 'onboarding_vendor_grid_subtitle';
    final stepPrefix = isBride ? 'onboarding_step_' : 'onboarding_vendor_step_';

    final cardsData = [
      i18n.translate('${stepPrefix}1'),
      i18n.translate('${stepPrefix}2'),
      i18n.translate('${stepPrefix}3'),
      i18n.translate('${stepPrefix}4'),
    ];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título principal - DOBRADO O TAMANHO
          Text(
            i18n.translate(titleKey),
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              color: GlimpseColors.textSubTitle,
              fontSize: 56.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: -2,
              height: 1.1,
            ),
          ),
          SizedBox(height: 16.h),
          // Subtítulo
          Text(
            i18n.translate(subtitleKey),
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              color: GlimpseColors.textSubTitle.withValues(alpha: 0.7),
              fontSize: 16.sp,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.3,
              height: 1.4,
            ),
          ),
          SizedBox(height: 32.h),
          // Grid de cards 2x2
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12.w,
              mainAxisSpacing: 12.h,
              childAspectRatio: 1,
            ),
            itemCount: cardsData.length,
            itemBuilder: (context, index) {
              final text = cardsData[index];
              final colors = cardColors[index];
              final number = (index + 1).toString().padLeft(2, '0');
              
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16.r),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors[0].withValues(alpha: 0.3),
                      blurRadius: 12.r,
                      offset: Offset(0, 4.h),
                    ),
                  ],
                ),
                padding: EdgeInsets.all(16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Número no topo
                    Text(
                      number,
                      style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                        color: Colors.black.withValues(alpha: 0.9),
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    // Texto descritivo
                    Text(
                      text,
                      style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                        color: Colors.black.withValues(alpha: 0.95),
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
