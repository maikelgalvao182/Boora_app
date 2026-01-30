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
  
  // Stream controllers para reviews
  Stream<ReviewStatsModel>? _statsStream;
  Stream<List<ReviewModel>>? _reviewsStream;
  
  // Widget de reviews cacheado para evitar rebuilds desnecessários
  late Widget _reviewsSectionWidget;
  
  // Contador de builds para debug
  int _buildCount = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('📄 [ProfileContentBuilderV2] initState() - hashCode: ${widget.hashCode}, followController: ${widget.followController?.hashCode}');
    
    _loadReviewStreams();
  }

  @override
  void dispose() {
    // FollowController é gerenciado pelo pai, não descartamos aqui
    super.dispose();
  }

  void _loadReviewStreams() {
    debugPrint('🔄 _loadReviewStreams iniciado para user: ${widget.displayUser.userId}');
    _statsStream = _reviewRepository.watchUserStats(widget.displayUser.userId);
    _reviewsStream = _reviewRepository.watchUserReviews(widget.displayUser.userId);
    
    // Inicializa o widget de reviews uma única vez
    _reviewsSectionWidget = _ProfileReviewsSection(
      statsStream: _statsStream,
      reviewsStream: _reviewsStream,
    );
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

    return ValueListenableBuilder<bool>(
      valueListenable: UserStore.instance.getMessageButtonNotifier(
        widget.displayUser.userId,
      ),
      builder: (context, showMessageButton, _) {
        return RepaintBoundary(
          child: ProfileActionsSection(
            showFollowButton: widget.followController != null,
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
  }
}

/// Widget separado para gerenciar estado de expansão e evitar rebuilds do pai
class _ProfileReviewsSection extends StatefulWidget {
  const _ProfileReviewsSection({
    required this.statsStream,
    required this.reviewsStream,
  });

  final Stream<ReviewStatsModel>? statsStream;
  final Stream<List<ReviewModel>>? reviewsStream;

  @override
  State<_ProfileReviewsSection> createState() => _ProfileReviewsSectionState();
}

class _ProfileReviewsSectionState extends State<_ProfileReviewsSection> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ReviewStatsModel>(
      stream: widget.statsStream,
      builder: (context, statsSnapshot) {
        debugPrint('🔍 [ProfileReviewsSection] StreamBuilder status:');
        debugPrint('  - hasData: ${statsSnapshot.hasData}');
        debugPrint('  - connectionState: ${statsSnapshot.connectionState}');
        
        if (statsSnapshot.hasData) {
          final stats = statsSnapshot.data!;
          debugPrint('  - hasReviews: ${stats.hasReviews}');
          debugPrint('  - totalReviews: ${stats.totalReviews}');
          debugPrint('  - overallRating: ${stats.overallRating}');
          debugPrint('  - badgesCount: ${stats.badgesCount}');
        } else {
          debugPrint('  - data is null');
        }
        
        if (!statsSnapshot.hasData || !statsSnapshot.data!.hasReviews) {
          debugPrint('  ❌ Não renderizando ReviewStatsSection/ReviewBadgesSection');
          return const SizedBox.shrink();
        }

        final stats = statsSnapshot.data!;
        debugPrint('  ✅ Renderizando ReviewStatsSection e ReviewBadgesSection');

        return RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Estatísticas agregadas
              ReviewStatsSection(stats: stats),
              
              if (stats.badgesCount.isNotEmpty)
                ReviewBadgesSection(badgesCount: stats.badgesCount),
              
              // Lista de reviews individuais + Seção "Avaliado por"
              StreamBuilder<List<ReviewModel>>(
                stream: widget.reviewsStream,
                builder: (context, reviewsSnapshot) {
                  if (reviewsSnapshot.hasError) {
                    debugPrint('❌ Erro ao carregar reviews: ${reviewsSnapshot.error}');
                    return const SizedBox.shrink();
                  }

                  if (!reviewsSnapshot.hasData) {
                    return const SizedBox.shrink();
                  }

                  final reviews = reviewsSnapshot.data!;

                  if (reviews.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Seção "Avaliado por" com avatares dos reviewers
                      ReviewedBySection(reviews: reviews),
                      
                      // Comentários das reviews
                      ReviewCommentsSection(reviews: reviews),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
