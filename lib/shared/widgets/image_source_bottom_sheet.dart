import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:partiu/common/services/image_crop_service.dart';
import 'package:partiu/common/services/image_picker_service.dart';
import 'package:partiu/common/utils/app_logger.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/image_compress_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:go_router/go_router.dart';

/// Bottom sheet compartilhável para seleção de imagem (câmera ou galeria)
/// 
/// Usado em:
/// - Upload de foto de perfil (GlimpsePhotoUploader)
/// - Envio de imagem em chat
/// 
/// Features:
/// - Crop automático para quadrado (opcional)
/// - Compressão de imagem
/// - Callback com arquivo processado
class ImageSourceBottomSheet extends StatefulWidget {
  const ImageSourceBottomSheet({
    required this.onImageSelected,
    super.key,
    this.cropToSquare = true,
    this.requireCrop = false,
    this.minWidth = 800,
    this.minHeight = 800,
    this.quality = 85,
  });

  final Function(File) onImageSelected;
  final bool cropToSquare;
  final bool requireCrop;
  final int minWidth;
  final int minHeight;
  final int quality;

  @override
  State<ImageSourceBottomSheet> createState() => _ImageSourceBottomSheetState();
}

class _ImageSourceBottomSheetState extends State<ImageSourceBottomSheet> {
  bool _processing = false;
  final ImagePickerService _pickerService = ImagePickerService();
  final ImageCropService _cropService = ImageCropService();
  final ImageCompressService _compressService = const ImageCompressService();

  Future<File?> _resolveXFileToLocalFile(XFile xfile) async {
    try {
      final candidate = File(xfile.path);
      if (await candidate.exists()) {
        return candidate;
      }

      // Fallback: em alguns devices/versões do Android, o picker pode retornar
      // um path não resolvível como arquivo (ex.: content://...).
      // Copiamos o conteúdo para um arquivo temporário local antes de cropar.
      final bytes = await xfile.readAsBytes();
      final tmp = File(
        '${Directory.systemTemp.path}/picked_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tmp.writeAsBytes(bytes, flush: true);
      if (await tmp.exists()) {
        AppLogger.info(
          '[ImageSourceBottomSheet] XFile resolved to temp file: ${tmp.path}',
        );
        return tmp;
      }

      AppLogger.error(
        '[ImageSourceBottomSheet] Failed to create temp file from XFile: ${xfile.path}',
      );
      return null;
    } catch (e, stackTrace) {
      AppLogger.error(
        '[ImageSourceBottomSheet] Error resolving XFile to local File: $e',
        e,
        stackTrace,
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                i18n.translate('select_photo'),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildOptionButton(
                    context,
                    icon: IconsaxPlusLinear.camera,
                    label: i18n.translate('camera'),
                    onTap: () async {
                      if (_processing) return;
                      setState(() => _processing = true);
                      try {
                        final selected = await _getImageFromCamera();
                        if (context.mounted && selected) context.pop();
                      } finally {
                        if (mounted) setState(() => _processing = false);
                      }
                    },
                  ),
                  _buildOptionButton(
                    context,
                    icon: IconsaxPlusLinear.gallery,
                    label: i18n.translate('gallery'),
                    onTap: () async {
                      if (_processing) return;
                      setState(() => _processing = true);
                      try {
                        final selected = await _getImageFromGallery();
                        if (context.mounted && selected) context.pop();
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
      ),
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
          SizedBox(height: 8.h),
          Text(
            label,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 16.sp,
              fontWeight: FontWeight.w400,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _getImageFromCamera() async {
    AppLogger.info('[ImageSourceBottomSheet] Starting camera image picker');
    try {
      final xfile = await _pickerService.pickImage(ImageSource.camera);
      if (xfile == null || !mounted) return false;

      final file = await _resolveXFileToLocalFile(xfile);
      if (file == null || !await file.exists()) {
        AppLogger.error(
          '[ImageSourceBottomSheet] Picked camera image is not accessible: ${xfile.path}',
        );
        return false;
      }

      return await _cropAndSelectImage(file);
    } catch (e) {
      AppLogger.error('[ImageSourceBottomSheet] Error picking camera image: $e');
      return false;
    }
  }

  Future<bool> _getImageFromGallery() async {
    AppLogger.info('[ImageSourceBottomSheet] Starting gallery image picker');
    try {
      final xfile = await _pickerService.pickImage(ImageSource.gallery);
      if (xfile == null || !mounted) return false;

      final file = await _resolveXFileToLocalFile(xfile);
      if (file == null || !await file.exists()) {
        AppLogger.error(
          '[ImageSourceBottomSheet] Picked gallery image is not accessible: ${xfile.path}',
        );
        return false;
      }

      return await _cropAndSelectImage(file);
    } catch (e) {
      AppLogger.error('[ImageSourceBottomSheet] Error picking gallery image: $e');
      return false;
    }
  }

  Future<bool> _cropAndSelectImage(File imageFile) async {
    AppLogger.info('[ImageSourceBottomSheet] Starting image processing...');
    var processed = false;
    try {
      File? processedFile = imageFile;

      // 1. Crop se necessário
      if (widget.cropToSquare) {
        final cropped = await _cropService.cropToSquare(imageFile);
        processed = true;

        if (cropped != null) {
          processedFile = cropped;
        } else {
          AppLogger.warning('[ImageSourceBottomSheet] Image crop was cancelled');

          if (widget.requireCrop) {
            if (!mounted) return false;

            final i18n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  i18n.translate('image_crop_cancelled').isNotEmpty
                      ? i18n.translate('image_crop_cancelled')
                      : 'Recorte cancelado',
                ),
              ),
            );
            return false;
          }
        }
      }

      // 2. Comprime a imagem
      AppLogger.info('[ImageSourceBottomSheet] Compressing image...');
      final compressed = await _compressService.compressFileToTempFile(
        processedFile,
        minWidth: widget.minWidth,
        minHeight: widget.minHeight,
        quality: widget.quality,
      );

      AppLogger.info('[ImageSourceBottomSheet] Image processed successfully');
      widget.onImageSelected(compressed);
      return true;
    } catch (e) {
      AppLogger.error('[ImageSourceBottomSheet] Error processing image: $e');
      if (!processed) {
        // Se falhou no crop, tenta comprimir a original
        try {
          final compressed = await _compressService.compressFileToTempFile(
            imageFile,
            minWidth: widget.minWidth,
            minHeight: widget.minHeight,
            quality: widget.quality,
          );
          widget.onImageSelected(compressed);
          return true;
        } catch (e2) {
          AppLogger.error('[ImageSourceBottomSheet] Error compressing fallback image: $e2');
          // Como último recurso, usa a imagem original
          widget.onImageSelected(imageFile);
          return true;
        }
      }

      return false;
    }
  }
}
