import 'package:flutter/material.dart';
import 'package:partiu/screens/notifications/controllers/simplified_notification_controller.dart';
import 'package:partiu/screens/notifications/repositories/notifications_repository.dart';
import 'package:partiu/screens/notifications/widgets/simplified_notification_screen.dart';

/// Wrapper para instanciar o SimplifiedNotificationScreen com suas dependências
class SimplifiedNotificationScreenWrapper extends StatefulWidget {
  const SimplifiedNotificationScreenWrapper({super.key});

  @override
  State<SimplifiedNotificationScreenWrapper> createState() =>
      _SimplifiedNotificationScreenWrapperState();
}

class _SimplifiedNotificationScreenWrapperState
    extends State<SimplifiedNotificationScreenWrapper> {
  late final SimplifiedNotificationController _controller;

  @override
  void initState() {
    super.initState();
    
    // Instancia o repository e controller
    final repository = NotificationsRepository();
    _controller = SimplifiedNotificationController(repository: repository);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimplifiedNotificationScreen(
      controller: _controller,
      onBackPressed: () => Navigator.of(context).pop(),
    );
  }
}
