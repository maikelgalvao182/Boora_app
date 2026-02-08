import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/presentation/viewmodels/people_ranking_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/people_ranking_card.dart';
import 'package:partiu/features/home/presentation/widgets/people_ranking_card_shimmer.dart';
import 'package:partiu/features/home/presentation/state/people_ranking_state.dart';
import 'package:partiu/features/notifications/widgets/notification_horizontal_filters.dart';
import 'package:partiu/features/notifications/widgets/notification_filter_shimmer.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/glimpse_tab_app_bar.dart';
import 'package:partiu/shared/widgets/outline_horizontal_filter.dart';
import 'package:partiu/shared/widgets/pull_to_refresh.dart';

/// Tela de ranking (Tab 2)
/// 
/// Exibe ranking de locais por eventos hospedados
class RankingTab extends StatefulWidget {
  const RankingTab({
    super.key,
    required this.peopleRankingViewModel,
    required this.locationsRankingViewModel,
  });
  
  final PeopleRankingViewModel peopleRankingViewModel;
  // Mantido por compatibilidade com o código existente, mas a UI de "Lugares"
  // foi desativada (página agora exibe apenas o ranking de pessoas).
  // ignore: unused_field
  final dynamic locationsRankingViewModel;

  @override
  State<RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<RankingTab> {
  late final PeopleRankingViewModel _peopleViewModel;
  late final PeopleRankingState _peopleState;

  @override
  void initState() {
    super.initState();
    debugPrint('🎴 [RankingTab] initState');
    debugPrint('   - ViewModel loadState: ${widget.peopleRankingViewModel.loadState}');
    debugPrint('   - ViewModel hasLoadedOnce: ${widget.peopleRankingViewModel.hasLoadedOnce}');
    debugPrint('   - ViewModel isInitialLoading: ${widget.peopleRankingViewModel.isInitialLoading}');
    debugPrint('   - ViewModel peopleRankings.length: ${widget.peopleRankingViewModel.peopleRankings.length}');
    
    // Usar o ViewModel pré-carregado do AppInitializer
    _peopleViewModel = widget.peopleRankingViewModel;
    
    // Criar state holders com listas master
    _peopleState = PeopleRankingState(_peopleViewModel.peopleRankings);
    
    _peopleViewModel.addListener(_onPeopleViewModelChanged);
    _peopleState.addListener(_onPeopleStateChanged);

    // 🚀 Lazy init por rota: Splash não garante preload completo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (!_peopleViewModel.hasLoadedOnce && !_peopleViewModel.isLoading) {
        unawaited(() async {
          try {
            // 🚫 Evitar requests extras de estados/cidades (UI deriva filtros localmente)
            await _peopleViewModel.initialize(loadFilters: false);
          } catch (_) {
            // Erro já é tratado/exposto pelo ViewModel.
          }
        }());
      }
    });
  }

  @override
  void dispose() {
    _peopleViewModel.removeListener(_onPeopleViewModelChanged);
    _peopleState.removeListener(_onPeopleStateChanged);
    _peopleState.dispose();
    // Não fazer dispose dos ViewModels pois eles são compartilhados
    super.dispose();
  }

  void _onPeopleViewModelChanged() {
    // Atualizar master list no state quando ViewModel recarregar
    // 🔥 CORREÇÃO: Passar flag isRefreshing para evitar limpeza indevida
    _peopleState.updateMaster(
      _peopleViewModel.peopleRankings,
      isRefreshing: _peopleViewModel.isRefreshing,
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _onPeopleStateChanged() {
    // State mudou (filtro aplicado) - apenas rebuild
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlimpseTabAppBar(
              title: i18n.translate('ranking_title').isNotEmpty
                  ? i18n.translate('ranking_title')
                  : 'Ranking',
            ),
            SizedBox(height: 8.h),

            // Importante: UI de tabs (incluindo "Lugares" e a Glimpse tab header)
            // foi removida. Esta página agora mostra apenas o conteúdo de "Pessoas".
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Loading state com shimmer (apenas no carregamento inicial)
    if (_peopleViewModel.isInitialLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Container fixo para o shimmer do filtro
          SizedBox(
            height: 56.h, // Altura fixa para manter espaço consistente
            child: NotificationFilterShimmer(),
          ),
          
          SizedBox(height: 12.h),
          
          // Lista de shimmer cards
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              itemBuilder: (context, index) => const PeopleRankingCardShimmer(),
            ),
          ),
        ],
      );
    }

    // Error state
    if (_peopleViewModel.error != null) {
      return Center(
        child: GlimpseEmptyState.standard(
          text: _peopleViewModel.error!,
        ),
      );
    }

    // Mostrar apenas ranking de pessoas
    return _buildPeopleRankingList();
  }

  Widget _buildPeopleRankingList() {
    debugPrint('👥 [RankingTab] _buildPeopleRankingList');
    
    final master = _peopleState.master;
    final visibleIds = _peopleState.visibleIds;
    final states = _peopleState.availableStates;
    final cities = _peopleState.availableCities;
    
    debugPrint('   - master.length: ${master.length}');
    debugPrint('   - visibleIds.length: ${visibleIds.length}');
    debugPrint('   - states.length: ${states.length}');
    debugPrint('   - cities.length: ${cities.length}');
    debugPrint('   - loadState: ${_peopleViewModel.loadState}');
    debugPrint('   - isLoading: ${_peopleViewModel.isLoading}');
    debugPrint('   - isInitialLoading: ${_peopleViewModel.isInitialLoading}');
    debugPrint('   - shouldShowEmptyState: ${_peopleViewModel.shouldShowEmptyState}');
    debugPrint('   - displayedRankings.length: ${_peopleState.displayedRankings.length}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Container para ambos os filtros (altura consistente)
        Column(
          children: [
            // Filtro de Estado (padrão)
            if (states.isNotEmpty)
              SizedBox(
                height: 48.h,
                child: _buildStateFilter(states),
              ),
            
            if (states.isNotEmpty && cities.isNotEmpty)
              SizedBox(height: 8.h),
            
            // Filtro de Cidade (outline)
            if (cities.isNotEmpty)
              SizedBox(
                height: 38.h,
                child: _buildCityFilter(cities),
              ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        // Lista de pessoas - 🚀 Sempre mantém Scrollable (com empty state dentro se necessário)
        Expanded(
          child: PlatformPullToRefresh(
            onRefresh: () async {
              debugPrint('🔄 [RankingTab] Pull-to-refresh INICIADO (pessoas)');
              debugPrint('   - ANTES: displayedRankings.length = ${_peopleState.displayedRankings.length}');
              debugPrint('   - ANTES: loadState = ${_peopleViewModel.loadState}');
              debugPrint('   - ANTES: shouldShowEmptyState = ${_peopleViewModel.shouldShowEmptyState}');
              
              // 🚫 Evitar refresh de estados/cidades (derivados da lista master)
              await _peopleViewModel.refresh(loadFilters: false);
              
              debugPrint('🔄 [RankingTab] Pull-to-refresh COMPLETO (pessoas)');
              debugPrint('   - DEPOIS: displayedRankings.length = ${_peopleState.displayedRankings.length}');
              debugPrint('   - DEPOIS: loadState = ${_peopleViewModel.loadState}');
              debugPrint('   - DEPOIS: shouldShowEmptyState = ${_peopleViewModel.shouldShowEmptyState}');
            },
            itemCount: _peopleState.displayedRankings.isEmpty && _peopleViewModel.shouldShowEmptyState
                ? 1 // Empty state como item único
                : _peopleState.displayedRankings.length,
            itemBuilder: (context, index) {
              debugPrint('🏗️ [RankingTab] itemBuilder chamado - index: $index');
              debugPrint('   - displayedRankings.isEmpty: ${_peopleState.displayedRankings.isEmpty}');
              debugPrint('   - shouldShowEmptyState: ${_peopleViewModel.shouldShowEmptyState}');
              
              // Mostrar empty state quando vazio E já carregou
              if (_peopleState.displayedRankings.isEmpty && _peopleViewModel.shouldShowEmptyState) {
                debugPrint('   ⚠️ Renderizando EMPTY STATE');
                final i18n = AppLocalizations.of(context);
                final emptyText = i18n.translate('ranking_people_empty').isNotEmpty
                    ? i18n.translate('ranking_people_empty')
                    : 'Nenhuma pessoa no ranking ainda';
                return SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: Center(
                    child: GlimpseEmptyState.standard(
                      text: emptyText,
                    ),
                  ),
                );
              }
              
              debugPrint('   ✅ Renderizando PeopleRankingCard - index: $index');
              final ranking = _peopleState.displayedRankings[index];
              
              // Calcular posição real no ranking (considerando filtros)
              final allFiltered = _peopleState.filteredItems;
              final position = allFiltered.indexOf(ranking) + 1;

              return PeopleRankingCard(
                key: ValueKey(ranking.userId),
                ranking: ranking,
                position: position,
                badgesCount: ranking.badgesCount,
                criteriaRatings: ranking.criteriaRatings,
                totalComments: ranking.totalComments,
              );
            },
            padding: EdgeInsets.symmetric(horizontal: 16.w),
          ),
        ),
      ],
    );
  }

  Widget _buildStateFilter(List<String> states) {
    final i18n = AppLocalizations.of(context);
    final selectedState = _peopleState.filter.state;
    
    // Criar lista com "Todos" + estados
    final allLabel = i18n.translate('all').isNotEmpty ? i18n.translate('all') : 'Todos';
    final items = [allLabel, ...states];
    
    // Index selecionado (0 = Todos, 1+ = estados)
    final selectedIndex = selectedState == null 
        ? 0 
        : states.indexOf(selectedState) + 1;
    
    return NotificationHorizontalFilters(
      items: items,
      selectedIndex: selectedIndex,
      onSelected: (index) {
        if (index == 0) {
          _peopleState.setStateFilter(null);
        } else {
          _peopleState.setStateFilter(states[index - 1]);
        }
      },
      padding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildCityFilter(List<String> cities) {
    final i18n = AppLocalizations.of(context);
    final selectedCity = _peopleState.filter.city;
    
    // Criar lista com "Todas" + cidades
    final allLabel = i18n.translate('all_feminine').isNotEmpty
        ? i18n.translate('all_feminine')
        : 'Todas';
    final values = [allLabel, ...cities];
    
    // Valor selecionado (null = Todas, string = cidade específica)
    final selected = selectedCity ?? allLabel;
    
    return OutlineHorizontalFilter(
      values: values,
      selected: selected,
      onSelected: (value) {
        if (value == null || value == allLabel) {
          _peopleState.setCityFilter(null);
        } else {
          _peopleState.setCityFilter(value);
        }
      },
      padding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}

