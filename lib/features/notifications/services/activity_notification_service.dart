import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/services/geo_index_service.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/features/notifications/services/notification_targeting_service.dart';
import 'package:partiu/features/notifications/services/notification_orchestrator.dart';
import 'package:partiu/features/notifications/services/user_affinity_service.dart';
import 'package:partiu/features/notifications/triggers/base_activity_trigger.dart';
import 'package:partiu/features/notifications/triggers/activity_created_trigger.dart';
import 'package:partiu/features/notifications/triggers/activity_join_request_trigger.dart';
import 'package:partiu/features/notifications/triggers/activity_join_approved_trigger.dart';
import 'package:partiu/features/notifications/triggers/activity_join_rejected_trigger.dart';
import 'package:partiu/features/notifications/triggers/activity_new_participant_trigger.dart';
import 'package:partiu/features/notifications/triggers/activity_heating_up_trigger.dart';
import 'package:partiu/features/notifications/triggers/activity_expiring_soon_trigger.dart';
import 'package:partiu/features/notifications/triggers/activity_canceled_trigger.dart';

/// Serviço orquestrador de notificações de atividades
/// 
/// Responsável por:
/// - Escutar eventos de atividades (criação, edição, cancelamento)
/// - Delegar para triggers específicos usando padrão Strategy
/// - Buscar usuários no raio de 30km (FREE_ACCOUNT_MAX_EVENT_DISTANCE_KM)
/// - Disparar notificações via NotificationRepository
/// 
/// Arquitetura:
/// ```
/// ActivityNotificationService (Orquestrador)
///         ↓
///   [Triggers Modulares]
///   - ActivityCreatedTrigger
///   - ActivityJoinRequestTrigger
///   - ActivityHeatingUpTrigger
///   - etc...
///         ↓
/// NotificationRepository (Persiste no Firestore)
/// ```
class ActivityNotificationService {
  ActivityNotificationService({
    required INotificationsRepository notificationRepository,
    required NotificationTargetingService targetingService,
    required NotificationOrchestrator orchestrator,
    required GeoIndexService geoIndexService,
    required UserAffinityService affinityService,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _notificationRepository = notificationRepository,
        _targetingService = targetingService,
        _orchestrator = orchestrator,
        _geoIndexService = geoIndexService,
        _affinityService = affinityService,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance {
    _initializeTriggers();
  }

  final INotificationsRepository _notificationRepository;
  final NotificationTargetingService _targetingService;
  final NotificationOrchestrator _orchestrator;
  final GeoIndexService _geoIndexService;
  final UserAffinityService _affinityService;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // Mapa de triggers indexado por tipo
  late final Map<String, BaseActivityTrigger> _triggers;

  /// Inicializa todos os triggers modulares
  void _initializeTriggers() {
    _triggers = {
      ActivityNotificationTypes.activityCreated: ActivityCreatedTrigger(
        notificationRepository: _notificationRepository,
        firestore: _firestore,
        targetingService: _targetingService,
        orchestrator: _orchestrator,
      ),
      ActivityNotificationTypes.activityJoinRequest: ActivityJoinRequestTrigger(
        notificationRepository: _notificationRepository,
        firestore: _firestore,
      ),
      ActivityNotificationTypes.activityJoinApproved: ActivityJoinApprovedTrigger(
        notificationRepository: _notificationRepository,
        firestore: _firestore,
      ),
      ActivityNotificationTypes.activityJoinRejected: ActivityJoinRejectedTrigger(
        notificationRepository: _notificationRepository,
        firestore: _firestore,
      ),
      ActivityNotificationTypes.activityNewParticipant: ActivityNewParticipantTrigger(
        notificationRepository: _notificationRepository,
        firestore: _firestore,
      ),
      ActivityNotificationTypes.activityHeatingUp: ActivityHeatingUpTrigger(
        notificationRepository: _notificationRepository,
        firestore: _firestore,
        geoIndexService: _geoIndexService,
        affinityService: _affinityService,
      ),
      ActivityNotificationTypes.activityExpiringSoon: ActivityExpiringSoonTrigger(
        notificationRepository: _notificationRepository,
        firestore: _firestore,
      ),
      ActivityNotificationTypes.activityCanceled: ActivityCanceledTrigger(
        notificationRepository: _notificationRepository,
        firestore: _firestore,
      ),
    };
  }

  /// Dispara notificação para nova atividade criada
  /// 
  /// Notifica todos os usuários dentro de FREE_ACCOUNT_MAX_EVENT_DISTANCE_KM (30km)
  Future<void> notifyActivityCreated(ActivityModel activity) async {
    print('🔔 [ActivityNotificationService.notifyActivityCreated] INICIANDO');
    print('🔔 [ActivityNotificationService.notifyActivityCreated] Activity: ${activity.id} - ${activity.name} ${activity.emoji}');
    print('🔔 [ActivityNotificationService.notifyActivityCreated] Localização: (${activity.latitude}, ${activity.longitude})');
    print('🔔 [ActivityNotificationService.notifyActivityCreated] Criador: ${activity.createdBy}');
    
    try {
      print('🔔 [ActivityNotificationService.notifyActivityCreated] Buscando trigger: ${ActivityNotificationTypes.activityCreated}');
      final trigger = _triggers[ActivityNotificationTypes.activityCreated];
      
      if (trigger == null) {
        print('❌ [ActivityNotificationService.notifyActivityCreated] TRIGGER É NULL!');
        print('❌ [ActivityNotificationService.notifyActivityCreated] Triggers disponíveis: ${_triggers.keys.toList()}');
        return;
      }
      
      print('✅ [ActivityNotificationService.notifyActivityCreated] Trigger encontrado: ${trigger.runtimeType}');
      print('🔔 [ActivityNotificationService.notifyActivityCreated] Executando trigger...');
      
      await trigger.execute(activity, {});
      
      print('✅ [ActivityNotificationService.notifyActivityCreated] Trigger executado com SUCESSO');
    } catch (e, stackTrace) {
      print('❌ [ActivityNotificationService.notifyActivityCreated] ERRO: $e');
      print('❌ [ActivityNotificationService.notifyActivityCreated] StackTrace: $stackTrace');
    }
  }

  /// Dispara notificação de pedido de entrada em atividade privada
  /// 
  /// Notifica apenas o dono da atividade
  Future<void> notifyJoinRequest({
    required ActivityModel activity,
    required String requesterId,
    required String requesterName,
  }) async {
    try {
      final trigger = _triggers[ActivityNotificationTypes.activityJoinRequest];
      if (trigger == null) return;

      await trigger.execute(activity, {
        'requesterId': requesterId,
        'requesterName': requesterName,
      });
    } catch (e) {
      print('[ActivityNotificationService] Erro ao notificar pedido: $e');
    }
  }

  /// Dispara notificação de aprovação de entrada
  /// 
  /// Notifica o usuário que foi aprovado
  Future<void> notifyJoinApproved({
    required ActivityModel activity,
    required String approvedUserId,
  }) async {
    try {
      final trigger = _triggers[ActivityNotificationTypes.activityJoinApproved];
      if (trigger == null) return;

      await trigger.execute(activity, {
        'approvedUserId': approvedUserId,
      });
    } catch (e) {
      print('[ActivityNotificationService] Erro ao notificar aprovação: $e');
    }
  }

  /// Dispara notificação de rejeição de entrada
  /// 
  /// Notifica o usuário que foi rejeitado
  Future<void> notifyJoinRejected({
    required ActivityModel activity,
    required String rejectedUserId,
  }) async {
    try {
      final trigger = _triggers[ActivityNotificationTypes.activityJoinRejected];
      if (trigger == null) return;

      await trigger.execute(activity, {
        'rejectedUserId': rejectedUserId,
      });
    } catch (e) {
      print('[ActivityNotificationService] Erro ao notificar rejeição: $e');
    }
  }

  /// Dispara notificação quando novo participante entra em atividade aberta
  /// 
  /// Notifica todos os participantes existentes (exceto o novo)
  Future<void> notifyNewParticipant({
    required ActivityModel activity,
    required String participantId,
    required String participantName,
  }) async {
    print('🔔 [ActivityNotificationService.notifyNewParticipant] INICIANDO');
    print('🔔 [ActivityNotificationService.notifyNewParticipant] Activity: ${activity.id} - ${activity.name}');
    print('🔔 [ActivityNotificationService.notifyNewParticipant] Participant: $participantId - $participantName');
    
    try {
      final trigger = _triggers[ActivityNotificationTypes.activityNewParticipant];
      
      if (trigger == null) {
        print('❌ [ActivityNotificationService.notifyNewParticipant] TRIGGER É NULL!');
        return;
      }
      
      print('✅ [ActivityNotificationService.notifyNewParticipant] Trigger encontrado, executando...');
      await trigger.execute(activity, {
        'participantId': participantId,
        'participantName': participantName,
      });
      print('✅ [ActivityNotificationService.notifyNewParticipant] Trigger executado com SUCESSO');
    } catch (e, stackTrace) {
      print('❌ [ActivityNotificationService.notifyNewParticipant] ERRO: $e');
      print('❌ [ActivityNotificationService.notifyNewParticipant] StackTrace: $stackTrace');
    }
  }

  /// Dispara notificação quando atividade atinge threshold de participantes
  /// 
  /// Thresholds: 3, 5, 10 participantes
  /// Notifica todos os participantes da atividade
  Future<void> notifyActivityHeatingUp({
    required ActivityModel activity,
    required int currentCount,
  }) async {
    try {
      print('🔥 [ActivityNotificationService.notifyActivityHeatingUp] CHAMADO');
      print('🔥 [ActivityNotificationService.notifyActivityHeatingUp] Activity: ${activity.id} - ${activity.name}');
      print('🔥 [ActivityNotificationService.notifyActivityHeatingUp] CurrentCount: $currentCount');
      print('🔥 [ActivityNotificationService.notifyActivityHeatingUp] Thresholds: ${ActivityNotificationTypes.heatingUpThresholds}');
      
      // Verifica se atingiu um threshold
      if (!ActivityNotificationTypes.heatingUpThresholds.contains(currentCount)) {
        print('⏭️ [ActivityNotificationService.notifyActivityHeatingUp] Count $currentCount NÃO é threshold, ignorando');
        return;
      }
      
      print('✅ [ActivityNotificationService.notifyActivityHeatingUp] Count $currentCount É THRESHOLD! Disparando trigger...');

      final trigger = _triggers[ActivityNotificationTypes.activityHeatingUp];
      if (trigger == null) {
        print('❌ [ActivityNotificationService.notifyActivityHeatingUp] Trigger não encontrado!');
        return;
      }

      await trigger.execute(activity, {
        'currentCount': currentCount,
      });
      
      print('✅ [ActivityNotificationService.notifyActivityHeatingUp] Trigger executado com sucesso');
    } catch (e, stackTrace) {
      print('❌ [ActivityNotificationService.notifyActivityHeatingUp] ERRO: $e');
      print('❌ [ActivityNotificationService.notifyActivityHeatingUp] StackTrace: $stackTrace');
    }
  }

  /// Dispara notificação quando atividade está próxima da expiração
  /// 
  /// Notifica todos os participantes quando faltam X horas
  Future<void> notifyActivityExpiringSoon({
    required ActivityModel activity,
    required int hoursRemaining,
  }) async {
    try {
      final trigger = _triggers[ActivityNotificationTypes.activityExpiringSoon];
      if (trigger == null) return;

      await trigger.execute(activity, {
        'hoursRemaining': hoursRemaining,
      });
    } catch (e) {
      print('[ActivityNotificationService] Erro ao notificar expiração: $e');
    }
  }

  /// Dispara notificação quando atividade é cancelada
  /// 
  /// Notifica todos os participantes
  Future<void> notifyActivityCanceled(ActivityModel activity) async {
    print('🔔 [ActivityNotificationService.notifyActivityCanceled] INICIANDO');
    print('🔔 [ActivityNotificationService.notifyActivityCanceled] Activity: ${activity.id} - ${activity.name}');
    
    try {
      final trigger = _triggers[ActivityNotificationTypes.activityCanceled];
      
      if (trigger == null) {
        print('❌ [ActivityNotificationService.notifyActivityCanceled] TRIGGER É NULL!');
        return;
      }
      
      print('✅ [ActivityNotificationService.notifyActivityCanceled] Trigger encontrado, executando...');
      await trigger.execute(activity, {});
      print('✅ [ActivityNotificationService.notifyActivityCanceled] Trigger executado com SUCESSO');
    } catch (e, stackTrace) {
      print('❌ [ActivityNotificationService.notifyActivityCanceled] ERRO: $e');
      print('❌ [ActivityNotificationService.notifyActivityCanceled] StackTrace: $stackTrace');
    }
  }

  /// Busca usuários dentro do raio de 30km
  /// 
  /// Usa geohash para query eficiente no Firestore
  /// Retorna lista de user IDs (exclui o criador da atividade)
  Future<List<String>> _findUsersInRadius({
    required double latitude,
    required double longitude,
    required String excludeUserId,
  }) async {
    try {
      // TODO: Implementar query geoespacial otimizada
      // Por enquanto, retorna lista vazia
      // Na implementação real, usar geoflutterfire ou similar
      
      final radiusInKm = FREE_ACCOUNT_MAX_EVENT_DISTANCE_KM;
      
      // Query básica (sem filtro geoespacial)
      final usersSnapshot = await _firestore
          .collection('Users')
          .where(FieldPath.documentId, isNotEqualTo: excludeUserId)
          .limit(100)
          .get();

      final nearbyUsers = <String>[];

      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final userLat = data['latitude'] as double?;
        final userLng = data['longitude'] as double?;

        if (userLat == null || userLng == null) continue;

        // Calcula distância
        final distance = Geolocator.distanceBetween(
          latitude,
          longitude,
          userLat,
          userLng,
        );

        // Converte para km e compara
        if (distance / 1000 <= radiusInKm) {
          nearbyUsers.add(doc.id);
        }
      }

      return nearbyUsers;
    } catch (e) {
      print('[ActivityNotificationService] Erro ao buscar usuários: $e');
      return [];
    }
  }

  /// Busca participantes de uma atividade
  Future<List<String>> _getActivityParticipants(String activityId) async {
    try {
      // TODO: Ajustar para estrutura real de participantes
      // Assumindo campo participantIds: [uid1, uid2, ...]
      
      final activityDoc = await _firestore
          .collection('events')
          .doc(activityId)
          .get();

      if (!activityDoc.exists) return [];

      final data = activityDoc.data();
      final participantIds = data?['participantIds'] as List<dynamic>?;

      return participantIds?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      print('[ActivityNotificationService] Erro ao buscar participantes: $e');
      return [];
    }
  }

  /// Obtém dados básicos de um usuário
  Future<Map<String, dynamic>?> _getUserData(String userId) async {
    try {
      final userDoc = await _firestore
          .collection('Users')
          .doc(userId)
          .get();

      if (!userDoc.exists) return null;

      final data = userDoc.data();
      return {
        'fullName': data?['fullname'] ?? 'Usuário',
        'photoUrl': data?['user_profile_photo'] ?? '',
      };
    } catch (e) {
      print('[ActivityNotificationService] Erro ao buscar dados do usuário: $e');
      return null;
    }
  }
}
