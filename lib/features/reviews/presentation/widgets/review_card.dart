import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/reviews/data/models/pending_review_model.dart';
import 'package:partiu/features/reviews/data/repositories/review_repository.dart';
import 'package:partiu/features/reviews/presentation/dialogs/review_dialog.dart';
import 'package:partiu/shared/widgets/action_card.dart';

/// Card para avaliações pendentes
/// 
/// Wrapper específico do domínio que usa o ActionCard genérico
class ReviewCard extends StatelessWidget {
  const ReviewCard({
    required this.pendingReview,
    super.key,
  });

  final PendingReviewModel pendingReview;

  @override
  Widget build(BuildContext context) {
    final repo = ReviewRepository();
    final i18n = AppLocalizations.of(context);

    debugPrint('🎴 ReviewCard build');
    debugPrint('   pendingReviewId: ${pendingReview.pendingReviewId}');
    debugPrint('   reviewerId: "${pendingReview.reviewerId}"');
    debugPrint('   revieweeId: "${pendingReview.revieweeId}"');
    debugPrint('   reviewerRole: ${pendingReview.reviewerRole}');
    debugPrint('   revieweeName: ${pendingReview.revieweeName}');
    debugPrint('   revieweePhotoUrl: ${pendingReview.revieweePhotoUrl}');
    
    // VALIDAÇÃO CRÍTICA: Detectar autoavaliação
    if (pendingReview.reviewerId == pendingReview.revieweeId) {
      debugPrint('❌ [ReviewCard] ERRO: Autoavaliação detectada!');
      final translated = i18n.translate('review_card_invalid_self_review_error');
      final errorMessage =
          translated.isNotEmpty ? translated : i18n.translate('something_went_wrong');

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GlimpseColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: GlimpseColors.error,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: GlimpseColors.error,
              size: 24,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                errorMessage,
                style: TextStyle(
                  color: GlimpseColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: GlimpseColors.error),
              onPressed: () async {
                await repo.dismissPendingReview(pendingReview.pendingReviewId);
              },
            ),
          ],
        ),
      );
    }

    // Determinar dados do usuário a ser mostrado no card
    String displayUserId;
    String? displayPhotoUrl;
    String displayName;
    List<TextSpan> textSpans;

    if (pendingReview.isOwnerReview) {
      // Owner avaliando participantes
      // Mostrar dados do primeiro participante ou mensagem genérica
      final participantCount = pendingReview.participantIds?.length ?? 0;
      
      if (participantCount == 0) {
        // Nenhum participante (não deveria acontecer, mas defesa)
        displayUserId = pendingReview.reviewerId; // Fallback
        displayPhotoUrl = null;
        displayName = i18n.translate('participants_label');

        final prefix = i18n.translate('review_card_rate_participants_prefix');

        textSpans = [
          TextSpan(text: prefix),
          const TextSpan(text: ' '),
          TextSpan(
            text: '${pendingReview.eventEmoji} ${pendingReview.eventTitle}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ];
      } else {
        // Pegar primeiro participante
        final firstParticipantId = pendingReview.participantIds!.first;
        final firstParticipant = pendingReview.participantProfiles?[firstParticipantId];
        
        displayUserId = firstParticipantId;
        displayPhotoUrl = firstParticipant?.photoUrl;
        displayName = firstParticipant?.name ?? i18n.translate('participant_label');

        final needsInEvent = i18n.translate('review_card_needs_review_in_event');

        final toBeReviewedInEvent = i18n.translate('review_card_to_be_reviewed_in_event');
        
        if (participantCount == 1) {
          textSpans = [
            TextSpan(
              text: displayName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: ' '),
            TextSpan(text: needsInEvent),
            const TextSpan(text: ' '),
            TextSpan(
              text: '${pendingReview.eventEmoji} ${pendingReview.eventTitle}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ];
        } else {
          final remaining = participantCount - 1;
          final andMoreTemplate = i18n.translate('review_card_and_more_count');
          final andMore = andMoreTemplate.replaceAll('{count}', remaining.toString());

          final personNeeds = i18n.translate('review_card_person_needs');

          final peopleNeed = i18n.translate('review_card_people_need');

          textSpans = [
            TextSpan(
              text: displayName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: ' '),
            TextSpan(text: andMore),
            const TextSpan(text: ' '),
            TextSpan(
              text: remaining == 1 ? personNeeds : peopleNeed,
            ),
            const TextSpan(text: ' '),
            TextSpan(text: toBeReviewedInEvent),
            const TextSpan(text: ' '),
            TextSpan(
              text: '${pendingReview.eventEmoji} ${pendingReview.eventTitle}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ];
        }
      }
    } else {
      // Participant avaliando owner
      displayUserId = pendingReview.revieweeId;
      displayPhotoUrl = pendingReview.revieweePhotoUrl;
        displayName = pendingReview.revieweeName.isNotEmpty
          ? pendingReview.revieweeName
          : i18n.translate('organizer_label');

      final needsInEvent = i18n.translate('review_card_needs_review_in_event');

      textSpans = [
        TextSpan(
          text: displayName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const TextSpan(text: ' '),
        TextSpan(text: needsInEvent),
        const TextSpan(text: ' '),
        TextSpan(
          text: '${pendingReview.eventEmoji} ${pendingReview.eventTitle}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ];
    }

    return ActionCard(
      userId: displayUserId,
      userPhotoUrl: displayPhotoUrl,
      textSpans: textSpans,
      timeAgo: _getTimeAgo(i18n, pendingReview.createdAt),
      primaryButtonText: i18n.translate('review_action_rate'),
      primaryButtonColor: GlimpseColors.approveButtonColor,
      onPrimaryAction: () async {
        debugPrint('🎯 [ReviewCard] Abrindo ReviewDialog...');
        
        final result = await ReviewDialog.show(
          context,
          pendingReview: pendingReview,
        );

        debugPrint('🔍 [ReviewCard] Dialog retornou: $result');

        // Se não completou, lança erro para evitar remoção
        if (result != true) {
          throw Exception(i18n.translate('review_canceled'));
        }
        
        debugPrint('✅ Review completado: ${pendingReview.pendingReviewId}');
      },
      secondaryButtonText: i18n.translate('review_action_dismiss'),
      secondaryButtonColor: GlimpseColors.rejectButtonColor,
      onSecondaryAction: () async {
        await repo.dismissPendingReview(pendingReview.pendingReviewId);
        debugPrint('🗑️ Review dispensado: ${pendingReview.pendingReviewId}');
      },
    );
  }

  String _timeAgoFromTemplate(AppLocalizations i18n, String key, int count) {
    final template = i18n.translate(key);
    if (template.isEmpty) return '';
    return template.replaceAll('{count}', count.toString());
  }

  String _getTimeAgo(AppLocalizations i18n, DateTime createdAt) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inMinutes < 1) {
      return i18n.translate('just_now');
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      final key = minutes == 1 ? 'time_ago_minutes_singular' : 'time_ago_minutes_plural';
      final fromTemplate = _timeAgoFromTemplate(i18n, key, minutes);
      return fromTemplate;
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      final key = hours == 1 ? 'time_ago_hours_singular' : 'time_ago_hours_plural';
      final fromTemplate = _timeAgoFromTemplate(i18n, key, hours);
      return fromTemplate;
    } else {
      final days = difference.inDays;
      final key = days == 1 ? 'time_ago_days_singular' : 'time_ago_days_plural';
      final fromTemplate = _timeAgoFromTemplate(i18n, key, days);
      return fromTemplate;
    }
  }
}
