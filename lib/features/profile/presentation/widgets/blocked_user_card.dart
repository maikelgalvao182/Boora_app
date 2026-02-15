import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

/// Card para exibir usuário bloqueado
/// 
/// Exibe:
/// - Avatar (StableAvatar)
/// - fullName
/// - from (localização)
/// - Botão "Desbloquear" com fundo vermelho claro
class BlockedUserCard extends StatelessWidget {
  const BlockedUserCard({
    required this.userId,
    required this.fullName,
    required this.onUnblock,
    this.from,
    this.photoUrl,
    super.key,
  });

  final String userId;
  final String fullName;
  final String? from;
  final String? photoUrl;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final unblockLabel = i18n.translate('unblock');
    final isCompactScreen = MediaQuery.sizeOf(context).width <= 360;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          StableAvatar(
            userId: userId,
            photoUrl: photoUrl,
            size: 58.w,
            borderRadius: BorderRadius.circular(8.r),
            enableNavigation: false, // Desabilitado para usuários bloqueados
          ),
          
          SizedBox(width: 12.w),
          
          // Informações
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Nome completo
                ReactiveUserNameWithBadge(
                  userId: userId,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: (isCompactScreen ? 14 : 15).sp,
                    fontWeight: FontWeight.w700,
                    color: GlimpseColors.primaryColorLight,
                  ),
                ),
                
                // Localização
                if (from != null && from!.isNotEmpty) ...[
                  SizedBox(height: 4.h),
                  Text(
                    from!,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: (isCompactScreen ? 12 : 13).sp,
                      fontWeight: FontWeight.w500,
                      color: GlimpseColors.textSubTitle,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          
          SizedBox(width: 12.w),
          
          // Botão Desbloquear
          TextButton(
            onPressed: onUnblock,
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              backgroundColor: const Color(0xFFFFEBEE), // Vermelho clarinho
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              unblockLabel.isNotEmpty ? unblockLabel : 'Desbloquear',
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: (isCompactScreen ? 12 : 13).sp,
                fontWeight: FontWeight.w600,
                color: GlimpseColors.dangerRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
