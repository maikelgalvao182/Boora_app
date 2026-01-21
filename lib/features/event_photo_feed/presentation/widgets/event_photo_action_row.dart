import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

class EventPhotoActionRow extends StatelessWidget {
  const EventPhotoActionRow({
    super.key,
    required this.onPickImage,
  });

  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onPickImage,
          icon: const Icon(
            IconsaxPlusLinear.gallery,
            color: GlimpseColors.textSubTitle,
          ),
        ),
        IconButton(
          onPressed: null,
          icon: const Icon(
            IconsaxPlusLinear.camera,
            color: GlimpseColors.textSubTitle,
          ),
        ),
        IconButton(
          onPressed: null,
          icon: const Icon(
            IconsaxPlusLinear.location,
            color: GlimpseColors.textSubTitle,
          ),
        ),
      ],
    );
  }
}
