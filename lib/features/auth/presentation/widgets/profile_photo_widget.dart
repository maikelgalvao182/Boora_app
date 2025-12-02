import 'dart:io';

import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_photo_uploader.dart';
import 'package:partiu/shared/widgets/svg_icon.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

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
        const SizedBox(height: 15),
        
        // Seletor de foto
        Center(
          child: GlimpsePhotoUploader(
            imageFile: imageFile,
            onImageSelected: onImageSelected,
            size: 180,
            placeholder: i18n.translate('add_photo'),
            customIcon: const SvgIcon(
              'assets/svg/camera.svg',
              width: 45,
              height: 45,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ),
        
        const SizedBox(height: 20),
        Text(
          i18n.translate('tap_to_select_photo'),
          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
            fontSize: 16,
            color: GlimpseColors.textSubTitle,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
