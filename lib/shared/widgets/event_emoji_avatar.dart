import 'package:flutter/material.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_color_helper.dart';

/// Widget compartilhável de avatar de emoji para eventos
/// Usado em conversation_tile, chat_app_bar e outros lugares
class EventEmojiAvatar extends StatelessWidget {
  const EventEmojiAvatar({
    required this.emoji,
    required this.eventId,
    this.size = 44,
    this.emojiSize = 24,
    super.key,
  });

  final String emoji;
  final String eventId;
  final double size;
  final double emojiSize;

  static const String defaultEmoji = '🎉';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: MarkerColorHelper.getColorForId(eventId),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        emoji.isNotEmpty ? emoji : defaultEmoji,
        style: TextStyle(
          fontSize: emojiSize,
        ),
      ),
    );
  }
}
