import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/features/notifications/templates/notification_templates.dart';
import 'package:partiu/features/notifications/triggers/base_activity_trigger.dart';

/// TRIGGER 4: Dono recusou entrada na atividade privada
/// 
/// Notificação enviada para: O membro que foi rejeitado
/// Remetente: O dono da atividade (createdBy)
/// Mensagem: "{fullName} recusou seu pedido para entrar em {emoji} {activityText}."
class ActivityJoinRejectedTrigger extends BaseActivityTrigger {
  const ActivityJoinRejectedTrigger({
    required super.notificationRepository,
    required super.firestore,
  });

  @override
  Future<void> execute(
    ActivityModel activity,
    Map<String, dynamic> context,
  ) async {
    print('⛔ [ActivityJoinRejectedTrigger.execute] INICIANDO');
    print('⛔ [ActivityJoinRejectedTrigger.execute] Activity: ${activity.id} - ${activity.name} ${activity.emoji}');
    print('⛔ [ActivityJoinRejectedTrigger.execute] Context: $context');
    
    try {
      final rejectedUserId = context['rejectedUserId'] as String?;
      print('⛔ [ActivityJoinRejectedTrigger.execute] RejectedUserId: $rejectedUserId');

      if (rejectedUserId == null) {
        print('❌ [ActivityJoinRejectedTrigger.execute] rejectedUserId não fornecido');
        return;
      }

      // Buscar dados do owner (quem rejeitou)
      final ownerInfo = await getUserInfo(activity.createdBy);
      print('⛔ [ActivityJoinRejectedTrigger.execute] Owner: ${ownerInfo['fullName']}');

      // Gera mensagem usando template
      final template = NotificationTemplates.activityJoinRejected(
        activityName: activity.name,
        emoji: activity.emoji,
      );

      print('⛔ [ActivityJoinRejectedTrigger.execute] Template gerado: ${template.title}');

      // Notifica o usuário rejeitado
      print('⛔ [ActivityJoinRejectedTrigger.execute] Criando notificação para: $rejectedUserId');
      await createNotification(
        receiverId: rejectedUserId,
        type: ActivityNotificationTypes.activityJoinRejected,
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

      print('✅ [ActivityJoinRejectedTrigger.execute] CONCLUÍDO - Notificação enviada para: $rejectedUserId');
    } catch (e, stackTrace) {
      print('❌ [ActivityJoinRejectedTrigger.execute] ERRO: $e');
      print('❌ [ActivityJoinRejectedTrigger.execute] StackTrace: $stackTrace');
    }
  }
}
