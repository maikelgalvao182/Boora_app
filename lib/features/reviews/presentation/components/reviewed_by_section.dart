import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

/// Modelo para representar um reviewer único
class _ReviewerInfo {
  final String userId;
  final String? displayName;
  final String? photoUrl;

  const _ReviewerInfo({
    required this.userId,
    this.displayName,
    this.photoUrl,
  });
}

/// Seção "Avaliado por..." que exibe os avatares dos usuários que enviaram avaliações
/// 
/// Mostra um grid de avatares com 6 colunas + nome do reviewer
/// 
/// ✅ Otimizado para cache:
/// - Faz preload em batch dos avatares no initState
/// - Usa StableAvatar com photoUrl direto (evita Firestore reads)
/// - Cache em disco via AvatarImageCache (90 dias)
class ReviewedBySection extends StatefulWidget {
  const ReviewedBySection({
    required this.reviews,
    super.key,
  });

  final List<ReviewModel> reviews;

  @override
  State<ReviewedBySection> createState() => _ReviewedBySectionState();
}

class _ReviewedBySectionState extends State<ReviewedBySection> {
  late final List<_ReviewerInfo> _reviewers;

  @override
  void initState() {
    super.initState();
    // Extrai reviewers únicos uma vez
    _reviewers = _extractUniqueReviewers();
  }

  /// Extrai lista de reviewers únicos a partir das reviews
  List<_ReviewerInfo> _extractUniqueReviewers() {
    final Map<String, _ReviewerInfo> uniqueReviewers = {};

    for (final review in widget.reviews) {
      // Pula se já temos esse reviewer
      if (uniqueReviewers.containsKey(review.reviewerId)) continue;

      uniqueReviewers[review.reviewerId] = _ReviewerInfo(
        userId: review.reviewerId,
        displayName: review.reviewerName,
        photoUrl: review.reviewerPhotoUrl,
      );
    }

    return uniqueReviewers.values.toList();
  }


  @override
  Widget build(BuildContext context) {
    if (_reviewers.isEmpty) {
      return const SizedBox.shrink();
    }

    final i18n = AppLocalizations.of(context);
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final topSpacing = isAndroid ? 16.0 : 0.0;

    return Container(
      padding: EdgeInsets.only(
        top: topSpacing,
        left: 20,
        right: 20,
      ),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.translate('reviewed_by_section_title'),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: GlimpseColors.primaryColorLight,
            ),
          ),
          const SizedBox(height: 12),
          _buildReviewersGrid(),
        ],
      ),
    );
  }

  Widget _buildReviewersGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0, // Quadrado perfeito para avatares redondos
      ),
      itemCount: _reviewers.length,
      itemBuilder: (context, index) {
        final reviewer = _reviewers[index];
        return _ReviewerCard(reviewer: reviewer);
      },
    );
  }
}

/// Card individual de reviewer com avatar e nome
class _ReviewerCard extends StatelessWidget {
  const _ReviewerCard({
    required this.reviewer,
  });

  final _ReviewerInfo reviewer;

  @override
  Widget build(BuildContext context) {
    return StableAvatar(
      userId: reviewer.userId,
      size: 26,
      photoUrl: reviewer.photoUrl,
      enableNavigation: true,
    );
  }
}
