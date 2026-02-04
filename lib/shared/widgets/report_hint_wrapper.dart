import 'package:flutter/material.dart';

/// Widget genérico que mostra um tooltip temporário com auto-show
/// Simplificado: apenas retorna o child (tooltip removido)
class AutoShowTooltip extends StatelessWidget {
  const AutoShowTooltip({
    required this.child,
    required this.message,
    this.position,
    this.duration = const Duration(seconds: 3),
    this.delay = const Duration(milliseconds: 800),
    this.color = Colors.red,
    this.textColor = Colors.white,
    super.key,
  });

  final Widget child;
  final String message;
  final dynamic position;
  final Duration duration;
  final Duration delay;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

/// Widget específico para tooltip de denúncia (report)
/// Simplificado: apenas retorna o child (tooltip removido)
class ReportHintTooltip extends StatelessWidget {
  const ReportHintTooltip({
    required this.child,
    this.position,
    this.duration = const Duration(seconds: 3),
    this.delay = const Duration(milliseconds: 800),
    super.key,
  });

  final Widget child;
  final dynamic position;
  final Duration duration;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

// Mantém o enum para compatibilidade com código antigo
enum ReportHintPosition { top, bottom }
