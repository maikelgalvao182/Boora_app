import 'dart:async';
import 'dart:io';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/image_source_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Componente para upload de foto de perfil estilo Glimpse
class GlimpsePhotoUploader extends StatefulWidget {

  const GlimpsePhotoUploader({
    required this.imageFile, required this.onImageSelected, super.key,
    this.size = 150,
    this.placeholder = '',
    this.customIcon,
  });
  final File? imageFile;
  final Function(File) onImageSelected;
  final double size;
  final String placeholder;
  final Widget? customIcon;

  @override
  State<GlimpsePhotoUploader> createState() => _GlimpsePhotoUploaderState();
}

class _GlimpsePhotoUploaderState extends State<GlimpsePhotoUploader> {
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    debugPrint('[GlimpsePhotoUploader] 🏗️ Building widget - processing: $_processing, hasImage: ${widget.imageFile != null}');
    
    return GestureDetector(
      onTap: _processing ? null : () {
        debugPrint('[GlimpsePhotoUploader] 👆 Tapped - showing image source dialog');
        _showImageSourceDialog(context);
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: GlimpseColors.lightTextField,
          shape: BoxShape.circle,
          image: widget.imageFile != null
              ? DecorationImage(
                  image: FileImage(widget.imageFile!),
                  fit: BoxFit.cover,
                )
              : const DecorationImage(
                  image: AssetImage('assets/images/empty_avatar.jpg'),
                  fit: BoxFit.cover,
                ),
        ),
        child: Stack(
          children: [
            if (widget.imageFile != null)
              Positioned(
                bottom: 0,
                right: 20.w,
                child: Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: GlimpseColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2.w,
                    ),
                  ),
                  child: Icon(
                    IconsaxPlusBold.edit_2,
                    color: Colors.white,
                    size: 20.sp,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showImageSourceDialog(BuildContext context) async {
    debugPrint('[GlimpsePhotoUploader] 📱 Showing image source dialog');
    
    setState(() => _processing = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        builder: (BuildContext context) {
          return ImageSourceBottomSheet(
            onImageSelected: (file) {
              widget.onImageSelected(file);
              if (mounted) setState(() => _processing = false);
            },
            cropToSquare: true,
            requireCrop: true,
            minWidth: 800,
            minHeight: 800,
            quality: 85,
          );
        },
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }
}
