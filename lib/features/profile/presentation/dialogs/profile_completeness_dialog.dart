import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:partiu/shared/widgets/profile_completeness_ring.dart';

/// Bottom-sheet content que exibe o progresso de completude do perfil
/// e permite navegar para edição ou dispensar permanentemente
class ProfileCompletenessDialog extends StatelessWidget {
  const ProfileCompletenessDialog({
    required this.onEditProfile,
    required this.onDontShow,
    super.key,
    this.photoUrl,
    this.percentage, // Percentual de completude (0-100)
    this.title,
    this.subtitle,
  });

  final VoidCallback onEditProfile;
  final VoidCallback onDontShow;
  final String? photoUrl;
  final int? percentage; // Percentual de completude (0-100)
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.close, size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // User avatar com Progress Ring
            ProfileCompletenessRing(
              size: 90,
              strokeWidth: 4,
              percentage: percentage ?? 0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: photoUrl != null && photoUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photoUrl!,
                        width: 82,
                        height: 82,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 82,
                          height: 82,
                          color: GlimpseColors.lightTextField,
                          child: const Icon(Icons.person, size: 40, color: Colors.grey),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 82,
                          height: 82,
                          color: GlimpseColors.lightTextField,
                          child: const Icon(Icons.person, size: 40, color: Colors.grey),
                        ),
                      )
                    : Container(
                        width: 82,
                        height: 82,
                        color: GlimpseColors.lightTextField,
                        child: const Icon(Icons.person, size: 40, color: Colors.grey),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Title
            Text(
              title ?? i18n.translate('complete_your_profile'),
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            
            // Message with highlighted percentage
            _buildMessageWithHighlight(
              context,
              subtitle ?? i18n.translate('profile_completeness_subtitle'),
            ),
            const SizedBox(height: 24),
            
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDontShow,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: GlimpseColors.borderColorLight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      i18n.translate('dont_show'),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onEditProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GlimpseColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: Text(
                      i18n.translate('edit_profile_button'),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds message with percentage highlighted in actionColor
  Widget _buildMessageWithHighlight(BuildContext context, String message) {
    // Regex para capturar o número seguido de %
    final percentageRegex = RegExp(r'(\d+)%');
    final match = percentageRegex.firstMatch(message);
    
    final baseStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: GlimpseColors.textSubTitle,
    );
    
    if (match == null) {
      // Se não houver porcentagem, retorna mensagem normal
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          message,
          style: baseStyle,
          textAlign: TextAlign.center,
        ),
      );
    }
    
    final percentageText = match.group(0)!; // Ex: "75%"
    final beforePercentage = message.substring(0, match.start);
    final afterPercentage = message.substring(match.end);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: beforePercentage),
            TextSpan(
              text: percentageText,
              style: const TextStyle(
                color: GlimpseColors.actionColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: afterPercentage),
          ],
        ),
      ),
    );
  }
}
