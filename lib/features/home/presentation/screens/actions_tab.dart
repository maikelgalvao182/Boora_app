import 'package:flutter/material.dart';
import 'package:partiu/app/services/localization_service.dart';
import 'package:partiu/features/home/data/models/pending_application_model.dart';
import 'package:partiu/features/home/data/repositories/pending_applications_repository.dart';
import 'package:partiu/features/home/presentation/widgets/approve_card.dart';
import 'package:partiu/features/reviews/data/models/pending_review_model.dart';
import 'package:partiu/features/reviews/data/repositories/review_repository.dart';
import 'package:partiu/features/reviews/presentation/widgets/review_card.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/glimpse_tab_app_bar.dart';
import 'package:partiu/shared/widgets/action_card_shimmer.dart';

/// Tela de ações (Tab 1)
/// 
/// Exibe:
/// - Aplicações pendentes de aprovação
/// - Reviews pendentes de avaliação
class ActionsTab extends StatefulWidget {
  const ActionsTab({super.key});

  @override
  State<ActionsTab> createState() => _ActionsTabState();
}

class _ActionsTabState extends State<ActionsTab> {
  final PendingApplicationsRepository _applicationsRepo = PendingApplicationsRepository();
  final ReviewRepository _reviewsRepo = ReviewRepository();

  @override
  void initState() {
    super.initState();
    debugPrint('🎬 ActionsTab: initState');
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🔄 ActionsTab: build');
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            GlimpseTabAppBar(
              title: LocalizationService.of(context).translate('actions') ?? 'Ações',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<PendingApplicationModel>>(
                stream: _applicationsRepo.getPendingApplicationsStream(),
                builder: (context, applicationsSnapshot) {
                  return StreamBuilder<List<PendingReviewModel>>(
                    stream: _reviewsRepo.getPendingReviewsStream(),
                    builder: (context, reviewsSnapshot) {
                      debugPrint('📡 ActionsTab StreamBuilder:');
                      debugPrint('   - Applications: ${applicationsSnapshot.hasData ? applicationsSnapshot.data!.length : 0}');
                      debugPrint('   - Reviews: ${reviewsSnapshot.hasData ? reviewsSnapshot.data!.length : 0}');
                      
                      // Loading inicial
                      final isLoading = 
                          (applicationsSnapshot.connectionState == ConnectionState.waiting && !applicationsSnapshot.hasData) ||
                          (reviewsSnapshot.connectionState == ConnectionState.waiting && !reviewsSnapshot.hasData);
                      
                      if (isLoading) {
                        debugPrint('   ⏳ Aguardando dados iniciais...');
                        return ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: 3,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, __) => const ActionCardShimmer(),
                        );
                      }

                      // Error
                      if (applicationsSnapshot.hasError || reviewsSnapshot.hasError) {
                        return Center(
                          child: GlimpseEmptyState.standard(
                            text: 'Erro ao carregar ações',
                          ),
                        );
                      }

                      final applications = applicationsSnapshot.data ?? [];
                      final reviews = reviewsSnapshot.data ?? [];
                      final totalItems = applications.length + reviews.length;

                      // Empty
                      if (totalItems == 0) {
                        debugPrint('   📭 Nenhuma ação pendente');
                        return Center(
                          child: GlimpseEmptyState.standard(
                            text: 'Nenhuma ação pendente',
                          ),
                        );
                      }

                      // List combinada
                      debugPrint('   📋 Renderizando ${applications.length} applications + ${reviews.length} reviews');
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: totalItems,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          // Primeiro mostra reviews, depois applications
                          if (index < reviews.length) {
                            final review = reviews[index];
                            debugPrint('   🎴 Criando ReviewCard $index: ${review.pendingReviewId}');
                            return ReviewCard(
                              key: ValueKey(review.pendingReviewId),
                              pendingReview: review,
                            );
                          } else {
                            final appIndex = index - reviews.length;
                            final application = applications[appIndex];
                            debugPrint('   🎴 Criando ApproveCard $index: ${application.applicationId}');
                            return ApproveCard(
                              key: ValueKey(application.applicationId),
                              application: application,
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
