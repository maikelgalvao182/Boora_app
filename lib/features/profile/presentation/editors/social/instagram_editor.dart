import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Editor para campo Instagram
/// Permite editar o nome de usuário do Instagram (sem @)
class InstagramEditor extends StatelessWidget {
  const InstagramEditor({
    required this.controller,
    super.key,
  });

  final TextEditingController controller;

  /// Validação do nome de usuário do Instagram
  /// - Não pode conter @ 
  /// - Não pode conter URLs (http/https)
  /// - Apenas letras, números, pontos e underscores
  String? _validateUsername(String? value) {
    if (value == null || value.isEmpty) return null; // Opcional
    
    // Verifica se contém @
    if (value.contains('@')) {
      return 'Não inclua o @ no nome de usuário';
    }
    
    // Verifica se é uma URL
    if (value.contains('http://') || value.contains('https://') || value.contains('www.')) {
      return 'Insira apenas o nome de usuário, não a URL';
    }
    
    // Verifica caracteres válidos do Instagram
    // Instagram permite: letras, números, ponto e underscore
    final usernameRegex = RegExp(r'^[a-zA-Z0-9._]+$');
    if (!usernameRegex.hasMatch(value)) {
      return 'Use apenas letras, números, pontos e underscores';
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlimpseTextField(
          labelText: i18n.translate('instagram_username_label'),
          hintText: i18n.translate('instagram_placeholder'),
          controller: controller,
          keyboardType: TextInputType.text,
          maxLines: 1,
          labelStyle: GlimpseStyles.fieldLabelStyle(
            color: Theme.of(context).textTheme.titleMedium?.color,
          ),
          inputFormatters: [
            // Remove @ automaticamente se digitado
            FilteringTextInputFormatter.deny(RegExp(r'@')),
            // Remove espaços
            FilteringTextInputFormatter.deny(RegExp(r'\s')),
          ],
          validator: _validateUsername,
        ),
        const SizedBox(height: 8),
        // Texto helper abaixo do input
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            i18n.translate('instagram_helper'),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ),
      ],
    );
  }
}
