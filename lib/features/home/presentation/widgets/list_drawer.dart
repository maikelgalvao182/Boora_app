import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/data/models/event_location.dart';
import 'package:partiu/features/home/data/services/map_discovery_service.dart';
import 'package:partiu/features/home/presentation/services/map_navigation_service.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/list_card.dart';
import 'package:partiu/features/home/presentation/widgets/list_card/list_card_controller.dart';
import 'package:partiu/features/home/presentation/widgets/list_drawer/list_drawer_controller.dart';
import 'package:partiu/features/notifications/widgets/notification_horizontal_filters.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/features/home/presentation/widgets/list_card_shimmer.dart';

/// Cache global de ListCardController para evitar recriação
class ListCardControllerCache {
  static final Map<String, ListCardController> _cache = {};

  /// Obtém ou cria um controller para o eventId
  static ListCardController get(String eventId) {
    return _cache.putIfAbsent(
      eventId,
      () {
        debugPrint('🎯 ListCardControllerCache: Criando controller para $eventId');
        return ListCardController(eventId: eventId);
      },
    );
  }
  
  /// Limpa o cache (útil para testes ou memory management)
  static void clear() {
    _cache.clear();
    debugPrint('🗑️ ListCardControllerCache: Cache limpo');
  }
  
  /// Remove um controller específico
  static void remove(String eventId) {
    _cache.remove(eventId);
    debugPrint('🗑️ ListCardControllerCache: Controller $eventId removido');
  }
}

/// Bottom sheet para exibir lista de atividades na região
/// 
/// ✅ Usa ListDrawerController (singleton) para gerenciar lista
/// ✅ Cache de controllers por eventId
/// ✅ Bottom sheet nativo do Flutter
/// ✅ Filtro horizontal por categoria integrado com MapViewModel
class ListDrawer extends StatelessWidget {
  const ListDrawer({
    super.key,
    required this.mapViewModel,
  });

  final MapViewModel mapViewModel;

  /// Mostra o bottom sheet
  static Future<void> show(BuildContext context, MapViewModel mapViewModel) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => ListDrawer(mapViewModel: mapViewModel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Container(
      height: screenHeight * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle e header
          Padding(
            padding: const EdgeInsets.only(
              top: 12,
              left: 20,
              right: 20,
            ),
            child: Column(
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: GlimpseColors.borderColorLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Título centralizado
                Text(
                  i18n.translate('activities_in_region'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: GlimpseColors.primaryColorLight,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),

          // Filtro horizontal por categoria
          _CategoryFilterBar(mapViewModel: mapViewModel),

          const SizedBox(height: 8),

          // Lista de atividades
          Expanded(
            child: _ListDrawerContent(mapViewModel: mapViewModel),
          ),
        ],
      ),
    );
  }
}

/// Barra de filtro horizontal por categoria
class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({required this.mapViewModel});

  final MapViewModel mapViewModel;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: mapViewModel,
      builder: (context, _) {
        final categories = mapViewModel.availableCategories;
        final allLabel = i18n.translate('notif_filter_all');
        final totalInBounds = mapViewModel.eventsInBoundsCount;
        final countsByCategory = mapViewModel.eventsInBoundsCountByCategory;

        // Build labels for each category with counts
        final categoryLabels = categories.map((key) {
          final normalized = key.trim();
          if (normalized.isEmpty) return key;
          final translated = i18n.translate('category_$normalized');
          return translated.isEmpty ? key : translated;
        }).toList(growable: false);

        final allItem = '$allLabel ($totalInBounds)';
        final items = <String>[
          allItem,
          ...List<String>.generate(
            categories.length,
            (index) {
              final key = categories[index].trim();
              final label = categoryLabels[index];
              final count = countsByCategory[key] ?? 0;
              return '$label ($count)';
            },
            growable: false,
          ),
        ];

        final selected = mapViewModel.selectedCategory;
        final selectedCategoryIndex =
            selected == null ? -1 : categories.indexOf(selected);
        final selectedIndex =
            selectedCategoryIndex >= 0 ? selectedCategoryIndex + 1 : 0;

        return NotificationHorizontalFilters(
          items: items,
          selectedIndex: selectedIndex,
          onSelected: (index) {
            if (index == 0) {
              mapViewModel.setCategoryFilter(null);
            } else {
              mapViewModel.setCategoryFilter(categories[index - 1]);
            }
          },
          padding: const EdgeInsets.symmetric(horizontal: 16),
          unselectedBackgroundColor: GlimpseColors.lightTextField,
        );
      },
    );
  }
}

/// Conteúdo interno do drawer (separado para usar controller)
class _ListDrawerContent extends StatelessWidget {
  const _ListDrawerContent({required this.mapViewModel});

  final MapViewModel mapViewModel;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final controller = ListDrawerController();
    final discoveryService = MapDiscoveryService();
    
    // Usuário não autenticado
    if (controller.currentUserId == null) {
      return Center(
        child: GlimpseEmptyState.standard(
          text: i18n.translate('user_not_authenticated'),
        ),
      );
    }

    // Wrap everything with ListenableBuilder to react to category changes
    return ListenableBuilder(
      listenable: mapViewModel,
      builder: (context, _) {
        final selectedCategory = mapViewModel.selectedCategory;

        // ValueNotifier de eventos próximos (Singleton - lista viva sem rebuild)
        return ValueListenableBuilder<List<EventLocation>>(
          valueListenable: discoveryService.nearbyEvents,
          builder: (context, nearbyEventsList, _) {
            // Filtrar eventos pela categoria selecionada
            final filteredNearbyEvents = selectedCategory == null
                ? nearbyEventsList
                : nearbyEventsList.where((event) {
                    final eventCategory = event.category?.trim();
                    return eventCategory == selectedCategory.trim();
                  }).toList();

            final hasNearbyEvents = filteredNearbyEvents.isNotEmpty;

        // ValueListenableBuilder para "Minhas atividades"
        return ValueListenableBuilder<bool>(
          valueListenable: controller.isLoadingMyEvents,
          builder: (context, isLoading, _) {
            // Loading state inicial
            if (isLoading && controller.myEvents.value.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SizedBox(height: 20),
                    ListCardShimmer(),
                    ListCardShimmer(),
                    ListCardShimmer(),
                  ],
                ),
              );
            }

            return ValueListenableBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              valueListenable: controller.myEvents,
              builder: (context, myEventsList, _) {
                final hasMyEvents = myEventsList.isNotEmpty;

                // Empty state
                if (!hasNearbyEvents && !hasMyEvents) {
                  return Center(
                    child: GlimpseEmptyState.standard(
                      text: i18n.translate('no_activities_found'),
                    ),
                  );
                }

                // Content with data
                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // SEÇÃO: Atividades próximas (do mapa)
                        if (hasNearbyEvents) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 24, bottom: 16),
                            child: _buildSectionLabel(i18n.translate('nearby_activities')),
                          ),
                          _buildNearbyEventsList(context, filteredNearbyEvents),
                        ],

                        // SEÇÃO: Minhas atividades
                        if (hasMyEvents) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 16),
                            child: _buildSectionLabel(i18n.translate('my_activities')),
                          ),
                          _buildMyEventsList(context, myEventsList),
                        ],
                        
                        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
          },
        );
      },
    );
  }

  /// Constrói label de seção
  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.getFont(
        FONT_PLUS_JAKARTA_SANS,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: GlimpseColors.textSubTitle,
      ),
    );
  }

  /// Constrói lista de eventos criados pelo usuário
  Widget _buildMyEventsList(BuildContext context, List<QueryDocumentSnapshot<Map<String, dynamic>>> myEventsList) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: myEventsList.length,
      itemBuilder: (context, index) {
        final eventDoc = myEventsList[index];
        return _EventCardWrapper(
          key: ValueKey('my_${eventDoc.id}'),
          eventId: eventDoc.id,
          onEventTap: () => _handleEventTap(context, eventDoc.id),
        );
      },
    );
  }

  /// Constrói lista de eventos próximos (do mapa)
  Widget _buildNearbyEventsList(BuildContext context, List<EventLocation> events) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return _EventCardWrapper(
          key: ValueKey('nearby_${event.eventId}'),
          eventId: event.eventId,
          onEventTap: () => _handleEventTap(context, event.eventId),
        );
      },
    );
  }

  /// Manipula tap em um evento
  void _handleEventTap(BuildContext context, String eventId) {
    // Fechar o bottom sheet
    Navigator.of(context).pop();
    
    // Navegar para o marker no mapa
    MapNavigationService.instance.navigateToEvent(eventId);
  }
}

/// Widget wrapper para ListCard com cache de controller
/// Separado para evitar rebuilds desnecessários
class _EventCardWrapper extends StatefulWidget {
  const _EventCardWrapper({
    super.key,
    required this.eventId,
    required this.onEventTap,
  });

  final String eventId;
  final VoidCallback onEventTap;

  @override
  State<_EventCardWrapper> createState() => _EventCardWrapperState();
}

class _EventCardWrapperState extends State<_EventCardWrapper> {
  late final ListCardController _controller;

  @override
  void initState() {
    super.initState();
    // Usa cache - nunca recria o controller
    _controller = ListCardControllerCache.get(widget.eventId);
    // Dispara load apenas se ainda não carregou
    _controller.load();
  }

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder reage apenas quando dados estão prontos
    return ValueListenableBuilder<bool>(
      valueListenable: _controller.dataReadyNotifier,
      builder: (context, isReady, _) {
        return ListCard(
          controller: _controller,
          onTap: widget.onEventTap,
        );
      },
    );
  }
}
