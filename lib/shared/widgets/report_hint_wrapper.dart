import 'dart:async';
import 'package:el_tooltip/el_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget genérico que mostra um tooltip temporário com auto-show
/// usando ElTooltip
class AutoShowTooltip extends StatefulWidget {
  const AutoShowTooltip({
    required this.child,
    required this.message,
    this.position = ElTooltipPosition.topEnd,
    this.duration = const Duration(seconds: 3),
    this.delay = const Duration(milliseconds: 800),
    this.color = Colors.red,
    this.textColor = Colors.white,
    super.key,
  });

  final Widget child;
  final String message;
  final ElTooltipPosition position;
  final Duration duration;
  final Duration delay;
  final Color color;
  final Color textColor;

  @override
  State<AutoShowTooltip> createState() => _AutoShowTooltipState();
}

class _AutoShowTooltipState extends State<AutoShowTooltip> {
  final ElTooltipController _tooltipController = ElTooltipController();
  Timer? _showTimer;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // Mostra o tooltip automaticamente após o delay
    _showTimer = Timer(widget.delay, () {
      if (mounted) {
        _tooltipController.show();
        
        // Esconde após a duração especificada
        _hideTimer = Timer(widget.duration, () {
          if (mounted) {
            _tooltipController.hide();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ElTooltip(
      controller: _tooltipController,
      position: widget.position,
      color: widget.color,
      showArrow: true,
      showModal: false,
      showChildAboveOverlay: false,
      appearAnimationDuration: const Duration(milliseconds: 300),
      disappearAnimationDuration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      content: Text(
        widget.message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: widget.textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Widget específico para tooltip de denúncia (report)
/// Usa a tradução 'report_hint_click_here'
class ReportHintTooltip extends StatefulWidget {
  const ReportHintTooltip({
    required this.child,
    this.position = ElTooltipPosition.topEnd,
    this.duration = const Duration(seconds: 3),
    this.delay = const Duration(milliseconds: 800),
    super.key,
  });

  final Widget child;
  final ElTooltipPosition position;
  final Duration duration;
  final Duration delay;

  @override
  State<ReportHintTooltip> createState() => _ReportHintTooltipState();
}

class _ReportHintTooltipState extends State<ReportHintTooltip> {
  final ElTooltipController _tooltipController = ElTooltipController();
  Timer? _showTimer;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _showTimer = Timer(widget.delay, () {
      if (mounted) {
        _tooltipController.show();
        _hideTimer = Timer(widget.duration, () {
          if (mounted) {
            _tooltipController.hide();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final message = i18n.translate('report_hint_click_here');

    return ElTooltip(
      controller: _tooltipController,
      position: widget.position,
      color: Colors.red,
      showArrow: true,
      showModal: false,
      showChildAboveOverlay: false,
      appearAnimationDuration: const Duration(milliseconds: 300),
      disappearAnimationDuration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: widget.child,
    );
  }
}

// Mantém o enum para compatibilidade com código antigo
enum ReportHintPosition { top, bottom }
