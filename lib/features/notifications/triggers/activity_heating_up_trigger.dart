import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/services/geo_index_service.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/features/notifications/services/user_affinity_service.dart';
import 'package:partiu/features/notifications/templates/notification_templates.dart';
import 'package:partiu/features/notifications/triggers/base_activity_trigger.dart';

/// TRIGGER 6: Atividade começando a esquentar (threshold de pessoas)
/// 
/// Power do Nomad Table - Notifica usuários EXTERNOS ao evento.
/// 
/// REGRAS DE NEGÓCIO:
/// 1. ✅ Notifica apenas usuários que NÃO estão no evento (não têm EventApplication)
/// 2. ✅ Aplica filtro geográfico (30km de raio usando GeoIndexService)
/// 3. ❌ NÃO aplica filtro de afinidade - é notificação de FOMO/buzz para alcançar mais pessoas
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
    required GeoIndexService geoIndexService,
    // ignore: unused_field - Mantido para compatibilidade da interface
    required UserAffinityService affinityService,
  })  : _geoIndexService = geoIndexService,
        // ignore: unused_field
        _affinityService = affinityService;

  final GeoIndexService _geoIndexService;
  // ignore: unused_field - Não usado desde remoção do filtro de afinidade
  final UserAffinityService _affinityService;

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

      // Verificar coordenadas da atividade
      if (activity.latitude == null || activity.longitude == null) {
        print('❌ [ActivityHeatingUpTrigger.execute] Atividade sem localização');
        return;
      }

      // PASSO 1: Buscar participantes DENTRO do evento (para excluir)
      print('🔥 [ActivityHeatingUpTrigger.execute] Buscando participantes do evento...');
      final eventParticipants = await _getEventParticipants(activity.id);
      final excludeIds = [...eventParticipants, activity.createdBy]; // Excluir participantes + criador
      print('🔥 [ActivityHeatingUpTrigger.execute] IDs a excluir: ${excludeIds.length} (${eventParticipants.length} participantes + 1 criador)');

      // PASSO 2: Buscar usuários no raio geográfico (30km)
      print('🔥 [ActivityHeatingUpTrigger.execute] Buscando usuários no raio de 30km...');
      final usersInRadius = await _geoIndexService.findUsersInRadius(
        latitude: activity.latitude!,
        longitude: activity.longitude!,
        radiusKm: 30.0,
        excludeUserIds: excludeIds,
      );
      print('🔥 [ActivityHeatingUpTrigger.execute] Usuários no raio: ${usersInRadius.length}');

      if (usersInRadius.isEmpty) {
        print('⚠️ [ActivityHeatingUpTrigger.execute] Nenhum usuário encontrado no raio');
        return;
      }

      // PASSO 3: Para "heating up", NÃO aplicamos filtro de afinidade
      // Diferente de "activity_created", este trigger é para gerar FOMO/buzz
      // e deve alcançar mais pessoas no raio, não apenas quem tem interesses em comum
      final targetUsers = usersInRadius;
      print('🔥 [ActivityHeatingUpTrigger.execute] Usuários alvo (todos no raio): ${targetUsers.length}');

      // PASSO 4: Buscar dados do criador
      print('🔥 [ActivityHeatingUpTrigger.execute] Buscando dados do criador: ${activity.createdBy}');
      final creatorInfo = await getUserInfo(activity.createdBy);
      print('🔥 [ActivityHeatingUpTrigger.execute] Criador: ${creatorInfo['fullName']}');

      // PASSO 5: Gerar template de mensagem
      final template = NotificationTemplates.activityHeatingUp(
        activityName: activity.name,
        emoji: activity.emoji,
        creatorName: creatorInfo['fullName'] ?? 'Alguém',
        participantCount: currentCount,
      );

      print('🔥 [ActivityHeatingUpTrigger.execute] Template gerado: ${template.title}');

      // PASSO 6: Enviar notificações para usuários elegíveis
      print('🔥 [ActivityHeatingUpTrigger.execute] Enviando notificações para ${targetUsers.length} usuários...');
      int sent = 0;
      for (final userId in targetUsers) {
        try {
          await createNotification(
            receiverId: userId,
            type: ActivityNotificationTypes.activityHeatingUp,
            params: {
              'title': template.title,
              'body': template.body,
              'preview': template.preview,
              ...template.extra,
            },
            relatedId: activity.id,
          );
          sent++;
          print('✅ [ActivityHeatingUpTrigger.execute] [$sent/${targetUsers.length}] Notificação criada para: $userId');
        } catch (e) {
          print('❌ [ActivityHeatingUpTrigger.execute] Erro ao notificar $userId: $e');
        }
      }

      print('✅ [ActivityHeatingUpTrigger.execute] CONCLUÍDO - $sent notificações enviadas');
      print('📊 [ActivityHeatingUpTrigger.execute] Resumo:');
      print('   • Participantes no evento: ${eventParticipants.length}');
      print('   • Usuários no raio (30km): ${usersInRadius.length}');
      print('   • Notificações enviadas: $sent');
    } catch (e, stackTrace) {
      print('❌ [ActivityHeatingUpTrigger.execute] ERRO: $e');
      print('❌ [ActivityHeatingUpTrigger.execute] StackTrace: $stackTrace');
    }
  }

  /// Busca IDs dos participantes que estão DENTRO do evento
  /// (para excluir das notificações heating up)
  Future<List<String>> _getEventParticipants(String activityId) async {
    try {
      print('🔍 [ActivityHeatingUpTrigger._getEventParticipants] Buscando aplicações aprovadas para: $activityId');
      
      final querySnapshot = await firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: activityId)
          .where('status', whereIn: ['approved', 'autoApproved'])
          .get();

      print('🔍 [ActivityHeatingUpTrigger._getEventParticipants] Encontradas ${querySnapshot.docs.length} aplicações aprovadas');

      if (querySnapshot.docs.isEmpty) return [];

      final participantIds = querySnapshot.docs
          .map((doc) => doc.data()['userId'] as String)
          .toList();

      print('🔍 [ActivityHeatingUpTrigger._getEventParticipants] ParticipantIds: $participantIds');
      return participantIds;
    } catch (e, stackTrace) {
      print('❌ [ActivityHeatingUpTrigger._getEventParticipants] ERRO: $e');
      print('❌ [ActivityHeatingUpTrigger._getEventParticipants] StackTrace: $stackTrace');
      return [];
    }
  }
}
