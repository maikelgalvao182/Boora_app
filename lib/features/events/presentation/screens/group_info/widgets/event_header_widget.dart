import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/event_emoji_avatar.dart';

/// Widget do cabeçalho do evento
/// Exibe emoji, nome, data e contador de membros
class EventHeaderWidget extends StatelessWidget {
  const EventHeaderWidget({
    required this.eventId,
    required this.emoji,
    required this.eventName,
    required this.formattedDate,
    required this.participantCount,
    required this.isCreator,
    required this.onEditName,
    super.key,
  });

  final String eventId;
  final String emoji;
  final String eventName;
  final String? formattedDate;
  final int participantCount;
  final bool isCreator;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Column(
      children: [
        // Avatar do evento
        EventEmojiAvatar(
          emoji: emoji,
          eventId: eventId,
          size: 100,
          emojiSize: 48,
        ),
        const SizedBox(height: 16),
        
        // Nome do evento (editável apenas para criador)
        _EventNameRow(
          eventName: eventName,
          isCreator: isCreator,
          onEditName: onEditName,
        ),
        
        // Data e hora do evento
        if (formattedDate != null) ...[
          const SizedBox(height: 8),
          Text(
            formattedDate!,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ],
        
        const SizedBox(height: 8),
        
        // Contador de membros
        Text(
          '$participantCount ${participantCount == 1 ? i18n.translate('member') : i18n.translate('members')}',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 14,
            color: GlimpseColors.textSubTitle,
          ),
        ),
      ],
    );
  }
}

/// Widget interno - Nome do evento com ícone de edição
class _EventNameRow extends StatelessWidget {
  const _EventNameRow({
    required this.eventName,
    required this.isCreator,
    required this.onEditName,
  });

  final String eventName;
  final bool isCreator;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            eventName,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: GlimpseColors.primaryColorLight,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isCreator) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onEditName,
            child: const Icon(
              IconsaxPlusLinear.edit_2,
              size: 20,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ],
      ],
    );
  }
}
