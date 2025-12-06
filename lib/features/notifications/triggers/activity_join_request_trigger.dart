import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/features/notifications/templates/notification_templates.dart';
import 'package:partiu/features/notifications/triggers/base_activity_trigger.dart';

/// TRIGGER 2: Solicitação de entrada em atividade privada
/// 
/// Notificação (para o dono): "{fullName} pediu para entrar na sua atividade {emoji} {activityText}."
/// 
/// Exemplo: "Júlia pediu para entrar na sua atividade 🍕 Pizza e conversa."
class ActivityJoinRequestTrigger extends BaseActivityTrigger {
  const ActivityJoinRequestTrigger({
    required super.notificationRepository,
    required super.firestore,
  });

  @override
  Future<void> execute(
    ActivityModel activity,
    Map<String, dynamic> context,
  ) async {
    print('🔐 [ActivityJoinRequestTrigger.execute] INICIANDO');
    print('🔐 [ActivityJoinRequestTrigger.execute] Activity: ${activity.id} - ${activity.name} ${activity.emoji}');
    print('🔐 [ActivityJoinRequestTrigger.execute] Context: $context');
    
    try {
      final requesterId = context['requesterId'] as String?;
      final requesterName = context['requesterName'] as String?;

      print('🔐 [ActivityJoinRequestTrigger.execute] RequesterId: $requesterId');
      print('🔐 [ActivityJoinRequestTrigger.execute] RequesterName: $requesterName');
      
      if (requesterId == null || requesterName == null) {
        print('❌ [ActivityJoinRequestTrigger.execute] Dados incompletos no context');
        return;
      }

      // Busca owner da atividade
      print('🔐 [ActivityJoinRequestTrigger.execute] Buscando owner da atividade...');
      final ownerId = await _getActivityOwner(activity.id);
      print('🔐 [ActivityJoinRequestTrigger.execute] OwnerId: $ownerId');
      
      if (ownerId == null) {
        print('❌ [ActivityJoinRequestTrigger.execute] Owner não encontrado');
        return;
      }

      // Busca dados do solicitante
      print('🔐 [ActivityJoinRequestTrigger.execute] Buscando dados do solicitante: $requesterId');
      final requesterInfo = await getUserInfo(requesterId);
      print('🔐 [ActivityJoinRequestTrigger.execute] Solicitante: ${requesterInfo['fullName']}');

      // Gera mensagem usando template
      final template = NotificationTemplates.activityJoinRequest(
        requesterName: requesterInfo['fullName'] ?? 'Alguém',
        activityName: activity.name,
        emoji: activity.emoji,
      );

      print('🔐 [ActivityJoinRequestTrigger.execute] Template gerado: ${template.title}');

      // Notifica apenas o dono
      print('🔐 [ActivityJoinRequestTrigger.execute] Criando notificação para owner: $ownerId');
      await createNotification(
        receiverId: ownerId,
        type: ActivityNotificationTypes.activityJoinRequest,
        params: {
          'title': template.title,
          'body': template.body,
          'preview': template.preview,
          ...template.extra,
        },
        senderId: requesterId,
        senderName: requesterInfo['fullName'],
        senderPhotoUrl: requesterInfo['photoUrl'],
        relatedId: activity.id,
      );

      print('✅ [ActivityJoinRequestTrigger.execute] CONCLUÍDO - Notificação enviada para owner: $ownerId');
    } catch (e, stackTrace) {
      print('❌ [ActivityJoinRequestTrigger.execute] ERRO: $e');
      print('❌ [ActivityJoinRequestTrigger.execute] StackTrace: $stackTrace');
    }
  }

  Future<String?> _getActivityOwner(String activityId) async {
    try {
      final activityDoc = await firestore
          .collection('Events')
          .doc(activityId)
          .get();

      if (!activityDoc.exists) return null;

      return activityDoc.data()?['createdBy'] as String?;
    } catch (e) {
      return null;
    }
  }
}
