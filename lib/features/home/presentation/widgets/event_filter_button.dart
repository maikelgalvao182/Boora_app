import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/services/events/event_creator_filters_controller.dart';

/// Botão flutuante para abrir filtros de eventos por criador.
///
/// Exibe indicador visual quando filtros estão ativos.
class EventFilterButton extends StatefulWidget {
  const EventFilterButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  State<EventFilterButton> createState() => _EventFilterButtonState();
}

class _EventFilterButtonState extends State<EventFilterButton> {
  final _controller = EventCreatorFiltersController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onFiltersChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onFiltersChanged);
    super.dispose();
  }

  void _onFiltersChanged() {
    // Defer setState to avoid calling during build phase
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFilters = _controller.hasActiveFilters;

    return GestureDetector(
      onTap: widget.onPressed,
      child: Container(
        width: 56.w,
        height: 56.h,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8.r,
              offset: Offset(0, 2.h),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Iconsax.search_normal,
              color: Colors.black,
              size: 28.sp,
            ),
            // Badge indicador de filtros ativos
            if (hasActiveFilters)
              Positioned(
                top: 14.h,
                right: 17.w,
                child: Container(
                  width: 12.w,
                  height: 12.h,
                  decoration: BoxDecoration(
                    color: GlimpseColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.w),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
