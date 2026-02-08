import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/pull_to_refresh.dart';
import 'package:partiu/features/home/presentation/screens/advanced_filters_screen.dart';
import 'package:partiu/features/home/data/services/people_map_discovery_service.dart';
import 'package:partiu/features/home/presentation/widgets/user_card.dart';
import 'package:partiu/features/home/presentation/widgets/user_card_shimmer.dart';

/// Tela para encontrar pessoas na região
/// 
/// ✅ Acesso exclusivo VIP (bloqueio feito no PeopleButton)
/// ✅ Lazy loading de 30 em 30 para listas longas
class FindPeopleScreen extends StatefulWidget {
  const FindPeopleScreen({super.key});

  @override
  State<FindPeopleScreen> createState() => _FindPeopleScreenState();
}

class _FindPeopleScreenState extends State<FindPeopleScreen> {
  late final ScrollController _scrollController;
  final PeopleMapDiscoveryService _peopleDiscoveryService = PeopleMapDiscoveryService();
  
  /// 📄 Lazy loading: quantidade de itens exibidos atualmente
  static const int _pageSize = 30;
  int _displayedCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    debugPrint('🎯 [FindPeopleScreen] Inicializando (acesso VIP garantido pelo PeopleButton)');

    // Se já existir um bounds conhecido do mapa, força refresh para popular a lista
    debugPrint('🔄 [FindPeopleScreen] Verificando bounds atual...');
    debugPrint('   📐 currentBounds: ${_peopleDiscoveryService.currentBounds.value}');
    debugPrint('   📋 nearbyPeople.length: ${_peopleDiscoveryService.nearbyPeople.value.length}');
    
    _peopleDiscoveryService.refreshCurrentBoundsIfStale(
      ttl: const Duration(minutes: 10),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // � Lazy loading: carregar mais itens quando chegar perto do final
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 300) {
      _loadMoreItems();
    }
  }
  
  /// 📄 Carrega mais itens na lista (lazy loading)
  void _loadMoreItems() {
    final totalAvailable = _peopleDiscoveryService.nearbyPeople.value.length;
    if (_displayedCount >= totalAvailable) return; // Já carregou tudo
    
    setState(() {
      _displayedCount = (_displayedCount + _pageSize).clamp(0, totalAvailable);
      debugPrint('📄 [LazyLoad] Carregando mais: $_displayedCount / $totalAvailable');
    });
  }
  
  /// 📄 Reseta a contagem quando a lista muda (novo bounds/filtros)
  void _resetDisplayCount() {
    _displayedCount = _pageSize;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(context, i18n),
      body: _buildBody(i18n),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, AppLocalizations i18n) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      title: ValueListenableBuilder<int>(
        valueListenable: _peopleDiscoveryService.nearbyPeopleCount,
        builder: (context, count, _) {
          final titleTemplate = count > 0
              ? (count == 1
                  ? i18n.translate('people_in_region_count_singular')
                  : i18n.translate('people_in_region_count_plural'))
              : i18n.translate('people_in_region');
          final title = titleTemplate.replaceAll('{count}', count.toString());

          return Text(
            title,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: GlimpseColors.primaryColorLight,
            ),
          );
        },
      ),
          leading: GlimpseBackButton.iconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => Navigator.of(context).pop(),
            color: GlimpseColors.primaryColorLight,
          ),
          leadingWidth: 56,
          actions: [
            // Botão de filtros
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: SizedBox(
                width: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    IconsaxPlusLinear.setting_4,
                    size: 24,
                    color: GlimpseColors.textSubTitle,
                  ),
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    final result = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.85,
                        ),
                        child: const AdvancedFiltersScreen(),
                      ),
                    );
                    
                    // Se filtros foram aplicados, o LocationQueryService já emitiu
                    // novos dados no stream e o controller já foi atualizado
                    if (result == true) {
                      debugPrint('✅ Filtros aplicados, aguardando atualização automática do stream');
                      // A UI prioriza o PeopleMapDiscoveryService; então precisamos
                      // reconsultar o bounds atual para refletir os filtros.
                      _peopleDiscoveryService.refreshCurrentBounds();
                    }
                  },
                ),
              ),
            ),
          ],
        );
  }

  Widget _buildBody(AppLocalizations i18n) {
    return ValueListenableBuilder<bool>(
      valueListenable: _peopleDiscoveryService.isViewportActive,
      builder: (context, viewportActive, _) {
        if (!viewportActive) {
          return Center(
            child: GlimpseEmptyState.standard(
              text: i18n.translate('zoom_in_to_see_people'),
            ),
          );
        }

        return ValueListenableBuilder<List<User>>(
          valueListenable: _peopleDiscoveryService.nearbyPeople,
          builder: (context, usersList, __) {
            return ValueListenableBuilder<bool>(
              valueListenable: _peopleDiscoveryService.isLoading,
              builder: (context, isLoading, ___) {
                if (isLoading && usersList.isEmpty) {
                  return ListView.separated(
                    padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                    itemCount: 5,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => const UserCardShimmer(),
                  );
                }

                return ValueListenableBuilder<Object?>(
                  valueListenable: _peopleDiscoveryService.lastError,
                  builder: (context, error, ____) {
                    if (error != null && usersList.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              i18n.translate('error_try_again'),
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 16,
                                color: GlimpseColors.textSubTitle,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () => _peopleDiscoveryService.refreshCurrentBounds(),
                              child: Text(
                                i18n.translate('try_again'),
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: GlimpseColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (usersList.isEmpty) {
                      return Center(
                        child: GlimpseEmptyState.standard(
                          text: i18n.translate('no_people_found_nearby'),
                        ),
                      );
                    }
                    
                    // 📄 Lazy loading: calcular quantos itens mostrar
                    final totalUsers = usersList.length;
                    final displayCount = _displayedCount.clamp(0, totalUsers);
                    final hasMoreToLoad = _displayedCount < totalUsers;

                    return PlatformPullToRefresh(
                      onRefresh: () async {
                        _resetDisplayCount();
                        // Limpa cache para garantir dados frescos do servidor
                        _peopleDiscoveryService.clearCache();
                        await _peopleDiscoveryService.refreshCurrentBounds();
                      },
                      controller: _scrollController,
                      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                      // +1 para o loading indicator se houver mais
                      itemCount: hasMoreToLoad ? displayCount + 1 : displayCount,
                      itemBuilder: (context, index) {
                        // Loading indicator no final
                        if (hasMoreToLoad && index == displayCount) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }

                        final user = usersList[index];
                        return UserCard(
                          key: ValueKey(user.userId),
                          userId: user.userId,
                          user: user,
                          overallRating: user.overallRating,
                          index: index,
                          onTap: () {
                            // TODO: Navegar para perfil do usuário
                          },
                        );
                      },
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
}
