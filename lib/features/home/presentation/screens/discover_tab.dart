import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/features/home/presentation/screens/discover_screen.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/location_picker_page_refactored.dart';
import 'package:partiu/features/home/presentation/services/onboarding_service.dart';
import 'package:partiu/features/home/presentation/widgets/category_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/create_button.dart';
import 'package:partiu/features/home/presentation/widgets/create_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/list_button.dart';
import 'package:partiu/features/home/presentation/widgets/list_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/liquid_swipe_onboarding.dart';
import 'package:partiu/features/home/presentation/widgets/navigate_to_user_button.dart';
import 'package:partiu/features/home/presentation/widgets/people_button.dart';
import 'package:partiu/features/home/presentation/widgets/invite_drawer.dart';
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
  static const double _filtersSpacing = 8;

  bool _isShowingOnboarding = false;

  void _showCreateDrawer() async {
    final coordinator = CreateFlowCoordinator(mapViewModel: widget.mapViewModel);
    
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
        
        // Se completou o fluxo ou fechou, sair
        break;
      }
      
      break;
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

  void _showInviteDrawer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const InviteDrawer(),
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
        
        // Botão "Ganhe 3 meses grátis" (canto superior esquerdo)
        Positioned(
          top: _peopleButtonTop,
          left: _peopleButtonLeft,
          child: _InviteOverlayButton(
            onPressed: _showInviteDrawer,
          ),
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
        Positioned(
          top: _peopleButtonTop + _peopleButtonHeight + _filtersSpacing,
          left: 0,
          right: 0,
          child: ListenableBuilder(
            listenable: widget.mapViewModel,
            builder: (context, _) {
              final categories = widget.mapViewModel.availableCategories;
              final allLabel = i18n.translate('notif_filter_all');
              final totalInBounds = widget.mapViewModel.eventsInBoundsCount;
              final countsByCategory = widget.mapViewModel.eventsInBoundsCountByCategory;

              final localeTag = Localizations.localeOf(context).toLanguageTag();
              if (_lastLocaleTag != localeTag ||
                  _lastCategoryKeys.length != categories.length ||
                  !_listsEqual(_lastCategoryKeys, categories)) {
                _lastLocaleTag = localeTag;
                _lastCategoryKeys = List<String>.from(categories, growable: false);
                _cachedCategoryLabels = categories
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
                  categories.length,
                  (index) {
                    final key = categories[index].trim();
                    final label = _cachedCategoryLabels[index];
                    final count = countsByCategory[key] ?? 0;
                    return '$label ($count)';
                  },
                  growable: false,
                ),
              ];

              final selected = widget.mapViewModel.selectedCategory;
              final selectedCategoryIndex =
                selected == null ? -1 : categories.indexOf(selected);
              final selectedIndex =
                selectedCategoryIndex >= 0 ? selectedCategoryIndex + 1 : 0;

              return NotificationHorizontalFilters(
                items: items,
                selectedIndex: selectedIndex,
                onSelected: (index) {
                  if (index == 0) {
                    widget.mapViewModel.setCategoryFilter(null);
                  } else {
                    widget.mapViewModel.setCategoryFilter(categories[index - 1]);
                  }
                },
                padding: const EdgeInsets.symmetric(horizontal: 16),
                unselectedBackgroundColor: Colors.white,
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
}

class _InviteOverlayButton extends StatelessWidget {
  const _InviteOverlayButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: GlimpseColors.primary,
            borderRadius: BorderRadius.circular(100),
          ),
          alignment: Alignment.center,
          child: Text(
            'Ganhe 3 meses grátis',
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
