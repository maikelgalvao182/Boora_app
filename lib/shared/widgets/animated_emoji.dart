import 'dart:async';
import 'package:flutter/material.dart';

class AnimatedEmoji extends StatefulWidget {
  const AnimatedEmoji({
    required this.emoji,
    this.size = 40,
    super.key,
  });

  final String emoji;
  final double size;

  @override
  State<AnimatedEmoji> createState() => _AnimatedEmojiState();
}

class _AnimatedEmojiState extends State<AnimatedEmoji> {
  late String _displayedEmoji;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _displayedEmoji = widget.emoji;
  }

  @override
  void didUpdateWidget(covariant AnimatedEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.emoji != oldWidget.emoji) {
      _timer?.cancel();

      // Delay leve para UX natural
      _timer = Timer(const Duration(milliseconds: 200), () async {
        if (!mounted) return;

        // Microtask: garante animação suave sem perder timing
        await Future.delayed(Duration.zero);

        setState(() {
          _displayedEmoji = widget.emoji;
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.elasticOut,
      switchOutCurve: Curves.easeInQuad,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return ScaleTransition(
          scale: animation,
          child: child,
        );
      },
      child: Text(
        _displayedEmoji,
        key: ValueKey(_displayedEmoji),
        style: TextStyle(fontSize: widget.size),
      ),
    );
  }
}
