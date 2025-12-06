import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/features/notifications/templates/notification_templates.dart';
import 'package:partiu/features/notifications/triggers/base_activity_trigger.dart';

/// TRIGGER 6: Atividade começando a esquentar (threshold de pessoas)
/// 
/// Power do Nomad Table.
/// 
/// Formato da notificação:
/// Linha 1 (activityText): Nome da atividade + emoji (ex: "Correr no parque 🏃")
/// Linha 2 (mensagem): "As pessoas estão participando da atividade de {creatorName}!"
/// 
/// Dispara quando atinge: 3, 5 ou 10 participantes
class ActivityHeatingUpTrigger extends BaseActivityTrigger {
  const ActivityHeatingUpTrigger({
    required super.notificationRepository,
    required super.firestore,
  });

  @override
  Future<void> execute(
    ActivityModel activity,
    Map<String, dynamic> context,
  ) async {
    print('🔥 [ActivityHeatingUpTrigger.execute] INICIANDO');
    print('🔥 [ActivityHeatingUpTrigger.execute] Activity: ${activity.id} - ${activity.name} ${activity.emoji}');
    print('🔥 [ActivityHeatingUpTrigger.execute] Context: $context');
    
    try {
      final currentCount = context['currentCount'] as int?;
      print('🔥 [ActivityHeatingUpTrigger.execute] CurrentCount: $currentCount');

      if (currentCount == null) {
        print('❌ [ActivityHeatingUpTrigger.execute] currentCount não fornecido');
        return;
      }

      // Busca participantes da atividade
      print('🔥 [ActivityHeatingUpTrigger.execute] Buscando participantes da atividade...');
      final participants = await _getActivityParticipants(activity.id);
      print('🔥 [ActivityHeatingUpTrigger.execute] Participantes encontrados: ${participants.length}');
      
      if (participants.isEmpty) {
        print('⚠️ [ActivityHeatingUpTrigger.execute] Nenhum participante encontrado');
        return;
      }

      // Busca dados do criador
      print('🔥 [ActivityHeatingUpTrigger.execute] Buscando dados do criador: ${activity.createdBy}');
      final creatorInfo = await getUserInfo(activity.createdBy);
      print('🔥 [ActivityHeatingUpTrigger.execute] Criador: ${creatorInfo['fullName']}');

      // Gera mensagem usando template
      final template = NotificationTemplates.activityHeatingUp(
        activityName: activity.name,
        emoji: activity.emoji,
        creatorName: creatorInfo['fullName'] ?? 'Alguém',
        participantCount: currentCount,
      );

      print('🔥 [ActivityHeatingUpTrigger.execute] Template gerado: ${template.title}');

      // Notifica todos os participantes
      print('🔥 [ActivityHeatingUpTrigger.execute] Enviando notificações para ${participants.length} participantes...');
      for (final participantId in participants) {
        print('🔥 [ActivityHeatingUpTrigger.execute] Criando notificação para: $participantId');
        await createNotification(
          receiverId: participantId,
          type: ActivityNotificationTypes.activityHeatingUp,
          params: {
            'title': template.title,
            'body': template.body,
            'preview': template.preview,
            ...template.extra,
          },
          relatedId: activity.id,
        );
        print('✅ [ActivityHeatingUpTrigger.execute] Notificação criada para: $participantId');
      }

      print('✅ [ActivityHeatingUpTrigger.execute] CONCLUÍDO - ${participants.length} notificações enviadas');
    } catch (e, stackTrace) {
      print('❌ [ActivityHeatingUpTrigger.execute] ERRO: $e');
      print('❌ [ActivityHeatingUpTrigger.execute] StackTrace: $stackTrace');
    }
  }

  Future<List<String>> _getActivityParticipants(String activityId) async {
    try {
      final activityDoc = await firestore
          .collection('Events')
          .doc(activityId)
          .get();

      if (!activityDoc.exists) return [];

      final data = activityDoc.data();
      final participantIds = data?['participantIds'] as List<dynamic>?;

      return participantIds?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      print('[ActivityHeatingUpTrigger] Erro ao buscar participantes: $e');
      return [];
    }
  }
}
