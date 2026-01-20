import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';

/// Widget que exibe contador de participantes em formato chip.
///
/// Otimização: por padrão NÃO abre stream próprio por card.
/// Em vez disso, consome `EventCardController.participantsCount`, que já é
/// alimentado pelo listener de participantes do controller (1 stream por card,
/// não 2).
///
/// Se você quiser forçar real-time independente do controller por algum motivo,
/// use `useRealtimeStream: true`.
class ParticipantsCounter extends StatelessWidget {
  const ParticipantsCounter({
    required this.controller,
    required this.eventId,
    required this.singularLabel,
    required this.pluralLabel,
    this.useRealtimeStream = false,
    super.key,
  });

  final EventCardController controller;
  final String eventId;
  final String singularLabel;
  final String pluralLabel;
  final bool useRealtimeStream;

  @override
  Widget build(BuildContext context) {
    // Caminho otimizado (default)
    if (!useRealtimeStream) {
      final count = controller.participantsCount;
      return _Chip(
        count: count,
        singularLabel: singularLabel,
        pluralLabel: pluralLabel,
      );
    }

    // Fallback: se quiser MESMO abrir um stream aqui (evitar quando estiver em lista)
    return StreamBuilder<int>(
      stream: controller.participantsCountStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? controller.participantsCount;
        return _Chip(
          count: count,
          singularLabel: singularLabel,
          pluralLabel: pluralLabel,
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.count,
    required this.singularLabel,
    required this.pluralLabel,
  });

  final int count;
  final String singularLabel;
  final String pluralLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: GlimpseColors.primaryLight,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$count ${count == 1 ? singularLabel : pluralLabel}',
        style: GoogleFonts.getFont(
          FONT_PLUS_JAKARTA_SANS,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: GlimpseColors.primaryColorLight,
        ),
      ),
    );
  }
}
