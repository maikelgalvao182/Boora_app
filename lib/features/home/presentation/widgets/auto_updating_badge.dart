import 'package:flutter/material.dart';
import 'package:partiu/common/state/app_state.dart';

/// Widget que exibe um badge de contador
/// Usa ValueListenableBuilder para reativamente atualizar com AppState (padrão Advanced-Dating)
class AutoUpdatingBadge extends StatelessWidget {
  const AutoUpdatingBadge({
    required this.child,
    super.key,
    this.count,
    this.badgeColor = Colors.red,
    this.textColor = Colors.white,
    this.fontSize = 10,
    this.minBadgeSize = 16.0,
    this.badgePadding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  });

  final Widget child;
  final int? count; // Agora opcional - usa AppState.unreadNotifications se null
  final Color badgeColor;
  final Color textColor;
  final double fontSize;
  final double minBadgeSize;
  final EdgeInsets badgePadding;

  static const _badgeRadius = 10.0;
  static const _badgeBorderRadius = BorderRadius.all(Radius.circular(_badgeRadius));
  static const _badgePosition = -2.0;
  static const _badgeTop = 2.0;

  @override
  Widget build(BuildContext context) {
    // Se count foi passado explicitamente, usar o valor (para Actions/Conversations)
    if (count != null) {
      return _buildBadge(count!);
    }
    
    // Caso contrário, usar AppState.unreadNotifications (padrão Advanced-Dating)
    return ValueListenableBuilder<int>(
      valueListenable: AppState.unreadNotifications,
      child: child,
      builder: (context, notificationCount, childWidget) {
        return _buildBadge(notificationCount, childWidget: childWidget);
      },
    );
  }

  Widget _buildBadge(int badgeCount, {Widget? childWidget}) {
    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          childWidget ?? child,
          if (badgeCount > 0)
            Positioned(
              right: _badgePosition,
              top: _badgeTop,
              child: IgnorePointer(
                child: Container(
                  padding: badgePadding,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: _badgeBorderRadius,
                    border: Border.all(color: Colors.white),
                  ),
                  constraints: BoxConstraints(
                    minWidth: minBadgeSize,
                    minHeight: minBadgeSize,
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : badgeCount.toString(),
                    style: TextStyle(
                      color: textColor,
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Badge específico para mensagens
class MessagesBadge extends StatelessWidget {
  const MessagesBadge({
    required this.child,
    super.key,
    this.count = 0,
    this.badgeColor = Colors.red,
    this.textColor = Colors.white,
    this.fontSize = 10,
  });

  final Widget child;
  final int count;
  final Color badgeColor;
  final Color textColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return AutoUpdatingBadge(
      count: count,
      badgeColor: badgeColor,
      textColor: textColor,
      fontSize: fontSize,
      child: child,
    );
  }
}
