import 'package:flutter/material.dart';
import 'package:partiu/features/home/presentation/screens/conversations_tab.dart';
import 'package:partiu/features/home/presentation/screens/discover_tab.dart';
import 'package:partiu/features/home/presentation/screens/matches_tab.dart';
import 'package:partiu/features/home/presentation/screens/profile_tab.dart';
import 'package:partiu/features/home/presentation/screens/ranking_tab.dart';
import 'package:partiu/features/home/presentation/widgets/home_app_bar.dart';
import 'package:partiu/features/home/presentation/widgets/home_bottom_navigation_bar.dart';
import 'package:partiu/shared/widgets/auth_protected_wrapper.dart';


/// Tela principal do app com navegação por tabs
class HomeScreenRefactored extends StatefulWidget {
  const HomeScreenRefactored({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeScreenRefactored> createState() => _HomeScreenRefactoredState();
}

class _HomeScreenRefactoredState extends State<HomeScreenRefactored> {
  int _selectedIndex = 0;

  // Lazy loading das páginas - instancia apenas quando necessário
  final List<Widget?> _pages = List<Widget?>.filled(5, null);

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    // Carregar página inicial
    _ensurePage(_selectedIndex);
  }

  /// Garante que a página está instanciada
  void _ensurePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pages[index] ??= _buildPage(index);
  }

  /// Constrói a página para o índice fornecido
  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const DiscoverTab();
      case 1:
        return const MatchesTab();
      case 2:
        return const RankingTab();
      case 3:
        return const ConversationsTab();
      case 4:
        return const ProfileTab();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Exibe a navegação entre abas com preservação de estado
  Widget _showCurrentNavBar() {
    return IndexedStack(
      index: _selectedIndex,
      children: <Widget>[
        RepaintBoundary(child: _pages[0] ?? const SizedBox.shrink()),
        RepaintBoundary(child: _pages[1] ?? const SizedBox.shrink()),
        RepaintBoundary(child: _pages[2] ?? const SizedBox.shrink()),
        RepaintBoundary(child: _pages[3] ?? const SizedBox.shrink()),
        RepaintBoundary(child: _pages[4] ?? const SizedBox.shrink()),
      ],
    );
  }

  /// Atualizar aba selecionada
  void _onTappedNavBar(int index) {
    if (index == _selectedIndex) {
      // Re-tap na mesma aba - pode adicionar lógica de scroll to top, etc.
      return;
    }

    setState(() {
      _ensurePage(index); // Lazy instantiate target page
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthProtectedWrapper(
      loadingMessage: 'Carregando dados do usuário...',
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: (_selectedIndex == 0)
            ? HomeAppBar(
                onNotificationsTap: () {
                  // TODO: Implementar navegação para notificações
                  debugPrint('Notificações tapped');
                },
                onFilterTap: () {
                  // TODO: Implementar abertura de filtros
                  debugPrint('Filtros tapped');
                },
              )
            : null,
        body: Stack(
          children: [
            _showCurrentNavBar(),

          ],
        ),
        bottomNavigationBar: HomeBottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onTappedNavBar,
        ),
      ),
    );
  }
}
