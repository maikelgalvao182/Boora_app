import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Step de comentário opcional (Step 2)
class CommentStep extends StatelessWidget {
  final TextEditingController controller;

  const CommentStep({
    required this.controller,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título
        Text(
          'Quer deixar um comentário?',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: GlimpseColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        
        // Subtítulo
        Text(
          'Compartilhe mais detalhes sobre sua experiência (opcional)',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: GlimpseColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        
        // Campo de texto
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: TextField(
            controller: controller,
            maxLines: 6,
            maxLength: 500,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: GlimpseColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Ex: Foi uma experiência incrível! A pessoa é muito...',
              hintStyle: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: GlimpseColors.textSecondary.withOpacity(0.6),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              counterStyle: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: GlimpseColors.textSecondary,
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Dica
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: GlimpseColors.info.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: GlimpseColors.info,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Seu comentário será público e ajudará outros usuários',
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: GlimpseColors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
