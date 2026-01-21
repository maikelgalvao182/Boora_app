import 'package:flutter/material.dart';
import 'package:partiu/features/event_photo_feed/data/models/tagged_participant_model.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

/// Widget que exibe avatares empilhados dos participantes marcados
/// Similar ao estilo do chat_app_bar_widget
class TaggedParticipantsAvatars extends StatelessWidget {
  const TaggedParticipantsAvatars({
    super.key,
    required this.participants,
    this.maxVisible = 3,
    this.avatarSize = 20,
    this.overlap = 8,
  });

  final List<TaggedParticipantModel> participants;
  final int maxVisible;
  final double avatarSize;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleCount = participants.length > maxVisible ? maxVisible : participants.length;
    final hasMore = participants.length > maxVisible;

    // Calcular largura total
    final totalWidth = avatarSize + (visibleCount - 1) * (avatarSize - overlap);

    return SizedBox(
      width: totalWidth,
      height: avatarSize,
      child: Stack(
        children: [
          for (var i = 0; i < visibleCount; i++)
            Positioned(
              left: i * (avatarSize - overlap),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 1.5,
                  ),
                ),
                child: StableAvatar(
                  userId: participants[i].userId,
                  photoUrl: participants[i].userPhotoUrl,
                  size: avatarSize - 3, // Compensar border
                  borderRadius: BorderRadius.circular(avatarSize / 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
