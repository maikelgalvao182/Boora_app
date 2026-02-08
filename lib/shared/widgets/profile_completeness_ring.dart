import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget que desenha um anel de progresso quadrado ao redor do avatar
/// para indicar visualmente o percentual de completude do perfil.
/// 
/// Cores:
/// - < 100%: Gradiente vermelho/laranja (incompleto)
/// - 100%: Verde (completo)
/// 
/// O anel segue o formato quadrado arredondado do StableAvatar.
/// 
/// Uso:
/// ```dart
/// ProfileCompletenessRing(
///   size: 100,
///   strokeWidth: 4,
///   percentage: 75, // 0-100
///   child: StableAvatar(...),
/// )
/// ```
class ProfileCompletenessRing extends StatelessWidget {
  const ProfileCompletenessRing({
    required this.size,
    required this.percentage,
    required this.child,
    this.strokeWidth = 4.0,
    this.showBadge = true,
    super.key,
  });

  final double size;
  final int percentage; // 0-100
  final Widget child;
  final double strokeWidth;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    // Cores baseadas no percentual
    final Color ringColor;
    final Gradient? ringGradient;

    if (percentage >= 100) {
      // Verde quando 100% completo
      ringColor = const Color(0xFF4CAF50); // Verde
      ringGradient = null;
    } else {
      // Gradiente vermelho/laranja quando incompleto
      ringColor = const Color(0xFFE53935); // Vermelho
      ringGradient = const LinearGradient(
        colors: [
          Color(0xFFE53935), // Vermelho
          Color(0xFFFF6F00), // Laranja escuro
          Color(0xFFFF9800), // Laranja
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none, // Permite que a tag ultrapasse os limites
        children: [
          // Anel de progresso quadrado
          CustomPaint(
            size: Size(size, size),
            painter: _ProgressRingPainter(
              percentage: percentage.clamp(0, 100),
              strokeWidth: strokeWidth,
              ringColor: ringColor,
              ringGradient: ringGradient,
            ),
          ),
          // Child (avatar) no centro
          SizedBox(
            width: size - (strokeWidth * 2) - 4, // Margem interna
            height: size - (strokeWidth * 2) - 4,
            child: child,
          ),

          // Badge de percentual (apenas se incompleto e showBadge = true)
          if (showBadge && percentage < 100 && percentage > 0)
            Positioned(
              bottom: -5,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: ringColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  i18n.translate('percentage_value').replaceAll('{value}', percentage.toString()),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom painter que desenha o anel de progresso circular
class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.percentage,
    required this.strokeWidth,
    required this.ringColor,
    this.ringGradient,
  });

  final int percentage;
  final double strokeWidth;
  final Color ringColor;
  final Gradient? ringGradient;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Fundo cinza claro (trilha do progresso) - círculo completo
    final backgroundPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Anel de progresso
    if (percentage > 0) {
      final progressPaint = Paint()
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // Aplica gradiente ou cor sólida
      final rect = Rect.fromLTWH(0, 0, size.width, size.height);
      if (ringGradient != null) {
        progressPaint.shader = ringGradient!.createShader(rect);
      } else {
        progressPaint.color = ringColor;
      }

      // Desenha arco de progresso (começa do topo e vai no sentido horário)
      const startAngle = -90 * 3.14159 / 180; // -90 graus (topo)
      final sweepAngle = (percentage / 100) * 2 * 3.14159; // Ângulo proporcional

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) {
    return oldDelegate.percentage != percentage ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.ringGradient != ringGradient;
  }
}
