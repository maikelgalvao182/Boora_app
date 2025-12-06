import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

class NotificationListSkeleton extends StatelessWidget {
  const NotificationListSkeleton({super.key, this.itemCount = 8});
  
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: itemCount,
          separatorBuilder: (_, __) => const Divider(
            height: 0,
            color: GlimpseColors.lightTextField,
          ),
          itemBuilder: (_, __) => const _NotificationSkeletonTile(),
        ),
      ),
    );
  }
}

class _NotificationSkeletonTile extends StatelessWidget {
  const _NotificationSkeletonTile();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            _Box.square(44, radius: 12),
            const SizedBox(width: 12),
            // Título + Subtítulo
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bar(160, 14, radius: 6),
                  SizedBox(height: 8),
                  _Bar(120, 12, radius: 6),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Dot
            const _Bar(18, 18, radius: 4),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.width, this.height, {required this.radius});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: GlimpseColors.lightTextField,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  const _Box.square(double size, {this.radius = 8})
      : width = size,
        height = size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: GlimpseColors.lightTextField,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
