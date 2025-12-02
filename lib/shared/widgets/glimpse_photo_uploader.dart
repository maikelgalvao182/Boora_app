import 'dart:async';
import 'dart:io';
import 'package:partiu/common/services/image_crop_service.dart';
import 'package:partiu/common/services/image_picker_service.dart';
import 'package:partiu/common/utils/app_logger.dart';
import 'package:partiu/core/services/image_compress_service.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:go_router/go_router.dart';

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
  final ImagePickerService _pickerService = ImagePickerService();
  final ImageCropService _cropService = ImageCropService();
  final ImageCompressService _compressService = const ImageCompressService();

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
          border: Border.all(
            color: GlimpseColors.borderColorLight,
          ),
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
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GlimpseColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    IconsaxPlusBold.edit_2,
                    color: Colors.white,
                    size: 20,
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
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context).translate('select_photo'),
                  style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: GlimpseColors.textSubTitle,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildOptionButton(
                      context,
                      icon: IconsaxPlusLinear.camera,
                      label: AppLocalizations.of(context).translate('camera'),
                      onTap: () async {
                        if (_processing) return;
                        context.pop();
                        await Future.delayed(const Duration(milliseconds: 80));
                        if (!mounted) return;
                        setState(() => _processing = true);
                        try {
                          await _getImageFromCamera();
                        } finally {
                          if (mounted) setState(() => _processing = false);
                        }
                      },
                    ),
                    _buildOptionButton(
                      context,
                      icon: IconsaxPlusLinear.gallery,
                      label: AppLocalizations.of(context).translate('gallery'),
                      onTap: () async {
                        if (_processing) return;
                        context.pop();
                        await Future.delayed(const Duration(milliseconds: 80));
                        if (!mounted) return;
                        setState(() => _processing = true);
                        try {
                          await _getImageFromGallery();
                        } finally {
                          if (mounted) setState(() => _processing = false);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
  onTap: _processing ? null : onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: GlimpseColors.lightTextField,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: GlimpseColors.primaryColorLight,
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _getImageFromCamera() async {
    AppLogger.info('[GlimpsePhotoUploader] [GREEN] Starting camera image picker');
    try {
      final xfile = await _pickerService.pickImage(ImageSource.camera);
      if (xfile == null || !mounted) return;
      
      final file = File(xfile.path);
      await _cropAndSelectImage(file);
    } catch (e) {
      AppLogger.error('[GlimpsePhotoUploader] Error picking camera image: $e');
    }
  }

  Future<void> _getImageFromGallery() async {
    AppLogger.info('[GlimpsePhotoUploader] [GREEN] Starting gallery image picker');
    debugPrint('[GlimpsePhotoUploader] 🖼️ _getImageFromGallery called');
    
    try {
      debugPrint('[GlimpsePhotoUploader] 📸 Calling pickImage service...');
      final xfile = await _pickerService.pickImage(ImageSource.gallery);
      if (xfile == null || !mounted) return;
      
      final file = File(xfile.path);
      await _cropAndSelectImage(file);
    } catch (e) {
      AppLogger.error('[GlimpsePhotoUploader] Error picking gallery image: $e');
    }
  }

  Future<void> _cropAndSelectImage(File imageFile) async {
    AppLogger.info('[GlimpsePhotoUploader] 🟡 Starting image cropper and compression...');
    var processed = false;
    try {
      // 1. Primeiro faz o crop para quadrado
      final cropped = await _cropService.cropToSquare(imageFile);
      processed = true;
      
      if (cropped != null) {
        // 2. Depois comprime a imagem cropada
        AppLogger.info('[GlimpsePhotoUploader] 🔧 Compressing cropped image...');
        final compressed = await _compressService.compressFileToTempFile(
          cropped,
          minWidth: 800,
          minHeight: 800,
          quality: 85,
        );
        
        AppLogger.info('[GlimpsePhotoUploader] ✅ Image processed successfully');
        widget.onImageSelected(compressed);
      } else {
        AppLogger.warning('[GlimpsePhotoUploader] Image crop was cancelled');
      }
    } catch (e) {
      AppLogger.error('[GlimpsePhotoUploader] Error processing image: $e');
      if (!processed) {
        // Se falhou no crop, pelo menos tenta comprimir a original
        try {
          final compressed = await _compressService.compressFileToTempFile(
            imageFile,
            minWidth: 800,
            minHeight: 800,
            quality: 85,
          );
          widget.onImageSelected(compressed);
        } catch (e2) {
          AppLogger.error('[GlimpsePhotoUploader] Error compressing fallback image: $e2');
          // Como último recurso, usa a imagem original
          widget.onImageSelected(imageFile);
        }
      }
    }
  }
}
