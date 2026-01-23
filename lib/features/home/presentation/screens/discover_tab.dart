import 'package:flutter/material.dart';
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/features/home/presentation/screens/discover_screen.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/location_picker_page_refactored.dart';
import 'package:partiu/features/home/presentation/services/map_navigation_service.dart';
import 'package:partiu/features/home/presentation/services/onboarding_service.dart';
import 'package:partiu/features/home/presentation/widgets/category_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/create_button.dart';
import 'package:partiu/features/home/presentation/widgets/create_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/list_button.dart';
import 'package:partiu/features/home/presentation/widgets/list_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/liquid_swipe_onboarding.dart';
import 'package:partiu/features/home/presentation/widgets/navigate_to_user_button.dart';
import 'package:partiu/features/home/presentation/widgets/people_button.dart';
import 'package:partiu/features/home/presentation/widgets/whatsapp_share_button.dart';
import 'package:partiu/features/home/presentation/widgets/vip_event_promo_overlay.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/features/home/presentation/screens/find_people_screen.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/notifications/widgets/notification_horizontal_filters.dart';

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

  List<String> _lastCategoryKeys = const [];
  String? _lastLocaleTag;
  List<String> _cachedCategoryLabels = const [];

  static const double _peopleButtonTop = 16;
  static const double _peopleButtonRight = 16;
  static const double _peopleButtonLeft = 16;
  static const double _peopleButtonHeight = 48;
  static const double _filtersSpacing = 16;

  bool _isShowingOnboarding = false;

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

  void _showListDrawer() {
    // Usa bottom sheet nativo
    ListDrawer.show(context, widget.mapViewModel);
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

    return Stack(
      children: [
        // Mapa Apple Maps
        DiscoverScreen(
          key: _discoverKey,
          mapViewModel: widget.mapViewModel,
        ),

        // Botão de compartilhar app (canto superior esquerdo)
        Positioned(
          top: _peopleButtonTop,
          left: _peopleButtonLeft,
          child: const WhatsAppShareButton(),
        ),

        // Botão "Perto de você" (canto superior direito)
        Positioned(
          top: _peopleButtonTop,
          right: _peopleButtonRight,
          child: PeopleButton(
            onPressed: _showPeopleNearby,
          ),
        ),

        // Filtro dinâmico por categoria (abaixo do PeopleButton)
        // Só exibe se houver eventos no mapa E o mapa estiver pronto
        Positioned(
          top: _peopleButtonTop + _peopleButtonHeight + _filtersSpacing,
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
              final countsByCategory = widget.mapViewModel.eventsInBoundsCountByCategory;

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

              final allItem = '$allLabel ($totalInBounds)';
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

              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: NotificationHorizontalFilters(
                  key: ValueKey('filters_$totalInBounds'),
                  items: items,
                  selectedIndex: selectedIndex,
                  onSelected: (index) {
                    if (index == 0) {
                      widget.mapViewModel.setCategoryFilter(null);
                    } else {
                      widget.mapViewModel.setCategoryFilter(categoriesWithCarnaval[index - 1]);
                    }
                  },
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  unselectedBackgroundColor: Colors.white,
                ),
              );
            },
          ),
        ),

        // Promo horizontal do(s) evento(s) de criadores VIP (abaixo do filtro)
        Positioned(
          top: _peopleButtonTop + _peopleButtonHeight + _filtersSpacing + 54,
          left: 16,
          right: 0,
          child: ListenableBuilder(
            listenable: widget.mapViewModel,
            builder: (context, _) {
              if (!widget.mapViewModel.mapReady) {
                return const SizedBox.shrink();
              }

              return VipEventPromoOverlay(
                events: widget.mapViewModel.events,
                visibleBounds: widget.mapViewModel.visibleBounds,
                onEventTap: (event) async {
                  // Reusar o mesmo fluxo do marker: abrir EventCard.
                  // (O handler faz preload/stream via EventCardController)
                  final controller = EventCardController(
                    eventId: event.id,
                    preloadedEvent: event,
                  );
                  // Aguarda carregar dados adicionais + avatares ANTES de mostrar o card
                  await controller.load();
                  await controller.preloadAvatarsAsync();
                  
                  if (!mounted) return;
                  
                  EventCard.show(
                    context: context,
                    controller: controller,
                    onActionPressed: () {},
                  );
                },
              );
            },
          ),
        ),
        
        // Botão de centralizar no usuário
        Positioned(
          right: 16,
          bottom: 96, // 24 (bottom do CreateButton) + 56 (tamanho do FAB) + 16 (espaçamento)
          child: NavigateToUserButton(
            onPressed: _centerOnUser,
          ),
        ),
        
        // Botão de lista de atividades (centro inferior)
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: ListButton(
              onPressed: _showListDrawer,
            ),
          ),
        ),
        
        // Botão flutuante para criar atividade
        Positioned(
          right: 16,
          bottom: 24,
          child: CreateButton(
            onPressed: _handleCreatePressed,
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
    if (categories.contains(carnavalKey)) {
      return <String>[carnavalKey, ...categories.where((c) => c != carnavalKey)];
    }
    return <String>[carnavalKey, ...categories];
  }
}
