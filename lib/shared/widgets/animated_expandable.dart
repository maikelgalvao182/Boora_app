import 'package:flutter/material.dart';

/// Widget que anima a expansão e colapso de seu conteúdo
/// Útil para mostrar/ocultar seções com transição suave
/// Combina AnimatedSize (altura) + AnimatedOpacity (fade) para efeito mais suave
class AnimatedExpandable extends StatelessWidget {
  const AnimatedExpandable({
    required this.isExpanded,
    required this.child,
    super.key,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOut,
    this.axis = Axis.vertical,
    this.maintainState = false,
    this.clip = true,
  });

  final bool isExpanded;
  final Widget child;
  final Duration duration;
  final Curve curve;
  final Axis axis;
  final bool maintainState;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final alignment = axis == Axis.horizontal ? Alignment.centerLeft : Alignment.topCenter;

    final content = AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      clipBehavior: clip ? Clip.hardEdge : Clip.none,
      child: AnimatedOpacity(
        duration: duration,
        curve: curve,
        opacity: isExpanded ? 1.0 : 0.0,
        child: maintainState
            ? IgnorePointer(
                ignoring: !isExpanded,
                child: Align(
                  alignment: alignment,
                  widthFactor: axis == Axis.horizontal ? (isExpanded ? 1.0 : 0.0) : 1.0,
                  heightFactor: axis == Axis.vertical ? (isExpanded ? 1.0 : 0.0) : 1.0,
                  child: child,
                ),
              )
            : (isExpanded
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = constraints.maxWidth;
                      if (!maxWidth.isFinite) {
                        return child;
                      }

                      return ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: maxWidth,
                          maxWidth: maxWidth,
                        ),
                        child: child,
                      );
                    },
                  )
                : const SizedBox.shrink()),
      ),
    );

    return clip ? ClipRect(child: content) : content;
  }
}
