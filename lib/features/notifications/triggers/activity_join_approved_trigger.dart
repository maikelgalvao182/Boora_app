import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/features/notifications/templates/notification_templates.dart';
import 'package:partiu/features/notifications/triggers/base_activity_trigger.dart';

/// TRIGGER 3: Dono aprovou entrada na atividade privada
/// 
/// Notificação enviada para: O membro que foi aprovado
/// Remetente: O dono da atividade (createdBy)
/// Mensagem: "Você foi aprovado para participar de {emoji} {activityText}!"
class ActivityJoinApprovedTrigger extends BaseActivityTrigger {
  const ActivityJoinApprovedTrigger({
    required super.notificationRepository,
    required super.firestore,
  });

  @override
  Future<void> execute(
    ActivityModel activity,
    Map<String, dynamic> context,
  ) async {
    print('✅ [ActivityJoinApprovedTrigger.execute] INICIANDO');
    print('✅ [ActivityJoinApprovedTrigger.execute] Activity: ${activity.id} - ${activity.name} ${activity.emoji}');
    print('✅ [ActivityJoinApprovedTrigger.execute] Context: $context');
    
    try {
      final approvedUserId = context['approvedUserId'] as String?;
      print('✅ [ActivityJoinApprovedTrigger.execute] ApprovedUserId: $approvedUserId');

      if (approvedUserId == null) {
        print('❌ [ActivityJoinApprovedTrigger.execute] approvedUserId não fornecido');
        return;
      }

      // Buscar dados do owner (quem aprovou)
      final ownerInfo = await getUserInfo(activity.createdBy);
      print('✅ [ActivityJoinApprovedTrigger.execute] Owner: ${ownerInfo['fullName']}');

      // Gera mensagem usando template
      final template = NotificationTemplates.activityJoinApproved(
        activityName: activity.name,
        emoji: activity.emoji,
      );

      print('✅ [ActivityJoinApprovedTrigger.execute] Template gerado: ${template.title}');

      // Notifica o usuário aprovado
      print('✅ [ActivityJoinApprovedTrigger.execute] Criando notificação para: $approvedUserId');
      await createNotification(
        receiverId: approvedUserId,
        type: ActivityNotificationTypes.activityJoinApproved,
        params: {
          'title': template.title,
          'body': template.body,
          'preview': template.preview,
          ...template.extra,
        },
        senderId: activity.createdBy,
        senderName: ownerInfo['fullName'],
        senderPhotoUrl: ownerInfo['photoUrl'],
        relatedId: activity.id,
      );

      print('✅ [ActivityJoinApprovedTrigger.execute] CONCLUÍDO - Notificação enviada para: $approvedUserId');
    } catch (e, stackTrace) {
      print('❌ [ActivityJoinApprovedTrigger.execute] ERRO: $e');
      print('❌ [ActivityJoinApprovedTrigger.execute] StackTrace: $stackTrace');
    }
  }
}
