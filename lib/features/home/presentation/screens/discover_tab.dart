import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:math' as math;
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/features/home/presentation/screens/discover_screen.dart';
import 'package:partiu/features/home/presentation/screens/event_creator_filters_screen.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/location_picker_page_refactored.dart';
import 'package:partiu/features/home/presentation/services/map_navigation_service.dart';
import 'package:partiu/features/home/presentation/services/onboarding_service.dart';
import 'package:partiu/features/home/presentation/widgets/category_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/create_button.dart';
import 'package:partiu/features/home/presentation/widgets/create_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/date_filter_calendar.dart';
import 'package:partiu/features/home/presentation/widgets/event_filter_button.dart';
import 'package:partiu/features/home/presentation/widgets/list_button.dart';
import 'package:partiu/features/home/presentation/widgets/list_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/liquid_swipe_onboarding.dart';
import 'package:partiu/features/home/presentation/widgets/navigate_to_user_button.dart';
import 'package:partiu/features/home/presentation/widgets/people_button.dart';
import 'package:partiu/features/home/presentation/widgets/whatsapp_share_button.dart';
import 'package:partiu/features/home/presentation/widgets/vip_event_promo_overlay.dart';
import 'package:partiu/features/home/presentation/screens/find_people_screen.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/notifications/widgets/notification_horizontal_filters.dart';
import 'package:partiu/features/home/presentation/widgets/map_controllers/event_card_presenter.dart';
import 'package:partiu/shared/widgets/animated_visibility.dart';
import 'package:partiu/features/event_photo_feed/presentation/services/feed_reminder_service.dart';
import 'package:partiu/features/event_photo_feed/presentation/widgets/feed_reminder_card.dart';

import 'package:partiu/features/home/presentation/coordinators/home_tab_coordinator.dart';

/// Tela de descoberta (Tab 0)
/// Exibe mapa interativo com atividades próximas
class DiscoverTab extends StatefulWidget {
  const DiscoverTab({
    super.key,
    required this.mapViewModel,
  });

  final MapViewModel mapViewModel;

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab> {
  final GlobalKey<DiscoverScreenState> _discoverKey = GlobalKey<DiscoverScreenState>();
  late final EventCardPresenter _eventPresenter;

  /// Controla a visibilidade do ListButton
  bool _listButtonVisible = true;

  List<String> _lastCategoryKeys = const [];
  String? _lastLocaleTag;
  List<String> _cachedCategoryLabels = const [];

  static const double _peopleButtonTop = 16;
  static const double _peopleButtonRight = 16;
  static const double _peopleButtonLeft = 16;
  static const double _peopleButtonHeight = 56;
  static const double _peopleToCategorySpacing = 8;
  static const double _categoryFiltersHeight = 32;
  static const double _categoryToVipSpacing = 8;

  bool _isShowingOnboarding = false;

  // Feed reminder card state
  FeedReminderResult? _feedReminderResult;
  bool _feedReminderVisible = false;
  bool _feedReminderEvaluated = false;

  @override
  void initState() {
    super.initState();
    _eventPresenter = EventCardPresenter(viewModel: widget.mapViewModel);

    // Escuta mudanças de aba para tentar consumir pendências quando esta aba virar ativa
    HomeTabCoordinator.instance.addListener(_onTabCoordinatorChanged);
    
    // Tenta consumir pendências (caso inicialização direta em aba 0)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryConsumePending();
      _evaluateFeedReminder();
    });
  }
  
  @override
  void dispose() {
    HomeTabCoordinator.instance.removeListener(_onTabCoordinatorChanged);
    super.dispose();
  }

  void _onTabCoordinatorChanged() {
    if (HomeTabCoordinator.instance.currentIndex == 0) {
      _tryConsumePending();
    }
  }

  /// Avalia se deve exibir o card de lembrete do feed
  Future<void> _evaluateFeedReminder() async {
    if (_feedReminderEvaluated) return;
    _feedReminderEvaluated = true;

    final result = await FeedReminderService.instance.evaluate();
    if (!mounted) return;

    if (result.shouldShow) {
      await FeedReminderService.instance.markShown();
      if (!mounted) return;
      setState(() {
        _feedReminderResult = result;
        _feedReminderVisible = true;
      });
    }
  }

  void _dismissFeedReminder() {
    setState(() {
      _feedReminderVisible = false;
      _feedReminderResult = null;
    });
  }

  void _tryConsumePending() {
    final pendingId = MapNavigationService.instance.pendingEventId;
    if (pendingId == null) return;

    // Só faz sentido se eu estiver montado
    if (!mounted) return;
    
    debugPrint('🔎 [DiscoverTab] _tryConsumePending: Encontrado $pendingId. Disparando navegação...');
    // Se o mapa estiver pronto e registrado, ele consumirá agora.
    MapNavigationService.instance.tryConsumePending();
  }

  void _showCreateDrawer() async {
    final coordinator = CreateFlowCoordinator(mapViewModel: widget.mapViewModel);
    
    // Variável para armazenar resultado final com activityId se criação bem-sucedida
    Map<String, dynamic>? finalResult;
    
    // Loop para gerenciar navegação entre drawers
    while (true) {
      // Mostra CreateDrawer (nunca em editMode no fluxo de criação)
      final createResult = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => CreateDrawer(
          coordinator: coordinator,
          initialName: coordinator.draft.activityText,
          initialEmoji: coordinator.draft.emoji,
        ),
      );

      if (!mounted) return;

      // Se fechou sem ação, sair do fluxo
      if (createResult == null) break;

      // Se pediu para abrir CategoryDrawer
      if (createResult['action'] == 'openCategory') {
        final categoryResult = await _showCategoryFlow(coordinator);

        if (!mounted) return;
        
        // Se voltou do CategoryDrawer, continua o loop para reabrir CreateDrawer
        if (categoryResult != null && categoryResult['action'] == 'back') {
          continue;
        }
        
        // Verificar se completou o fluxo com sucesso
        if (categoryResult != null && categoryResult['participants'] != null) {
          final participants = categoryResult['participants'] as Map<String, dynamic>;
          if (participants['success'] == true && participants['navigateToEvent'] == true) {
            finalResult = participants;
          }
        }
        
        // Se completou o fluxo ou fechou, sair
        break;
      }
      
      break;
    }
    
    // ✅ Após todos os drawers fecharem, navegar para o evento se criação foi bem-sucedida
    if (finalResult != null && finalResult['activityId'] != null && mounted) {
      // Pequeno delay para garantir que a UI está estável
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (mounted) {
        MapNavigationService.instance.navigateToEvent(
          finalResult['activityId'] as String,
          showConfetti: true,
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _showCategoryFlow(CreateFlowCoordinator coordinator) async {
    // Loop para gerenciar navegação entre CategoryDrawer, ScheduleDrawer e LocationPicker
    while (true) {
      final categoryResult = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => CategoryDrawer(
          coordinator: coordinator,
          initialCategory: coordinator.draft.category,
        ),
      );

      if (!mounted) return null;

      // Se voltou para CreateDrawer
      if (categoryResult != null && categoryResult['action'] == 'back') {
        return categoryResult;
      }

      // Se fechou sem resultado, sair
      if (categoryResult == null) return null;

      // Se pediu para abrir LocationPicker (veio do ScheduleDrawer)
      if (categoryResult['action'] == 'openLocationPicker') {
        final locationResult = await _showLocationPickerFlow(coordinator);

        if (!mounted) return null;
        
        // Se voltou do LocationPicker, continua o loop para reabrir CategoryDrawer/ScheduleDrawer
        if (locationResult != null && locationResult['action'] == 'back') {
          continue;
        }
        
        // Fluxo completado ou cancelado
        return locationResult;
      }
      
      return categoryResult;
    }
  }

  Future<Map<String, dynamic>?> _showLocationPickerFlow(CreateFlowCoordinator coordinator) async {
    final locationResult = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPageRefactored(
          coordinator: coordinator,
        ),
        fullscreenDialog: true,
      ),
    );

    return locationResult;
  }

  void _showListDrawer() async {
    // Esconde o ListButton
    setState(() => _listButtonVisible = false);
    
    // Mostra o bottom sheet e espera fechar
    await ListDrawer.show(context, widget.mapViewModel);
    
    // Mostra o ListButton de volta
    if (mounted) {
      setState(() => _listButtonVisible = true);
    }
  }

  void _centerOnUser() {
    _discoverKey.currentState?.centerOnUser();
  }

  void _showPeopleNearby() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const FindPeopleScreen(),
      ),
    );
  }

  void _showEventCreatorFilters() async {
    final result = await EventCreatorFiltersScreen.show(context);
    if (result == true && mounted) {
      // Filtros aplicados - recarregar eventos
      widget.mapViewModel.reloadEvents();
    }
  }

  Future<void> _showOnboarding() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) {
          return LiquidSwipeOnboarding(
            onComplete: () {
              if (Navigator.of(routeContext).canPop()) {
                Navigator.of(routeContext).pop();
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _handleCreatePressed() async {
    if (_isShowingOnboarding) return;

    final completed = await OnboardingService.instance.isOnboardingCompleted();
    if (!mounted) return;

    if (completed) {
      _showCreateDrawer();
      return;
    }

    final alreadyTapped =
        await OnboardingService.instance.hasFirstCreateOverlayTapOccurred();
    if (!alreadyTapped) {
      await OnboardingService.instance.markFirstCreateOverlayTap();
    }

    if (!mounted) return;

    _isShowingOnboarding = true;
    try {
      await _showOnboarding();
    } finally {
      _isShowingOnboarding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLargeScreen = screenWidth > 390;
    final largeScreenExtraSpacing = screenWidth > 390 ? 4.h : 0.0;
    final peopleToCategorySpacing = _peopleToCategorySpacing.h + largeScreenExtraSpacing;
    final categoryToVipSpacing = _categoryToVipSpacing.h + largeScreenExtraSpacing;
    final effectivePeopleHeight = isLargeScreen ? math.min(56.0, 56.w) : 56.h;
    final effectiveCategoryFiltersHeight = isLargeScreen ? math.min(32.0, 32.h) : 40.h;

    return Stack(
      children: [
        // Mapa Apple Maps
        DiscoverScreen(
          key: _discoverKey,
          mapViewModel: widget.mapViewModel,
        ),

        // Linha superior de overlays (calendário + people) orientada por constraints
        Positioned(
          top: _peopleButtonTop.h,
          left: _peopleButtonLeft.w,
          right: _peopleButtonRight.w,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalGap = 8.w;
              final reservedPeopleWidth = 176.w;
              final dateAvailableWidth = (constraints.maxWidth - reservedPeopleWidth - horizontalGap)
                  .clamp(120.w, constraints.maxWidth);

              return Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: dateAvailableWidth,
                      child: ListenableBuilder(
                        listenable: widget.mapViewModel,
                        builder: (context, _) {
                          return DateFilterCalendar(
                            selectedDate: widget.mapViewModel.selectedDate,
                            onDateSelected: (date) {
                              widget.mapViewModel.setDateFilter(date);
                            },
                            availableWidth: dateAvailableWidth,
                          );
                        },
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PeopleButton(
                      onPressed: _showPeopleNearby,
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // Filtro dinâmico por categoria (abaixo do PeopleButton)
        // Só exibe se houver eventos no mapa E o mapa estiver pronto
        Positioned(
          top: _peopleButtonTop.h + effectivePeopleHeight + peopleToCategorySpacing,
          left: 0,
          right: 0,
          child: ListenableBuilder(
            listenable: widget.mapViewModel,
            builder: (context, _) {
              final totalInBounds = widget.mapViewModel.eventsInBoundsCount;
              
              // Não renderiza se o mapa não estiver pronto ou não houver eventos
              if (!widget.mapViewModel.mapReady || totalInBounds == 0) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: const SizedBox.shrink(),
                );
              }
              
              final categories = widget.mapViewModel.availableCategories;
              final categoriesWithCarnaval = _withCarnavalCategory(categories);
              final allLabel = i18n.translate('notif_filter_all');
              // Usa contagens já filtradas por data
              final countsByCategory = widget.mapViewModel.eventsInBoundsCountByCategory;
              // Total filtrado por data (para "Todas")
              final filteredTotal = countsByCategory.values.fold<int>(0, (sum, c) => sum + c);

              final localeTag = Localizations.localeOf(context).toLanguageTag();
              if (_lastLocaleTag != localeTag ||
                  _lastCategoryKeys.length != categoriesWithCarnaval.length ||
                  !_listsEqual(_lastCategoryKeys, categoriesWithCarnaval)) {
                _lastLocaleTag = localeTag;
                _lastCategoryKeys = List<String>.from(categoriesWithCarnaval, growable: false);
                _cachedCategoryLabels = categoriesWithCarnaval
                    .map((key) {
                      final normalized = key.trim();
                      if (normalized.isEmpty) return key;
                      // As categorias são salvas como chaves (ex: gastronomy, sports)
                      // e traduzidas via i18n (ex: category_gastronomy)
                      final translated = i18n.translate('category_$normalized');
                      // Fallback: se não houver tradução, usa a chave original
                      return translated.isEmpty ? key : translated;
                    })
                    .toList(growable: false);
              }

              final allItem = '$allLabel ($filteredTotal)';
              final items = <String>[
                allItem,
                ...List<String>.generate(
                  categoriesWithCarnaval.length,
                  (index) {
                    final key = categoriesWithCarnaval[index].trim();
                    final label = _cachedCategoryLabels[index];
                    final count = countsByCategory[key] ?? 0;
                    return '$label ($count)';
                  },
                  growable: false,
                ),
              ];

              final selected = widget.mapViewModel.selectedCategory;
              final selectedCategoryIndex =
                selected == null ? -1 : categoriesWithCarnaval.indexOf(selected);
              final selectedIndex =
                selectedCategoryIndex >= 0 ? selectedCategoryIndex + 1 : 0;
              
              // Key inclui data selecionada para forçar rebuild quando filtro muda
              final selectedDateKey = widget.mapViewModel.selectedDate?.toIso8601String() ?? 'all';
              final sidePadding = MediaQuery.sizeOf(context).width <= 390 ? 12.w : 16.w;

              return NotificationHorizontalFilters(
                key: ValueKey('filters_${filteredTotal}_$selectedDateKey'),
                items: items,
                selectedIndex: selectedIndex,
                onSelected: (index) {
                  if (index == 0) {
                    widget.mapViewModel.setCategoryFilter(null);
                  } else {
                    widget.mapViewModel.setCategoryFilter(categoriesWithCarnaval[index - 1]);
                  }
                },
                padding: EdgeInsets.symmetric(horizontal: sidePadding),
                unselectedBackgroundColor: Colors.white,
              );
            },
          ),
        ),

        // Promo horizontal do(s) evento(s) de criadores VIP (abaixo do filtro)
        Positioned(
          top: _peopleButtonTop.h +
            effectivePeopleHeight +
              peopleToCategorySpacing +
              effectiveCategoryFiltersHeight +
              categoryToVipSpacing,
          left: 0,
          right: 0,
          child: ListenableBuilder(
            listenable: widget.mapViewModel,
            builder: (context, _) {
              if (!widget.mapViewModel.mapReady) {
                return const SizedBox.shrink();
              }

              final sidePadding = MediaQuery.sizeOf(context).width <= 390 ? 12.w : 16.w;

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: sidePadding),
                child: VipEventPromoOverlay(
                  events: widget.mapViewModel.events,
                  visibleBounds: widget.mapViewModel.visibleBounds,
                  onEventTap: (event) async {
                    if (!mounted) return;
                    await _eventPresenter.onMarkerTap(context, event);
                  },
                ),
              );
            },
          ),
        ),
        
        // Botão de centralizar no usuário + Spinner de carregamento (Zoom Out) + Compartilhar
        Positioned(
          right: 16,
          bottom: bottomInset + 96, // 24 (bottom do CreateButton) + 56 (tamanho do FAB) + 16 (espaçamento)
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListenableBuilder(
                listenable: widget.mapViewModel,
                builder: (context, _) {
                  // Mostrar apenas se estiver carregando E em zoom baixo (≤5.0)
                  final isZoomOut = widget.mapViewModel.currentZoom <= 5.0;
                  final isLoading = widget.mapViewModel.isLoading;

                  if (isLoading && isZoomOut) {
                    return Container(
                      margin: EdgeInsets.only(bottom: 12.h),
                      width: 56.w,
                      height: 56.h,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: CupertinoActivityIndicator(radius: 10),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              // Botão de compartilhar app (mesmo tamanho do NavigateToUserButton - 56x56)
              Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: WhatsAppShareButton(),
              ),
              // Botão de filtro de eventos (por criador)
              Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: EventFilterButton(
                  onPressed: _showEventCreatorFilters,
                ),
              ),
              NavigateToUserButton(
                onPressed: _centerOnUser,
              ),
            ],
          ),
        ),
        
        // Botão de lista de atividades (centro inferior)
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomInset + 24,
          child: Center(
            child: AnimatedVisibility(
              visible: _listButtonVisible,
              child: ListButton(
                onPressed: _showListDrawer,
              ),
            ),
          ),
        ),
        
        // Botão flutuante para criar atividade
        Positioned(
          right: 16,
          bottom: bottomInset + 24,
          child: CreateButton(
            onPressed: _handleCreatePressed,
          ),
        ),

        // Card flutuante de lembrete para postar fotos no feed
        if (_feedReminderVisible && _feedReminderResult != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 96,
            child: FeedReminderCard(
              reminderType: _feedReminderResult!.type!,
              onDismiss: _dismissFeedReminder,
            ),
          ),
      ],
    );
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<String> _withCarnavalCategory(List<String> categories) {
    const carnavalKey = 'carnaval';
    // Só adiciona carnaval no topo se já existir na lista
    if (categories.contains(carnavalKey)) {
      return <String>[carnavalKey, ...categories.where((c) => c != carnavalKey)];
    }
    // Não adiciona carnaval artificialmente se não há eventos de carnaval
    return categories;
  }
}
