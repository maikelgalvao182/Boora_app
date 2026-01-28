import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/event_photo_feed/data/models/tagged_participant_model.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/tagged_participants_avatars.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

class EventPhotoComposerHeader extends StatelessWidget {
  const EventPhotoComposerHeader({
    super.key,
    required this.userId,
    this.userPhotoUrl,
    required this.topicText,
    required this.onSelectEvent,
    this.taggedParticipants = const [],
  });

  final String userId;
  final String? userPhotoUrl;
  final String topicText;
  final VoidCallback onSelectEvent;
  final List<TaggedParticipantModel> taggedParticipants;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: StableAvatar(
            userId: userId,
            size: 38,
            photoUrl: userPhotoUrl,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: ReactiveUserNameWithBadge(
                        userId: userId,
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: GlimpseColors.primaryColorLight,
                        ),
                      ),
                    ),
                    const TextSpan(text: '  '),
                    TextSpan(
                      text: '> ',
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: GlimpseColors.textSubTitle,
                      ),
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: InkWell(
                        onTap: onSelectEvent,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text(
                            topicText,
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: GlimpseColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (taggedParticipants.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      TaggedParticipantsAvatars(
                        participants: taggedParticipants,
                        maxVisible: 3,
                        avatarSize: 20,
                        overlap: 8,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        taggedParticipants.length == 1
                            ? i18n.translate('event_photo_one_participant_label')
                            : i18n.translate('event_photo_participants_count_label').replaceAll('{count}', taggedParticipants.length.toString()),
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: GlimpseColors.textSubTitle,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
