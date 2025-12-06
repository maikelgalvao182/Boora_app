import 'package:flutter/material.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/profile/presentation/controllers/profile_controller.dart';
import 'package:partiu/features/profile/presentation/components/profile_header.dart';
import 'package:partiu/features/profile/presentation/widgets/about_me_section.dart';
import 'package:partiu/features/profile/presentation/widgets/basic_information_profile_section.dart';
import 'package:partiu/features/profile/presentation/widgets/interests_profile_section.dart';
import 'package:partiu/features/profile/presentation/widgets/languages_profile_section.dart';
import 'package:partiu/features/profile/presentation/widgets/gallery_profile_section.dart';
import 'package:partiu/shared/stores/user_store.dart';

// Novo sistema de reviews
import 'package:partiu/features/reviews/data/repositories/review_repository.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';
import 'package:partiu/features/reviews/data/models/review_stats_model.dart';
import 'package:partiu/features/reviews/presentation/components/review_card_v2.dart';
import 'package:partiu/features/reviews/presentation/components/review_stats_section.dart';

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

  @override
  void initState() {
    super.initState();
    _loadReviewStreams();
  }

  void _loadReviewStreams() {
    _statsStream = _reviewRepository.watchUserStats(widget.displayUser.userId);
    _reviewsStream = _reviewRepository.watchUserReviews(widget.displayUser.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // HEADER com foto, nome, idade
        RepaintBoundary(
          child: ProfileHeader(
            key: ValueKey('${widget.displayUser.userId}_${widget.displayUser.userProfilePhoto}'),
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
            _buildBasicInfo(),
            _buildInterests(),
            _buildLanguages(),
            _buildGallery(),
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
          child: AboutMeSection(userId: widget.displayUser.userId),
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

  Widget _buildGallery() {
    // Galeria não precisa de ValueListenableBuilder pois usa dados diretos do User
    if (widget.displayUser.userGallery == null || widget.displayUser.userGallery!.isEmpty) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: GalleryProfileSection(galleryMap: widget.displayUser.userGallery),
    );
  }

  /// 🆕 Nova seção de reviews usando ReviewRepository
  Widget _buildReviewsV2() {
    return StreamBuilder<ReviewStatsModel>(
      stream: _statsStream,
      builder: (context, statsSnapshot) {
        if (!statsSnapshot.hasData || !statsSnapshot.data!.hasReviews) {
          return const SizedBox.shrink();
        }

        final stats = statsSnapshot.data!;

        return RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Estatísticas agregadas
              ReviewStatsSection(stats: stats),
              
              const SizedBox(height: 8),
              
              // Lista de reviews individuais
              StreamBuilder<List<ReviewModel>>(
                stream: _reviewsStream,
                builder: (context, reviewsSnapshot) {
                  if (!reviewsSnapshot.hasData || reviewsSnapshot.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final reviews = reviewsSnapshot.data!;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Mostrar até 5 reviews recentes
                        ...reviews.take(5).map((review) {
                          return ReviewCardV2(review: review);
                        }).toList(),
                        
                        // Botão "Ver todas" se tiver mais de 5
                        if (reviews.length > 5)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Center(
                              child: TextButton(
                                onPressed: () {
                                  // TODO: Navegar para tela de todas as reviews
                                  debugPrint('🔍 Ver todas as ${reviews.length} reviews');
                                },
                                child: Text(
                                  'Ver todas as ${reviews.length} avaliações',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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
