import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Iconsax.search_normal,
              color: Colors.black,
              size: 28,
            ),
            // Badge indicador de filtros ativos
            if (hasActiveFilters)
              Positioned(
                top: 14,
                right: 17,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: GlimpseColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
