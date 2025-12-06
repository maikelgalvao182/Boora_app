import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/features/notifications/templates/notification_templates.dart';
import 'package:partiu/features/notifications/triggers/base_activity_trigger.dart';

/// TRIGGER 5: Novo participante entrou em atividade aberta (open)
/// 
/// Notificação (para o dono): "{fullName} entrou na sua atividade {emoji} {activityText}!"
class ActivityNewParticipantTrigger extends BaseActivityTrigger {
  const ActivityNewParticipantTrigger({
    required super.notificationRepository,
    required super.firestore,
  });

  @override
  Future<void> execute(
    ActivityModel activity,
    Map<String, dynamic> context,
  ) async {
    print('👥 [ActivityNewParticipantTrigger.execute] INICIANDO');
    print('👥 [ActivityNewParticipantTrigger.execute] Activity: ${activity.id} - ${activity.name} ${activity.emoji}');
    print('👥 [ActivityNewParticipantTrigger.execute] Context: $context');
    
    try {
      final participantId = context['participantId'] as String?;
      final participantName = context['participantName'] as String?;

      print('👥 [ActivityNewParticipantTrigger.execute] ParticipantId: $participantId');
      print('👥 [ActivityNewParticipantTrigger.execute] ParticipantName: $participantName');
      
      if (participantId == null || participantName == null) {
        print('❌ [ActivityNewParticipantTrigger.execute] Dados incompletos');
        return;
      }

      // Busca owner da atividade
      print('👥 [ActivityNewParticipantTrigger.execute] Buscando owner da atividade...');
      final ownerId = await _getActivityOwner(activity.id);
      print('👥 [ActivityNewParticipantTrigger.execute] OwnerId: $ownerId');
      
      if (ownerId == null || ownerId == participantId) {
        print('⚠️ [ActivityNewParticipantTrigger.execute] Owner não encontrado ou é o próprio participante');
        return;
      }

      print('👥 [ActivityNewParticipantTrigger.execute] Buscando dados do participante: $participantId');
      final participantInfo = await getUserInfo(participantId);
      print('👥 [ActivityNewParticipantTrigger.execute] Participante: ${participantInfo['fullName']}');

      // Gera mensagem usando template
      final template = NotificationTemplates.activityNewParticipant(
        participantName: participantInfo['fullName'] ?? 'Alguém',
        activityName: activity.name,
        emoji: activity.emoji,
      );

      print('👥 [ActivityNewParticipantTrigger.execute] Template gerado: ${template.title}');

      // Notifica apenas o dono
      print('👥 [ActivityNewParticipantTrigger.execute] Criando notificação para owner: $ownerId');
      await createNotification(
        receiverId: ownerId,
        type: ActivityNotificationTypes.activityNewParticipant,
        params: {
          'title': template.title,
          'body': template.body,
          'preview': template.preview,
          ...template.extra,
        },
        senderId: participantId,
        senderName: participantInfo['fullName'],
        senderPhotoUrl: participantInfo['photoUrl'],
        relatedId: activity.id,
      );

      print('✅ [ActivityNewParticipantTrigger.execute] CONCLUÍDO - Notificação enviada para owner: $ownerId');
    } catch (e, stackTrace) {
      print('❌ [ActivityNewParticipantTrigger.execute] ERRO: $e');
      print('❌ [ActivityNewParticipantTrigger.execute] StackTrace: $stackTrace');
    }
  }

  Future<String?> _getActivityOwner(String activityId) async {
    print('👥 [ActivityNewParticipantTrigger._getActivityOwner] Buscando doc: $activityId');
    try {
      final activityDoc = await firestore
          .collection('Events')
          .doc(activityId)
          .get();

      if (!activityDoc.exists) {
        print('⚠️ [ActivityNewParticipantTrigger._getActivityOwner] Documento não existe');
        return null;
      }

      final ownerId = activityDoc.data()?['createdBy'] as String?;
      print('✅ [ActivityNewParticipantTrigger._getActivityOwner] OwnerId: $ownerId');
      return ownerId;
    } catch (e, stackTrace) {
      print('❌ [ActivityNewParticipantTrigger._getActivityOwner] ERRO: $e');
      print('❌ [ActivityNewParticipantTrigger._getActivityOwner] StackTrace: $stackTrace');
      return null;
    }
  }
}
