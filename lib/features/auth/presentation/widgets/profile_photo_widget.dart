import 'dart:io';

import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_photo_uploader.dart';
import 'package:partiu/shared/widgets/svg_icon.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Widget de seleção de foto de perfil
/// Extraído de TelaFotoPerfil para reutilização no wizard
class ProfilePhotoWidget extends StatelessWidget {
  const ProfilePhotoWidget({
    required this.imageFile,
    required this.onImageSelected,
    super.key,
  });

  final File? imageFile;
  final ValueChanged<File?> onImageSelected;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Column(
      children: [
        SizedBox(height: 15.h),
        
        // Seletor de foto
        Center(
          child: GlimpsePhotoUploader(
            imageFile: imageFile,
            onImageSelected: onImageSelected,
            size: 180.w,
            placeholder: i18n.translate('add_photo'),
            customIcon: SvgIcon(
              'assets/svg/camera.svg',
              width: 45.w,
              height: 45.h,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ),
        
        SizedBox(height: 20.h),
        Text(
          i18n.translate('tap_to_select_photo'),
          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
            fontSize: 16.sp,
            color: GlimpseColors.textSubTitle,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
