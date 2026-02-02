import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/services/geo_index_service.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/services/user_affinity_service.dart';

/// ---------------------------------------------------------------------------
/// CAMADA 2 — TARGETING DE NOTIFICAÇÕES
///
/// RESPONSÁVEL POR:
/// - Decidir QUEM deve receber cada tipo de notificação
/// - Com base em regras: geolocalização, afinidade, participantes, criador.
/// 
/// NÃO cria notificações.
/// NÃO formata mensagens.
/// NÃO toca UI.
///
/// Retorna sempre:
///   Map<userId, List<String>> → lista de interesses em comum (pode ser vazia)
/// ---------------------------------------------------------------------------
class NotificationTargetingService {
  final GeoIndexService _geo;
  final UserAffinityService _affinity;
  final FirebaseFirestore _firestore;

  NotificationTargetingService({
    required GeoIndexService geoService,
    required UserAffinityService affinityService,
    FirebaseFirestore? firestore,
  })  : _geo = geoService,
        _affinity = affinityService,
        _firestore = firestore ?? FirebaseFirestore.instance;

  // ===========================================================================
  // 1 — ACTIVITY_CREATED → GEO + AFINIDADE
  // ===========================================================================
  Future<Map<String, List<String>>> getUsersForActivityCreated(
    ActivityModel activity,
  ) async {
    print('\n🎯 [Targeting] activity_created → INÍCIO');
    print('🎯 [Targeting] Criador a EXCLUIR: ${activity.createdBy}');

    try {
      // 1. Geo
      final nearby = await _geo.findUsersInRadius(
        latitude: activity.latitude,
        longitude: activity.longitude,
        radiusKm: EVENT_NOTIFICATION_RADIUS_KM,
        excludeUserIds: [activity.createdBy],
        limit: 500,
      );

      print('🌍 [Targeting] Dentro do raio: ${nearby.length} users');
      if (nearby.isNotEmpty) {
        print('🌍 [Targeting] Primeiros 5 IDs: ${nearby.take(5).toList()}');
        print('🌍 [Targeting] Criador está na lista? ${nearby.contains(activity.createdBy) ? "❌ SIM (ERRO!)" : "✅ NÃO (correto)"}');
      }

      if (nearby.isEmpty) return {};

      // 2. Afinidade
      final affinity = await _affinity.calculateAffinityMap(
        creatorId: activity.createdBy,
        candidateUserIds: nearby,
      );

      print('💖 [Targeting] Afinidade válida: ${affinity.length} users');
      if (affinity.isNotEmpty) {
        print('💖 [Targeting] Primeiros 5 com afinidade: ${affinity.keys.take(5).toList()}');
        print('💖 [Targeting] Criador está nos resultados? ${affinity.containsKey(activity.createdBy) ? "❌ SIM (ERRO!)" : "✅ NÃO (correto)"}');
      }
      print('✅ [Targeting] activity_created → FIM');
      return affinity;

    } catch (e, st) {
      print('❌ [Targeting] ERRO activity_created: $e');
      print(st);
      return {};
    }
  }

  // ===========================================================================
  // 2 — ACTIVITY_HEATING_UP → PARTICIPANTES
  // ===========================================================================
  Future<Map<String, List<String>>> getUsersForActivityHeatingUp(
    String activityId,
  ) async {
    print('\n🔥 [Targeting] activity_heating_up');

    final participants = await _getParticipants(activityId);
    return {for (final u in participants) u: const []};
  }

  // ===========================================================================
  // 3 — JOIN_REQUEST → CRIADOR
  // ===========================================================================
  Future<Map<String, List<String>>> getUsersForJoinRequest(
    String activityId,
  ) async {
    print('\n📨 [Targeting] join_request');

    final owner = await _getOwner(activityId);
    if (owner == null) return {};

    return {owner: const []};
  }

  // ===========================================================================
  // 4 — JOIN_APPROVED → SOLICITANTE
  // ===========================================================================
  Future<Map<String, List<String>>> getUsersForJoinApproved(
    String approvedUserId,
  ) async {
    print('\n👍 [Targeting] join_approved');
    return {approvedUserId: const []};
  }

  // ===========================================================================
  // 5 — JOIN_REJECTED → SOLICITANTE
  // ===========================================================================
  Future<Map<String, List<String>>> getUsersForJoinRejected(
    String rejectedUserId,
  ) async {
    print('\n🚫 [Targeting] join_rejected');
    return {rejectedUserId: const []};
  }

  // ===========================================================================
  // 6 — NEW_PARTICIPANT → CRIADOR
  // ===========================================================================
  Future<Map<String, List<String>>> getUsersForNewParticipant(
    String activityId,
  ) async {
    print('\n👥 [Targeting] new_participant');

    final owner = await _getOwner(activityId);
    if (owner == null) return {};

    return {owner: const []};
  }

  // ===========================================================================
  // 7 — ACTIVITY_EXPIRING → PARTICIPANTES
  // ===========================================================================
  Future<Map<String, List<String>>> getUsersForActivityExpiring(
    String activityId,
  ) async {
    print('\n⏰ [Targeting] activity_expiring');

    final participants = await _getParticipants(activityId);
    return {for (final u in participants) u: const []};
  }

  // ===========================================================================
  // 8 — ACTIVITY_CANCELED → PARTICIPANTES
  // ===========================================================================
  Future<Map<String, List<String>>> getUsersForActivityCanceled(
    String activityId,
  ) async {
    print('\n🛑 [Targeting] activity_canceled');

    final participants = await _getParticipants(activityId);
    return {for (final u in participants) u: const []};
  }

  // ===========================================================================
  // HELPERS PRIVADOS
  // ===========================================================================

  Future<List<String>> _getParticipants(String activityId) async {
    try {
      final doc =
          await _firestore.collection('events').doc(activityId).get();

      if (!doc.exists) return [];

      final list = doc.data()?['participantIds'] as List<dynamic>? ?? [];
      return list.map((e) => e.toString()).toList();

    } catch (e) {
      print('❌ [Targeting] Erro ao buscar participantes: $e');
      return [];
    }
  }

  Future<String?> _getOwner(String activityId) async {
    try {
      final doc =
          await _firestore.collection('events').doc(activityId).get();

      if (!doc.exists) return null;

      return doc.data()?['createdBy'] as String?;

    } catch (e) {
      print('❌ [Targeting] Erro ao buscar owner: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ANALYTICS / DEBUG
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> getTargetingStats(ActivityModel a) async {
    final radiusUsers = await _geo.findUsersInRadius(
      latitude: a.latitude,
      longitude: a.longitude,
      radiusKm: EVENT_NOTIFICATION_RADIUS_KM,
      excludeUserIds: [a.createdBy],
      limit: 500,
    );

    final affinity = await _affinity.calculateAffinityMap(
      creatorId: a.createdBy,
      candidateUserIds: radiusUsers,
    );

    return {
      'activityId': a.id,
      'activityName': a.name,
      'radiusUsers': radiusUsers.length,
      'affinityUsers': affinity.length,
      'conversionRate': radiusUsers.isEmpty
          ? 0.0
          : affinity.length / radiusUsers.length,
    };
  }
}
