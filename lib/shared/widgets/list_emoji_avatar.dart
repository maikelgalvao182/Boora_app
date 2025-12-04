import 'package:flutter/material.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_color_helper.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

/// Widget de avatar composto: emoji de fundo + avatar do usuário sobreposto
/// 
/// Usado em ListCard e outros componentes que precisam exibir:
/// - Background colorido com emoji do evento
/// - Avatar do usuário no canto inferior direito
class ListEmojiAvatar extends StatelessWidget {
  const ListEmojiAvatar({
    required this.emoji,
    required this.eventId,
    this.size = 56,
    this.emojiSize = 28,
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
