import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:share_plus/share_plus.dart';

/// Botão circular para compartilhar o app via sistema nativo
class WhatsAppShareButton extends StatelessWidget {
  const WhatsAppShareButton({super.key});

  Future<void> _shareApp(BuildContext context) async {
    final i18n = AppLocalizations.of(context);
    const String appUrl = BOORA_APP_STORE_URL;
    final String shareMessage = i18n.translate('share_app_message');
    final String message = '$shareMessage\n\n$appUrl';
    
    try {
      // Obtém a posição do botão para o popover no iPad/iOS
      final box = context.findRenderObject() as RenderBox?;
      final sharePositionOrigin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      
      await Share.share(
        message,
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      debugPrint('Erro ao compartilhar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8.r,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () => _shareApp(context),
        customBorder: const CircleBorder(),
        child: Container(
          width: 56.w,
          height: 56.h,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 4.h),
              child: SvgPicture.asset(
                'assets/svg/forward.svg',
                width: 28.w,
                height: 28.h,
                colorFilter: const ColorFilter.mode(
                  GlimpseColors.primary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
