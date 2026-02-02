import 'package:flutter/material.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/profile/presentation/controllers/profile_controller.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/features/profile/presentation/components/profile_header.dart';
import 'package:partiu/features/profile/presentation/widgets/about_me_section.dart';
import 'package:partiu/features/profile/presentation/widgets/basic_information_profile_section.dart';
import 'package:partiu/features/profile/presentation/widgets/interests_profile_section.dart';
import 'package:partiu/features/profile/presentation/widgets/languages_profile_section.dart';
import 'package:partiu/screens/chat/chat_screen_refactored.dart';

// Novo sistema de reviews
import 'package:partiu/features/reviews/data/repositories/review_repository.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';
import 'package:partiu/features/reviews/data/models/review_stats_model.dart';
import 'package:partiu/features/reviews/presentation/components/review_stats_section.dart';
import 'package:partiu/features/reviews/presentation/components/review_badges_section.dart';
import 'package:partiu/features/reviews/presentation/components/reviewed_by_section.dart';
import 'package:partiu/features/reviews/presentation/components/review_comments_section.dart';
import 'package:partiu/features/profile/presentation/widgets/profile_actions_section.dart';
import 'package:partiu/features/profile/presentation/controllers/follow_controller.dart';
import 'package:partiu/shared/stores/user_store.dart';

/// Builder de conteúdo do perfil com NOVO sistema de reviews
/// 
/// ✅ Integrado com ReviewRepository
/// ✅ Usa ReviewCardV2 e ReviewStatsSection
/// ✅ Compatível com arquitetura Clean
class ProfileContentBuilderV2 extends StatefulWidget {
  const ProfileContentBuilderV2({
    required this.controller,
    required this.displayUser,
    required this.myProfile,
    required this.i18n,
    required this.currentUserId,
    this.followController,
    super.key,
  });

  final ProfileController controller;
  final User displayUser;
  final bool myProfile;
  final AppLocalizations i18n;
  final String currentUserId;
  /// FollowController é gerenciado pelo pai (ProfileScreenOptimized) para evitar
  /// recriação quando profile.value muda no stream do Firestore.
  final FollowController? followController;

  @override
  State<ProfileContentBuilderV2> createState() => _ProfileContentBuilderV2State();
}

class _ProfileContentBuilderV2State extends State<ProfileContentBuilderV2> {
  final _reviewRepository = ReviewRepository();
  
  // Future para reviews (get único, não stream)
  late Future<_ReviewData> _reviewDataFuture;
  
  // Widget de reviews cacheado para evitar rebuilds desnecessários
  late Widget _reviewsSectionWidget;
  
  // Contador de builds para debug
  int _buildCount = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('📄 [ProfileContentBuilderV2] initState() - hashCode: ${widget.hashCode}, followController: ${widget.followController?.hashCode}');
    
    _loadReviewData();
  }

  @override
  void didUpdateWidget(covariant ProfileContentBuilderV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recarrega dados se o usuário mudou
    if (oldWidget.displayUser.userId != widget.displayUser.userId) {
      debugPrint('📄 [ProfileContentBuilderV2] didUpdateWidget - userId mudou, recarregando dados');
      _loadReviewData();
    }
  }

  @override
  void dispose() {
    // FollowController é gerenciado pelo pai, não descartamos aqui
    super.dispose();
  }

  void _loadReviewData() {
    debugPrint('🔄 _loadReviewData iniciado para user: ${widget.displayUser.userId}');
    // Usa Future único (get) em vez de Stream - muito mais eficiente
    _reviewDataFuture = _fetchReviewData(widget.displayUser.userId);
    
    // Inicializa/atualiza o widget de reviews
    _reviewsSectionWidget = _ProfileReviewsSection(
      key: ValueKey('reviews_${widget.displayUser.userId}'),
      reviewDataFuture: _reviewDataFuture,
    );
  }

  Future<_ReviewData> _fetchReviewData(String userId) async {
    debugPrint('📡 [ProfileContentBuilderV2] Buscando reviews para: ${userId.substring(0, 8)}...');
    
    try {
      // Busca reviews e calcula stats (uma única query) com timeout
      final reviews = await _reviewRepository
          .getUserReviews(userId, limit: 50)
          .timeout(const Duration(seconds: 10), onTimeout: () {
            debugPrint('⏰ [ProfileContentBuilderV2] TIMEOUT ao buscar reviews');
            return <ReviewModel>[];
          });
      final stats = ReviewStatsModel.calculate(userId, reviews);
      
      debugPrint('📊 [ProfileContentBuilderV2] Reviews carregados: ${reviews.length}, rating: ${stats.overallRating}');
      
      return _ReviewData(stats: stats, reviews: reviews);
    } catch (e, stack) {
      debugPrint('❌ [ProfileContentBuilderV2] Erro ao buscar reviews: $e');
      debugPrint('   Stack: $stack');
      // Retorna dados vazios em caso de erro
      return _ReviewData(
        stats: ReviewStatsModel.calculate(userId, const []),
        reviews: const [],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    debugPrint('📄 [ProfileContentBuilderV2] build() #$_buildCount - hashCode: ${widget.hashCode}, State.hashCode: $hashCode, followController: ${widget.followController?.hashCode}');
    return Column(
      children: [
        // HEADER com foto, nome, idade
        RepaintBoundary(
          child: ProfileHeader(
            key: ValueKey('${widget.displayUser.userId}_${widget.displayUser.photoUrl}'),
            user: widget.displayUser,
            isMyProfile: widget.myProfile,
            i18n: widget.i18n,
          ),
        ),
        
        const SizedBox(height: 24),
        
        // SECTIONS
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAboutMe(),
            if (!widget.myProfile) _buildActions(),
            _buildBasicInfo(),
            _buildInterests(),
            _buildLanguages(),
            _buildReviewsV2(), // 🆕 NOVO sistema
          ],
        ),
        
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildAboutMe() {
    final bio = widget.displayUser.userBio;
    if (bio.trim().isEmpty) return const SizedBox();
    return RepaintBoundary(
      child: AboutMeSection(
        bio: bio,
        hasActionsBelow: !widget.myProfile,
      ),
    );
  }

  Widget _buildBasicInfo() {
    return RepaintBoundary(
      child: BasicInformationProfileSection(user: widget.displayUser),
    );
  }

  Widget _buildInterests() {
    return RepaintBoundary(
      child: InterestsProfileSection(interests: widget.displayUser.interests),
    );
  }

  Widget _buildLanguages() {
    return RepaintBoundary(
      child: LanguagesProfileSection(languages: widget.displayUser.languages),
    );
  }

  /// 🆕 Nova seção de reviews usando ReviewRepository
  Widget _buildReviewsV2() {
    return _reviewsSectionWidget;
  }

  Widget _buildActions() {
    debugPrint('📄 [ProfileContentBuilderV2] _buildActions() chamado');
    // Renderização condicional via UserStore
    // Campo Firestore: message_button (bool). Default: true.
    // Campo Firestore: advancedSettings.followButton (bool). Default: true.

    return ValueListenableBuilder<bool>(
      valueListenable: UserStore.instance.getFollowButtonNotifier(
        widget.displayUser.userId,
      ),
      builder: (context, showFollowButton, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: UserStore.instance.getMessageButtonNotifier(
            widget.displayUser.userId,
          ),
          builder: (context, showMessageButton, _) {
            return RepaintBoundary(
              child: ProfileActionsSection(
                showFollowButton: showFollowButton && widget.followController != null,
                showMessageButton: showMessageButton,
                followController: widget.followController,
                onAddFriend: () {
                  debugPrint('👥 Adicionar amigo clicado');
                },
                onMessage: showMessageButton ? () {
                  // Verificar se usuário está bloqueado
                  if (BlockService().isBlockedCached(widget.currentUserId, widget.displayUser.userId)) {
                    ToastService.showWarning(
                      message: widget.i18n.translate('user_blocked_cannot_message'),
                    );
                    return;
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreenRefactored(
                        user: widget.displayUser,
                        isEvent: false,
                      ),
                    ),
                  );
                } : null,
              ),
            );
          },
        );
      },
    );
  }
}

/// Dados de reviews carregados (stats + lista)
class _ReviewData {
  final ReviewStatsModel stats;
  final List<ReviewModel> reviews;
  
  const _ReviewData({required this.stats, required this.reviews});
}

/// Widget separado para reviews usando FutureBuilder (mais eficiente que StreamBuilder)
class _ProfileReviewsSection extends StatelessWidget {
  const _ProfileReviewsSection({
    required this.reviewDataFuture,
    super.key,
  });

  final Future<_ReviewData> reviewDataFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReviewData>(
      future: reviewDataFuture,
      builder: (context, snapshot) {
        debugPrint('🔍 [ProfileReviewsSection] FutureBuilder status:');
        debugPrint('  - hasData: ${snapshot.hasData}');
        debugPrint('  - connectionState: ${snapshot.connectionState}');
        
        if (snapshot.hasData) {
          final data = snapshot.data!;
          debugPrint('  - hasReviews: ${data.stats.hasReviews}');
          debugPrint('  - totalReviews: ${data.stats.totalReviews}');
          debugPrint('  - overallRating: ${data.stats.overallRating}');
          debugPrint('  - badgesCount: ${data.stats.badgesCount}');
        } else if (snapshot.hasError) {
          debugPrint('  - error: ${snapshot.error}');
        } else {
          debugPrint('  - loading...');
        }
        
        // Loading ou erro - não mostra nada
        if (!snapshot.hasData || !snapshot.data!.stats.hasReviews) {
          if (snapshot.connectionState == ConnectionState.done) {
            debugPrint('  ❌ Não renderizando ReviewStatsSection/ReviewBadgesSection');
          }
          return const SizedBox.shrink();
        }

        final stats = snapshot.data!.stats;
        final reviews = snapshot.data!.reviews;
        debugPrint('  ✅ Renderizando ReviewStatsSection e ReviewBadgesSection');

        return RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Estatísticas agregadas
              ReviewStatsSection(stats: stats),
              
              if (stats.badgesCount.isNotEmpty)
                ReviewBadgesSection(badgesCount: stats.badgesCount),
              
              // Seção "Avaliado por" com avatares dos reviewers
              if (reviews.isNotEmpty)
                ReviewedBySection(reviews: reviews),
              
              // Comentários das reviews
              if (reviews.isNotEmpty)
                ReviewCommentsSection(reviews: reviews),
            ],
          ),
        );
      },
    );
  }
}
