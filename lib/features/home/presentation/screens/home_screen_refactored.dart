import 'package:flutter/material.dart';
import 'package:partiu/features/conversations/ui/conversations_tab.dart';
import 'package:partiu/features/home/presentation/screens/discover_tab.dart';
import 'package:partiu/features/home/presentation/screens/actions_tab.dart';
import 'package:partiu/features/home/presentation/screens/profile_tab.dart';
import 'package:partiu/features/home/presentation/screens/ranking_tab.dart';
import 'package:partiu/features/home/presentation/widgets/home_app_bar.dart';
import 'package:partiu/features/home/presentation/widgets/home_bottom_navigation_bar.dart';
import 'package:partiu/shared/widgets/auth_protected_wrapper.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/people_ranking_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/ranking_viewmodel.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/core/services/app_initializer_service.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/features/home/presentation/coordinators/home_tab_coordinator.dart';
import 'package:provider/provider.dart';

/// Tela principal do app com navegação por tabs
/// 
/// IMPORTANTE:
/// - SplashScreen executa apenas a inicialização CRÍTICA (rápida)
/// - Warmups pesados (mapa/conversas/participantes) rodam após o primeiro frame
class HomeScreenRefactored extends StatefulWidget {
  const HomeScreenRefactored({
    super.key, 
    this.initialIndex = 0,
  });

  final int initialIndex;

  @override
  State<HomeScreenRefactored> createState() => _HomeScreenRefactoredState();
}

class _HomeScreenRefactoredState extends State<HomeScreenRefactored> {
  int _selectedIndex = 0;
  bool _warmupStarted = false;

  // Lazy loading das páginas - instancia apenas quando necessário
  final List<Widget?> _pages = List<Widget?>.filled(5, null);

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    
    // Cria a página inicial e dispara warmup após o primeiro frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureInitialPage();
      _startWarmupAfterFirstFrame();
    });

    // Escuta mudanças solicitadas externamente (Coordinator)
    HomeTabCoordinator.instance.addListener(_onCoordinatorTabChanged);
  }

  void _onCoordinatorTabChanged() {
    final targetIndex = HomeTabCoordinator.instance.currentIndex;
    if (targetIndex != _selectedIndex) {
      AppLogger.info('🔄 [HomeScreen] Coordinator solicitou troca para aba $targetIndex', tag: 'HOME');
      _onTappedNavBar(targetIndex);
    }
  }

  @override
  void didUpdateWidget(HomeScreenRefactored oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIndex != oldWidget.initialIndex) {
      setState(() {
        _selectedIndex = widget.initialIndex;
        _ensurePage(_selectedIndex);
      });
    }
  }

  /// Garante que a página inicial está pronta
  /// Diferente do antigo _initializeData, não espera nenhum carregamento
  void _ensureInitialPage() {
    if (!mounted) return;
    
    // Log leve para confirmar status (sem bloquear UI)
    final mapViewModel = Provider.of<MapViewModel>(context, listen: false);
    AppLogger.info(
      'Home abriu | mapReady=${mapViewModel.mapReady} | eventos=${mapViewModel.events.length}',
      tag: 'HOME',
    );
    
    setState(() {
      _ensurePage(_selectedIndex);
    });
  }

  void _startWarmupAfterFirstFrame() {
    if (!mounted) return;
    if (_warmupStarted) return;
    _warmupStarted = true;

    final mapViewModel = Provider.of<MapViewModel>(context, listen: false);
    final peopleRankingViewModel = Provider.of<PeopleRankingViewModel>(context, listen: false);
    final locationsRankingViewModel = Provider.of<RankingViewModel>(context, listen: false);
    final conversationsViewModel = Provider.of<ConversationsViewModel>(context, listen: false);

    final initializer = AppInitializerService(
      mapViewModel,
      peopleRankingViewModel,
      locationsRankingViewModel,
      conversationsViewModel,
    );

    // Não await para não travar UI; warmup roda em background
    initializer.warmupAfterFirstFrame().catchError((e, stackTrace) {
      AppLogger.error(
        'Warmup pós-primeiro-frame falhou',
        tag: 'HOME',
        error: e,
        stackTrace: stackTrace is StackTrace ? stackTrace : StackTrace.current,
      );
    });
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
        return Consumer<MapViewModel>(
          builder: (context, mapViewModel, _) => DiscoverTab(mapViewModel: mapViewModel),
        );
      case 1:
        return const ActionsTab();
      case 2:
        return Consumer2<PeopleRankingViewModel, RankingViewModel>(
          builder: (context, peopleRanking, locationsRanking, _) => RankingTab(
            peopleRankingViewModel: peopleRanking,
            locationsRankingViewModel: locationsRanking,
          ),
        );
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
  void dispose() {
    // ❌ DESATIVADO: Listener automático removido
    // PendingReviewsListenerService.instance.stopListening();
    // widget.mapViewModel.dispose(); // Agora gerenciado pelo Provider
    HomeTabCoordinator.instance.removeListener(_onCoordinatorTabChanged);
    super.dispose();
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
                  AppLogger.info('Notificações tapped', tag: 'HOME');
                },
                onFilterTap: () {
                  // TODO: Implementar abertura de filtros
                  AppLogger.info('Filtros tapped', tag: 'HOME');
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
