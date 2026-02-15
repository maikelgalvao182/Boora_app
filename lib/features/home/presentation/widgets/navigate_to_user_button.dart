import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:iconsax/iconsax.dart';

/// Botão flutuante para centralizar mapa na localização do usuário
class NavigateToUserButton extends StatefulWidget {
  const NavigateToUserButton({
    required this.onPressed,
    super.key,
  });

  final VoidCallback onPressed;

  @override
  State<NavigateToUserButton> createState() => _NavigateToUserButtonState();
}

class _NavigateToUserButtonState extends State<NavigateToUserButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePress() {
    HapticFeedback.lightImpact();
    
    // Anima o botão
    _controller.forward().then((_) {
      _controller.reverse();
    });
    
    // Executa callback
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'navigate_to_user_button',
      child: Material(
        elevation: 8.r,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: const CircleBorder(),
        color: Colors.transparent,
        child: InkWell(
          onTap: _handlePress,
          customBorder: const CircleBorder(),
          child: Container(
            width: 56.w,
            height: 56.h,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: AnimatedBuilder(
                animation: _rotationAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationAnimation.value * 2 * 3.14159, // 360 graus em radianos
                    child: child,
                  );
                },
                child: Icon(
                  Iconsax.direct_up,
                  color: GlimpseColors.primaryColorLight,
                  size: 28.sp,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
