import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/event_emoji_avatar.dart';

/// Widget do cabeçalho do evento
/// Exibe emoji, nome, data e contador de membros
/// Para criadores: exibe botões de edição em formato de nuvem de tags
class EventHeaderWidget extends StatelessWidget {
  const EventHeaderWidget({
    required this.eventId,
    required this.emoji,
    required this.eventName,
    required this.formattedDate,
    required this.participantCount,
    required this.isCreator,
    required this.onEditName,
    required this.onEditDate,
    this.onEditCategory,
    this.onEditParticipants,
    this.onEditLocation,
    this.categoryLabel,
    this.participantsLabel,
    this.locationLabel,
    super.key,
  });

  final String eventId;
  final String emoji;
  final String eventName;
  final String? formattedDate;
  final int participantCount;
  final bool isCreator;
  final VoidCallback onEditName;
  final VoidCallback onEditDate;
  final VoidCallback? onEditCategory;
  final VoidCallback? onEditParticipants;
  final VoidCallback? onEditLocation;
  final String? categoryLabel;
  final String? participantsLabel;
  final String? locationLabel;

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
        
        const SizedBox(height: 16),
        
        // Nuvem de tags/botões de edição (apenas para criador)
        if (isCreator) ...[
          _EditTagsCloud(
            formattedDate: formattedDate,
            categoryLabel: categoryLabel,
            participantsLabel: participantsLabel,
            locationLabel: locationLabel,
            onEditDate: onEditDate,
            onEditCategory: onEditCategory,
            onEditParticipants: onEditParticipants,
            onEditLocation: onEditLocation,
            i18n: i18n,
          ),
          const SizedBox(height: 16),
        ] else if (formattedDate != null) ...[
          // Para não-criadores, mostrar apenas a data (sem edição)
          Text(
            formattedDate!,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: GlimpseColors.textSubTitle,
            ),
          ),
          const SizedBox(height: 8),
        ],
        
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

/// Widget interno - Nuvem de tags de edição
class _EditTagsCloud extends StatelessWidget {
  const _EditTagsCloud({
    required this.formattedDate,
    required this.categoryLabel,
    required this.participantsLabel,
    required this.locationLabel,
    required this.onEditDate,
    required this.onEditCategory,
    required this.onEditParticipants,
    required this.onEditLocation,
    required this.i18n,
  });

  final String? formattedDate;
  final String? categoryLabel;
  final String? participantsLabel;
  final String? locationLabel;
  final VoidCallback onEditDate;
  final VoidCallback? onEditCategory;
  final VoidCallback? onEditParticipants;
  final VoidCallback? onEditLocation;
  final AppLocalizations i18n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          // Data e hora
          if (formattedDate != null)
            _EditTag(
              icon: IconsaxPlusLinear.calendar_1,
              label: formattedDate!,
              onTap: onEditDate,
            ),
          
          // Categoria
          if (onEditCategory != null)
            _EditTag(
              icon: IconsaxPlusLinear.category,
              label: categoryLabel ?? i18n.translate('category'),
              onTap: onEditCategory!,
            ),
          
          // Participantes/Filtros
          if (onEditParticipants != null)
            _EditTag(
              icon: IconsaxPlusLinear.people,
              label: participantsLabel ?? i18n.translate('filters'),
              onTap: onEditParticipants!,
            ),
          
          // Localização
          if (onEditLocation != null)
            _EditTag(
              icon: IconsaxPlusLinear.location,
              label: locationLabel ?? i18n.translate('location'),
              onTap: onEditLocation!,
            ),
        ],
      ),
    );
  }
}

/// Widget interno - Tag de edição individual
class _EditTag extends StatelessWidget {
  const _EditTag({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: GlimpseColors.lightTextField,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: GlimpseColors.primaryColorLight,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: GlimpseColors.primaryColorLight,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget interno - Nome do evento
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
    Widget nameText = Text(
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
    );

    if (isCreator) {
      return GestureDetector(
        onTap: onEditName,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: GlimpseColors.lightTextField,
            borderRadius: BorderRadius.circular(12),
          ),
          child: nameText,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: nameText,
    );
  }
}
