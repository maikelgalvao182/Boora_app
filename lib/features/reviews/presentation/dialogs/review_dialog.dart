import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/reviews/presentation/dialogs/review_dialog_controller.dart';
import 'package:partiu/features/reviews/presentation/components/rating_criteria_step.dart';
import 'package:partiu/features/reviews/presentation/components/badge_selection_step.dart';
import 'package:partiu/features/reviews/presentation/components/comment_step.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';

/// Dialog para avaliar um participante/owner após um evento
class ReviewDialog extends StatelessWidget {
  final String eventId;
  final String revieweeId;
  final String revieweeName;
  final String? revieweePhotoUrl;
  final String reviewerRole; // 'owner' | 'participant'
  final String pendingReviewId;

  const ReviewDialog({
    required this.eventId,
    required this.revieweeId,
    required this.revieweeName,
    this.revieweePhotoUrl,
    required this.reviewerRole,
    required this.pendingReviewId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ReviewDialogController(
        eventId: eventId,
        revieweeId: revieweeId,
        reviewerRole: reviewerRole,
      ),
      child: _ReviewDialogContent(
        revieweeName: revieweeName,
        revieweePhotoUrl: revieweePhotoUrl,
        pendingReviewId: pendingReviewId,
      ),
    );
  }
}

class _ReviewDialogContent extends StatelessWidget {
  final String revieweeName;
  final String? revieweePhotoUrl;
  final String pendingReviewId;

  const _ReviewDialogContent({
    required this.revieweeName,
    this.revieweePhotoUrl,
    required this.pendingReviewId,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReviewDialogController>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(context, controller),

            // Progress bar
            _buildProgressBar(controller),

            // Content (steps)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Avatar e info do reviewee
                    _buildRevieweeInfo(),
                    const SizedBox(height: 24),

                    // Step content
                    if (controller.currentStep == 0)
                      RatingCriteriaStep(
                        ratings: controller.ratings,
                        onRatingChanged: controller.setRating,
                      )
                    else if (controller.currentStep == 1)
                      BadgeSelectionStep(
                        selectedBadges: controller.selectedBadges,
                        onBadgeToggle: controller.toggleBadge,
                      )
                    else
                      CommentStep(
                        controller: controller.commentController,
                      ),

                    // Error message
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: GlimpseColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: GlimpseColors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                controller.errorMessage!,
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: GlimpseColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Actions (botões)
            _buildActions(context, controller),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ReviewDialogController controller) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GlimpseColors.primary.withOpacity(0.05),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          // Botão voltar (apenas se não for step 0)
          if (controller.canGoBack)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: controller.previousStep,
              color: GlimpseColors.textPrimary,
            )
          else
            const SizedBox(width: 48),

          // Título
          Expanded(
            child: Text(
              controller.currentStepLabel,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: GlimpseColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Botão fechar
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            color: GlimpseColors.textPrimary,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(ReviewDialogController controller) {
    return Container(
      height: 4,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: LinearProgressIndicator(
        value: controller.progress,
        backgroundColor: Colors.grey.shade200,
        valueColor: AlwaysStoppedAnimation(GlimpseColors.primary),
      ),
    );
  }

  Widget _buildRevieweeInfo() {
    return Column(
      children: [
        // Avatar
        CircleAvatar(
          radius: 40,
          backgroundColor: GlimpseColors.primary.withOpacity(0.2),
          backgroundImage: revieweePhotoUrl != null
              ? NetworkImage(revieweePhotoUrl!)
              : null,
          child: revieweePhotoUrl == null
              ? Text(
                  revieweeName[0].toUpperCase(),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: GlimpseColors.primary,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),

        // Nome
        Text(
          revieweeName,
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: GlimpseColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, ReviewDialogController controller) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Botão principal
          SizedBox(
            width: double.infinity,
            child: GlimpseButton(
              text: _getButtonText(controller),
              onPressed: controller.isSubmitting
                  ? null
                  : () => _handleButtonPress(context, controller),
              isLoading: controller.isSubmitting,
            ),
          ),

          // Botão "Pular" apenas no step 2 (comentário)
          if (controller.currentStep == 2) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: controller.isSubmitting
                  ? null
                  : () => _handleSkipComment(context, controller),
              child: Text(
                'Pular comentário',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getButtonText(ReviewDialogController controller) {
    switch (controller.currentStep) {
      case 0:
        return 'Continuar';
      case 1:
        return 'Continuar';
      case 2:
        return 'Enviar Avaliação';
      default:
        return 'Continuar';
    }
  }

  Future<void> _handleButtonPress(
    BuildContext context,
    ReviewDialogController controller,
  ) async {
    if (controller.currentStep == 0) {
      controller.goToBadgesStep();
    } else if (controller.currentStep == 1) {
      controller.goToCommentStep();
    } else {
      // Step 2: Submit review
      final success = await controller.submitReview();
      if (success && context.mounted) {
        Navigator.of(context).pop(true);
        _showSuccessMessage(context);
      }
    }
  }

  Future<void> _handleSkipComment(
    BuildContext context,
    ReviewDialogController controller,
  ) async {
    final success = await controller.skipCommentAndSubmit();
    if (success && context.mounted) {
      Navigator.of(context).pop(true);
      _showSuccessMessage(context);
    }
  }

  void _showSuccessMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Avaliação enviada com sucesso!',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: GlimpseColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
