import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax/iconsax.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/features/profile/data/services/visits_service.dart';
import 'package:partiu/shared/widgets/typing_indicator.dart';

/// Widget chip que exibe o contador de visitas ao perfil.
class ProfileVisitsChip extends StatelessWidget {
  const ProfileVisitsChip({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final userId = AppState.currentUserId ?? '';
    final isCompactScreen = MediaQuery.sizeOf(context).width <= 360;
    
    if (kDebugMode) {
      debugPrint('🎨 [ProfileVisitsChip] build chamado com userId: $userId');
    }
    
    // Show skeleton only if user not loaded yet
    if (userId.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ [ProfileVisitsChip] userId vazio, mostrando skeleton');
      }
      return _buildSkeletonChip();
    }

    final visitsService = VisitsService.instance;
    if (kDebugMode) {
      debugPrint('📊 [ProfileVisitsChip] Cache atual: ${visitsService.cachedVisitsCount}');
    }

    return GestureDetector(
      onTap: () => GoRouter.of(context).push(AppRoutes.profileVisits),
      child: Container(
        height: 31.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: GlimpseColors.visitsChipBackground,
          borderRadius: BorderRadius.circular(30.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Iconsax.eye,
              size: 16.sp,
              color: Colors.black,
            ),
            SizedBox(width: 6.w),
            Text(
              i18n.translate('profile_visits'),
              style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: (isCompactScreen ? 11 : 12).sp,
              ),
            ),
            SizedBox(width: 4.w),
            StreamBuilder<int>(
              stream: visitsService.watchUserVisitsCount(userId),
              initialData: visitsService.cachedVisitsCount,
              builder: (context, snapshot) {
                if (kDebugMode) {
                  debugPrint('🔄 [ProfileVisitsChip] StreamBuilder update:');
                  debugPrint('   - connectionState: ${snapshot.connectionState}');
                  debugPrint('   - hasData: ${snapshot.hasData}');
                  debugPrint('   - data: ${snapshot.data}');
                  debugPrint('   - hasError: ${snapshot.hasError}');
                  if (snapshot.hasError) {
                    debugPrint('   - error: ${snapshot.error}');
                  }
                }
                
                final visits = snapshot.data ?? 0;
                if (kDebugMode) {
                  debugPrint('   - visits (final): $visits');
                }

                // Mostra loading se ainda está conectando E não tem cache válido
                final isLoading = snapshot.connectionState == ConnectionState.waiting &&
                    (visitsService.cachedVisitsCount == null || !visitsService.hasLoadedOnce);

                if (isLoading) {
                  return Padding(
                    padding: EdgeInsets.only(left: 2.w, right: 2.w),
                    child: TypingIndicator(
                      dotSize: 4.w,
                      color: Colors.black,
                    ),
                  );
                }

                return Text(
                  visits.toString(),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: (isCompactScreen ? 11 : 12).sp,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSkeletonChip() {
    return Container(
      width: 80.w,
      height: 31.h,
      decoration: BoxDecoration(
        color: GlimpseColors.lightTextField,
        borderRadius: BorderRadius.circular(15.5.r),
      ),
    );
  }
}
