import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

class EventPhotoComposerHeader extends StatelessWidget {
  const EventPhotoComposerHeader({
    super.key,
    required this.userId,
    this.userPhotoUrl,
    required this.topicText,
    required this.onSelectEvent,
  });

  final String userId;
  final String? userPhotoUrl;
  final String topicText;
  final VoidCallback onSelectEvent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        StableAvatar(
          userId: userId,
          size: 38,
          photoUrl: userPhotoUrl,
          borderRadius: BorderRadius.circular(10),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
        ),
      ],
    );
  }
}
