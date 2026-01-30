import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/shared/widgets/typing_indicator.dart';

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
      final isReady = controller.participantsReady;
      
      // 🎯 Mostrar TypingIndicator enquanto carrega (evita "pop")
      if (count == 0 && !isReady) {
        return _LoadingChip();
      }
      
      return _AnimatedChip(
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
        
        // 🎯 Mostrar loading se ainda não tem dados
        if (!snapshot.hasData && count == 0 && !controller.participantsReady) {
          return _LoadingChip();
        }
        
        return _AnimatedChip(
          count: count,
          singularLabel: singularLabel,
          pluralLabel: pluralLabel,
        );
      },
    );
  }
}

/// 🎯 Chip com loading indicator (três pontos animados)
class _LoadingChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: GlimpseColors.primaryLight,
        borderRadius: BorderRadius.circular(100),
      ),
      child: TypingIndicator(
        color: GlimpseColors.primaryColorLight,
        dotSize: 6,
      ),
    );
  }
}

/// 🎯 Chip com animação de fade/scale na transição
class _AnimatedChip extends StatelessWidget {
  const _AnimatedChip({
    required this.count,
    required this.singularLabel,
    required this.pluralLabel,
  });

  final int count;
  final String singularLabel;
  final String pluralLabel;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(
            scale: 0.8 + (0.2 * value),
            child: child,
          ),
        );
      },
      child: Container(
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
      ),
    );
  }
}
