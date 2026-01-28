import 'package:flutter/foundation.dart';

/// Coordinator singleton para gerenciar a troca de abas da HomeScreen de forma programática.
/// Permite que serviços externos (como notificações) solicitem mudanças de aba
/// sem depender de reconstruções do GoRouter.
class HomeTabCoordinator extends ChangeNotifier {
  static final HomeTabCoordinator _instance = HomeTabCoordinator._internal();
  static HomeTabCoordinator get instance => _instance;

  HomeTabCoordinator._internal();

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  /// Solicita a troca para a aba especificada
  /// [forceNotify] força a notificação mesmo se já estiver na aba (útil para re-trigger de lógica)
  void goToTab(int index, {bool forceNotify = false}) {
    if (_currentIndex == index && !forceNotify) return;
    
    _currentIndex = index;
    debugPrint('🔄 [HomeTabCoordinator] Solicitando troca para aba: $index (force=$forceNotify)');
    notifyListeners();
  }
}
