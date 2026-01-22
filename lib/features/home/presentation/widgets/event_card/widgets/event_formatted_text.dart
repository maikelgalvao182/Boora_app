import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget burro que exibe texto formatado de um evento
/// 
/// Exemplo: "João quer 🎉 jogar futebol em Parque Ibirapuera dia 15/12 às 18:00"
class EventFormattedText extends StatelessWidget {
  const EventFormattedText({
    required this.fullName,
    required this.activityText,
    required this.locationName,
    required this.dateText,
    required this.timeText,
    required this.onLocationTap,
    this.emoji,
    super.key,
  });

  final String fullName;
  final String activityText;
  final String locationName;
  final String dateText;
  final String timeText;
  final VoidCallback onLocationTap;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    final baseStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    );

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: baseStyle.copyWith(color: GlimpseColors.textSubTitle),
        children: [
          // Nome do criador (só se não vazio)
          if (fullName.isNotEmpty) ...[
            TextSpan(
              text: fullName,
              style: baseStyle.copyWith(color: GlimpseColors.primary),
            ),
            
            // Conectivo
            TextSpan(text: ' ${i18n.translate('event_formatted_wants')} '),
          ],
          
          // "quer" quando fullName está vazio (nome no header)
          if (fullName.isEmpty) ...[
            TextSpan(text: '${i18n.translate('event_formatted_wants')} '),
          ],
          
          // Atividade
          TextSpan(
            text: activityText,
            style: baseStyle.copyWith(color: GlimpseColors.primaryColorLight),
          ),
          
          // Emoji à direita do activity (se fornecido)
          if (emoji != null) ...[
            TextSpan(text: ' $emoji'),
          ],
          
          // Local (clicável, sem sublinhado)
          if (locationName.isNotEmpty) ...[
            TextSpan(text: ' ${i18n.translate('event_formatted_in')} '),
            TextSpan(
              text: locationName,
              style: baseStyle.copyWith(color: GlimpseColors.primary),
              recognizer: TapGestureRecognizer()..onTap = onLocationTap,
            ),
          ],
          
          // Data
          if (dateText.isNotEmpty) ...[
            TextSpan(text: dateText.startsWith('dia ') ? ' no ' : ' '),
            TextSpan(text: dateText),
          ],
          
          // Horário
          if (timeText.isNotEmpty) ...[
            TextSpan(text: ' ${i18n.translate('event_formatted_at')} '),
            TextSpan(text: timeText),
          ],
        ],
      ),
    );
  }
}
