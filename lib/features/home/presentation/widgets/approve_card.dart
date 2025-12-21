import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/data/models/pending_application_model.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/shared/widgets/action_card.dart';

/// Card para aprovação de aplicações pendentes
/// 
/// Wrapper específico do domínio que usa o ActionCard genérico
class ApproveCard extends StatelessWidget {
  const ApproveCard({
    required this.application,
    super.key,
  });

  final PendingApplicationModel application;

  @override
  Widget build(BuildContext context) {
    final repo = EventApplicationRepository();

    debugPrint('🔍 ApproveCard - userId: ${application.userId}');
    debugPrint('🔍 ApproveCard - userPhotoUrl: ${application.userPhotoUrl}');
    debugPrint('🔍 ApproveCard - userName: ${application.userFullName}');

    return ActionCard(
      userId: application.userId,
      userPhotoUrl: application.userPhotoUrl,
      textSpans: [
        TextSpan(
          text: application.userFullName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const TextSpan(text: ' quer '),
        TextSpan(
          text: '${application.eventEmoji} ${application.activityText}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
      timeAgo: application.timeAgo,
      primaryButtonText: 'Aceitar',
      primaryButtonColor: GlimpseColors.approveButtonColor,
      onPrimaryAction: () async {
        await repo.approveApplication(application.applicationId);
        debugPrint('✅ Aplicação aprovada: ${application.applicationId}');
        
        if (context.mounted) {
          final i18n = AppLocalizations.of(context);
          ToastService.showSuccess(
            message: i18n.translate('application_approved_successfully'),
          );
        }
      },
      secondaryButtonText: 'Recusar',
      secondaryButtonColor: GlimpseColors.rejectButtonColor,
      onSecondaryAction: () async {
        await repo.rejectApplication(application.applicationId);
        debugPrint('❌ Aplicação rejeitada: ${application.applicationId}');
      },
    );
  }
}
