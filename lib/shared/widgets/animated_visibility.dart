import 'package:flutter/material.dart';

/// Widget reutilizável que anima a visibilidade de um child com
/// fade + slide + scale. Controlado externamente via [visible].
///
/// Exemplo:
/// ```dart
/// AnimatedVisibility(
///   visible: _isVisible,
///   child: MyButton(),
/// )
/// ```
class AnimatedVisibility extends StatefulWidget {
  const AnimatedVisibility({
    super.key,
    required this.visible,
    required this.child,
    this.hideDuration = const Duration(milliseconds: 220),
    this.showDuration = const Duration(milliseconds: 320),
    this.slideOffset = const Offset(0, 0.10),
    this.minScale = 0.98,
  });

  /// Se true, o child é exibido (fade in + slide up + scale up).
  /// Se false, o child é ocultado (fade out + slide down + scale down).
  final bool visible;

  /// Widget filho a ser animado.
  final Widget child;

  /// Duração da animação de esconder.
  final Duration hideDuration;

  /// Duração da animação de aparecer.
  final Duration showDuration;

  /// Offset do slide quando oculto (begin). Offset.zero quando visível (end).
  final Offset slideOffset;

  /// Escala mínima quando oculto (0.98 = quase imperceptível, premium).
  final double minScale;

  @override
  State<AnimatedVisibility> createState() => _AnimatedVisibilityState();
}

class _AnimatedVisibilityState extends State<AnimatedVisibility>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.hideDuration,
      reverseDuration: widget.showDuration,
      value: widget.visible ? 1.0 : 0.0,
    );

    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInCubic,
      reverseCurve: Curves.easeOutBack,
    );

    _slide = Tween<Offset>(
      begin: widget.slideOffset,
      end: Offset.zero,
    ).animate(curve);

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.60, curve: Curves.easeOut),
        reverseCurve: const Interval(0.20, 1.0, curve: Curves.easeIn),
      ),
    );

    _scale = Tween<double>(begin: widget.minScale, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          child: widget.child,
        ),
      ),
    );
  }
}
