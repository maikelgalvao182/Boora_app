import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/services/geo_index_service.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/notifications/services/user_affinity_service.dart';
import 'package:partiu/features/notifications/templates/notification_templates.dart';
import 'package:partiu/features/notifications/triggers/base_activity_trigger.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/core/utils/app_localizations.dart';

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
    try {
      final i18n = await AppLocalizations.loadForLanguageCode(AppLocalizations.currentLocale);

      final currentCount = context['currentCount'] as int?;

      if (currentCount == null) {
        AppLogger.warning(
          'ActivityHeatingUpTrigger: currentCount não fornecido',
          tag: 'NOTIFICATIONS',
        );
        return;
      }

      // PASSO 1: Buscar participantes DENTRO do evento (para excluir)
      final eventParticipants = await _getEventParticipants(activity.id);
      final excludeIds = [...eventParticipants, activity.createdBy]; // Excluir participantes + criador

      // PASSO 2: Buscar usuários no raio geográfico
      final usersInRadius = await _geoIndexService.findUsersInRadius(
        latitude: activity.latitude,
        longitude: activity.longitude,
        radiusKm: EVENT_NOTIFICATION_RADIUS_KM,
        excludeUserIds: excludeIds,
      );

      if (usersInRadius.isEmpty) {
        AppLogger.info(
          'ActivityHeatingUpTrigger: nenhum usuário no raio',
          tag: 'NOTIFICATIONS',
        );
        return;
      }

      // PASSO 3: Para "heating up", NÃO aplicamos filtro de afinidade
      // Diferente de "activity_created", este trigger é para gerar FOMO/buzz
      // e deve alcançar mais pessoas no raio, não apenas quem tem interesses em comum
      final targetUsers = usersInRadius;

      // PASSO 4: Buscar dados do criador
      final creatorInfo = await getUserInfo(activity.createdBy);

      // PASSO 5: Gerar template de mensagem
      final template = NotificationTemplates.activityHeatingUp(
        i18n: i18n,
        activityName: activity.name,
        emoji: activity.emoji,
        creatorName: creatorInfo['fullName'] ?? i18n.translate('someone'),
        participantCount: currentCount,
      );

      // PASSO 6: Enviar notificações para usuários elegíveis
      AppLogger.info(
        'ActivityHeatingUpTrigger: enviando para ${targetUsers.length} usuários (count=$currentCount)',
        tag: 'NOTIFICATIONS',
      );
      int sent = 0;
      for (final userId in targetUsers) {
        final ok = await createNotification(
          receiverId: userId,
          type: ActivityNotificationTypes.activityHeatingUp,
          params: {
            'title': template.title,
            'body': template.body,
            'preview': template.preview,
            ...template.extra,
          },
          relatedId: activity.id,
          // ✅ CORREÇÃO: Passar dados do CRIADOR (não do participante que entrou)
          senderId: activity.createdBy,
          senderName: creatorInfo['fullName'],
          senderPhotoUrl: creatorInfo['photoUrl'],
        );

        if (!ok) {
          continue;
        }

        sent++;
      }

      AppLogger.success(
        'ActivityHeatingUpTrigger concluído: $sent/${targetUsers.length} notificações criadas',
        tag: 'NOTIFICATIONS',
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'ActivityHeatingUpTrigger: erro ao executar',
        tag: 'NOTIFICATIONS',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Busca IDs dos participantes que estão DENTRO do evento
  /// (para excluir das notificações heating up)
  Future<List<String>> _getEventParticipants(String activityId) async {
    try {
      final querySnapshot = await firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: activityId)
          .where('status', whereIn: ['approved', 'autoApproved'])
          .get();

      if (querySnapshot.docs.isEmpty) return [];

      final participantIds = querySnapshot.docs
          .map((doc) => doc.data()['userId'] as String)
          .toList();

      return participantIds;
    } catch (e, stackTrace) {
      AppLogger.error(
        'ActivityHeatingUpTrigger: erro ao buscar participantes',
        tag: 'NOTIFICATIONS',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }
}
