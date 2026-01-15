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
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/screens/chat/chat_screen_refactored.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Novo sistema de reviews
import 'package:partiu/features/reviews/data/repositories/review_repository.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';
import 'package:partiu/features/reviews/data/models/review_stats_model.dart';
import 'package:partiu/features/reviews/presentation/components/review_stats_section.dart';
import 'package:partiu/features/reviews/presentation/components/review_badges_section.dart';
import 'package:partiu/features/reviews/presentation/components/review_comments_section.dart';
import 'package:partiu/features/profile/presentation/widgets/profile_actions_section.dart';

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
    super.key,
  });

  final ProfileController controller;
  final User displayUser;
  final bool myProfile;
  final AppLocalizations i18n;
  final String currentUserId;

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

  @override
  void initState() {
    super.initState();
    _loadReviewStreams();
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
    return ValueListenableBuilder<String?>(
      valueListenable: UserStore.instance.getBioNotifier(widget.displayUser.userId),
      builder: (context, bio, _) {
        if (bio == null || bio.trim().isEmpty) return const SizedBox();
        return RepaintBoundary(
          child: AboutMeSection(
            userId: widget.displayUser.userId,
            hasActionsBelow: !widget.myProfile,
          ),
        );
      },
    );
  }

  Widget _buildBasicInfo() {
    return RepaintBoundary(
      child: BasicInformationProfileSection(userId: widget.displayUser.userId),
    );
  }

  Widget _buildInterests() {
    return ValueListenableBuilder<List<String>?>(
      valueListenable: UserStore.instance.getInterestsNotifier(widget.displayUser.userId),
      builder: (context, interests, _) {
        if (interests == null || interests.isEmpty) return const SizedBox();
        return RepaintBoundary(
          child: InterestsProfileSection(userId: widget.displayUser.userId),
        );
      },
    );
  }

  Widget _buildLanguages() {
    return ValueListenableBuilder<String?>(
      valueListenable: UserStore.instance.getLanguagesNotifier(widget.displayUser.userId),
      builder: (context, languages, _) {
        if (languages == null || languages.trim().isEmpty) return const SizedBox();
        return RepaintBoundary(
          child: LanguagesProfileSection(userId: widget.displayUser.userId),
        );
      },
    );
  }

  /// 🆕 Nova seção de reviews usando ReviewRepository
  Widget _buildReviewsV2() {
    return _reviewsSectionWidget;
  }

  Widget _buildActions() {
    // Renderização condicional via stream do documento do usuário
    // Campo Firestore: message_button (bool). Default: true.
    final userDocStream = FirebaseFirestore.instance
        .collection('Users')
        .doc(widget.displayUser.userId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snapshot) {
        bool showMessageButton = true;

        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          final raw = data?['message_button'];
          if (raw is bool) {
            showMessageButton = raw;
          } else if (raw is String) {
            showMessageButton = raw.toLowerCase() == 'true';
          }
        }

        if (!showMessageButton) {
          return const SizedBox.shrink();
        }

        return RepaintBoundary(
          child: ProfileActionsSection(
            onAddFriend: () {
              debugPrint('👥 Adicionar amigo clicado');
            },
            onMessage: () {
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
            },
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
              
              // Lista de reviews individuais
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

                  return ReviewCommentsSection(reviews: reviews);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
