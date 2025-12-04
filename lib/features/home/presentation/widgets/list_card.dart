import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/list_emoji_avatar.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/features/home/presentation/widgets/list_card/list_card_controller.dart';
import 'package:partiu/features/home/presentation/widgets/list_card_shimmer.dart';

/// Card de atividade para lista
/// 
/// Busca dados de:
/// - events: emoji, activityText, schedule
/// - EventApplications: participantes aprovados + contador
class ListCard extends StatefulWidget {
  const ListCard({
    required this.controller,
    this.onTap,
    super.key,
  });

  final ListCardController controller;
  final VoidCallback? onTap;

  @override
  State<ListCard> createState() => _ListCardState();
}

class _ListCardState extends State<ListCard> {
  late ListCardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Formata data/hora para exibição
  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    
    try {
      final formattedDate = DateFormat('dd/MM', 'pt_BR').format(dateTime);
      
      // Se for meia-noite exata (00:00), mostrar só a data (flexible)
      if (dateTime.hour == 0 && dateTime.minute == 0) {
        return formattedDate;
      }
      
      // Caso contrário, mostrar data + hora
      final formattedTime = DateFormat('HH:mm').format(dateTime);
      return '$formattedDate • $formattedTime';
    } catch (e) {
      debugPrint('Erro ao formatar data/hora: $e');
      return '';
    }
  }

  /// Constrói a pilha de avatares: Emoji (Criador) + Participantes + Contador
  Widget _buildParticipantsStack() {
    final emoji = _controller.emoji ?? ListEmojiAvatar.defaultEmoji;
    final participants = _controller.recentParticipants;
    final totalCount = _controller.totalParticipantsCount;
    
    final displayCount = participants.length > 5 ? 5 : participants.length;
    final hasCounter = totalCount > 0;
    
    const double emojiAvatarSize = 46.0;
    const double participantSize = 46.0;
    const double counterSize = 52.0;
    const double overlapOffset = 30.0;
    
    // Largura total = Emoji + (Participantes * Offset) + (Contador * Offset)
    double totalWidth = emojiAvatarSize;
    if (displayCount > 0) {
       totalWidth += (displayCount * overlapOffset);
    }
    if (hasCounter) {
      totalWidth += overlapOffset;
    }

    return SizedBox(
      height: emojiAvatarSize,
      width: totalWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Emoji Avatar (Base - Esquerda - Primeiro da lista)
          Positioned(
            left: 0,
            top: 0,
            child: ListEmojiAvatar(
              emoji: emoji,
              eventId: _controller.eventId,
              size: emojiAvatarSize,
              emojiSize: 28,
            ),
          ),
          
          // 2. Participantes (Sobrepondo da esquerda para a direita)
          for (int i = 0; i < displayCount; i++)
            Positioned(
              left: emojiAvatarSize - (emojiAvatarSize - overlapOffset) + (i * overlapOffset),
              top: (emojiAvatarSize - participantSize) / 2,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                ),
                child: StableAvatar(
                  userId: participants[i]['userId'] as String,
                  photoUrl: participants[i]['photoUrl'] as String?,
                  size: participantSize,
                  borderRadius: BorderRadius.circular(999),
                  enableNavigation: true,
                ),
              ),
            ),
            
          // 3. Contador (Último da pilha)
          if (hasCounter)
            Positioned(
              left: emojiAvatarSize - (emojiAvatarSize - overlapOffset) + (displayCount * overlapOffset),
              top: 0,
              child: Container(
                width: counterSize,
                height: counterSize,
                decoration: BoxDecoration(
                  color: GlimpseColors.primaryLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$totalCount',
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: GlimpseColors.primaryColorLight,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (_controller.isLoading) {
      return const ListCardShimmer();
    }

    // Error state
    if (_controller.error != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: GlimpseColors.borderColorLight,
            width: 1,
          ),
        ),
        child: Text(
          _controller.error!,
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 13,
            color: Colors.red,
          ),
        ),
      );
    }

    // Success state
    final activityText = _controller.activityText ?? 'Atividade';
    
    final scheduleDate = _controller.scheduleDate;
    String dateText = '';
    String timeText = '';
    if (scheduleDate != null) {
      dateText = DateFormat('dd/MM', 'pt_BR').format(scheduleDate);
      if (scheduleDate.hour != 0 || scheduleDate.minute != 0) {
        timeText = DateFormat('HH:mm').format(scheduleDate);
      }
    }

    final hasParticipants = _controller.totalParticipantsCount > 0;
    final locationName = _controller.locationName;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: GlimpseColors.borderColorLight,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título/Data (Esquerda) + Contador (Direita)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activityText,
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: GlimpseColors.primaryColorLight,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      if (dateText.isNotEmpty || (locationName != null && locationName.isNotEmpty)) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (locationName != null && locationName.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: GlimpseColors.primaryLight,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  locationName,
                                  style: GoogleFonts.getFont(
                                    FONT_PLUS_JAKARTA_SANS,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: GlimpseColors.primaryDarker,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                            if (dateText.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: GlimpseColors.lightTextField,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Iconsax.calendar_1,
                                      size: 14,
                                      color: GlimpseColors.textSubTitle,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      dateText,
                                      style: GoogleFonts.getFont(
                                        FONT_PLUS_JAKARTA_SANS,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: GlimpseColors.textSubTitle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            if (timeText.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: GlimpseColors.lightTextField,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Iconsax.clock,
                                      size: 14,
                                      color: GlimpseColors.textSubTitle,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      timeText,
                                      style: GoogleFonts.getFont(
                                        FONT_PLUS_JAKARTA_SANS,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: GlimpseColors.textSubTitle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Base: Avatars (Esquerda)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildParticipantsStack(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
