import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/app/services/localization_service.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/home/presentation/viewmodels/ranking_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/place_card/place_card.dart';
import 'package:partiu/features/home/presentation/widgets/place_card/place_card_controller.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/glimpse_tab_app_bar.dart';

/// Tela de ranking (Tab 2)
/// 
/// Exibe ranking de locais por eventos hospedados
class RankingTab extends StatefulWidget {
  const RankingTab({super.key});

  @override
  State<RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<RankingTab> {
  late final RankingViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = RankingViewModel();
    _viewModel.addListener(_onViewModelChanged);
    
    // Inicializar rankings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewModel.initialize();
    });
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            GlimpseTabAppBar(
              title: LocalizationService.of(context).translate('ranking') ?? 'Ranking',
            ),
            
            const SizedBox(height: 16),
            
            // Conteúdo
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Loading state
    if (_viewModel.isLoading) {
      return const Center(
        child: CupertinoActivityIndicator(radius: 16),
      );
    }

    // Error state
    if (_viewModel.error != null) {
      return Center(
        child: GlimpseEmptyState.standard(
          text: _viewModel.error!,
        ),
      );
    }

    return _buildLocationRankingList();
  }

  Widget _buildLocationRankingList() {
    final rankings = _viewModel.locationRankings;
    
    if (rankings.isEmpty) {
      return Center(
        child: GlimpseEmptyState.standard(
          text: 'Nenhum local no ranking ainda',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _viewModel.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: rankings.length,
        itemBuilder: (context, index) {
          final ranking = rankings[index];
          final position = index + 1;

          // Criar controller com dados do ranking
          final controller = PlaceCardController(
            eventId: 'ranking_${ranking.placeId}',
            preloadedData: {
              'locationName': ranking.locationName,
              'formattedAddress': ranking.formattedAddress,
              'placeId': ranking.placeId,
              'photoReferences': ranking.photoReferences,
              'visitors': ranking.visitors,
              'totalVisitorsCount': ranking.totalVisitors,
            },
          );

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: GlimpseColors.borderColorLight,
                width: 1,
              ),
            ),
            child: PlaceCard(
              controller: controller,
              customTagWidget: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: GlimpseColors.primaryLight,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${ranking.totalEventsHosted} eventos',
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: GlimpseColors.primaryDarker,
                  ),
                ),
              ),
              onTap: () {
                debugPrint('🏆 Local clicado: ${ranking.placeId}');
              },
            ),
          );
        },
      ),
    );
  }
}
