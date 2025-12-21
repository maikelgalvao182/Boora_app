import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Widget de celebração com confetti
/// 
/// Usado quando o usuário se aplica com sucesso a um evento
class ConfettiCelebration extends StatefulWidget {
  const ConfettiCelebration({
    super.key,
    this.duration = const Duration(seconds: 3),
    this.numberOfParticles = 50,
    this.maxBlastForce = 40.0,
    this.minBlastForce = 10.0,
    this.emissionFrequency = 0.03,
    this.gravity = 0.3,
    this.autoPlay = true,
  });

  final Duration duration;
  final int numberOfParticles;
  final double maxBlastForce;
  final double minBlastForce;
  final double emissionFrequency;
  final double gravity;
  final bool autoPlay;

  @override
  State<ConfettiCelebration> createState() => _ConfettiCelebrationState();
}

class _ConfettiCelebrationState extends State<ConfettiCelebration> {
  late ConfettiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ConfettiController(duration: widget.duration);
    
    if (widget.autoPlay) {
      // Disparar imediatamente usando microtask (mais rápido que addPostFrameCallback)
      Future.microtask(() {
        if (mounted) {
          _controller.play();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Método público para iniciar a animação manualmente
  void play() {
    if (mounted) {
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConfettiWidget(
        confettiController: _controller,
        blastDirectionality: BlastDirectionality.explosive,
        numberOfParticles: widget.numberOfParticles,
        maxBlastForce: widget.maxBlastForce,
        minBlastForce: widget.minBlastForce,
        emissionFrequency: widget.emissionFrequency,
        gravity: widget.gravity,
        shouldLoop: false,
        particleDrag: 0.05,
        colors: const [
          GlimpseColors.actionColor,
          GlimpseColors.primary,
          Color(0xFFFFB800), // Amarelo/dourado
          Color(0xFFFF6B6B), // Vermelho/rosa
          Color(0xFF4ECDC4), // Verde água
          Color(0xFFFFE66D), // Amarelo claro
        ],
        createParticlePath: (size) {
          // Cria confettis menores em forma de retângulos e círculos
          final path = Path();
          final smallerSize = Size(size.width * 0.4, size.height * 0.4);
          path.addOval(Rect.fromCircle(center: Offset.zero, radius: smallerSize.width / 2));
          return path;
        },
      ),
    );
  }
}

/// Overlay helper para mostrar confetti em qualquer tela
class ConfettiOverlay {
  /// Mostra confetti celebration em overlay
  /// 
  /// Útil para celebrar ações sem precisar adicionar o widget na árvore
  static OverlayEntry? show(BuildContext context) {
    final overlay = Overlay.of(context);
    
    final overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Confetti na parte inferior da tela
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ConfettiCelebration(
                numberOfParticles: 80,
                maxBlastForce: 45,
                minBlastForce: 20,
                emissionFrequency: 0.02,
                gravity: 0.1,
              ),
            ),
          ],
        ),
      ),
    );

    overlay.insert(overlayEntry);
    
    debugPrint('🎉 Confetti overlay inserido!');

    // Remove automaticamente após a duração
    Future.delayed(const Duration(seconds: 4), () {
      overlayEntry.remove();
      debugPrint('🎉 Confetti overlay removido!');
    });

    return overlayEntry;
  }
}
