import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Botão flutuante "Ganhe 90 dias Premium"
class InviteButton extends StatelessWidget {
  const InviteButton({
    required this.onPressed,
    super.key,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text(
              '🎁',
              style: TextStyle(fontSize: 28),
            ),
          ),
        ),
      ),
    );
  }
}
