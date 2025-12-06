import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/notifications/templates/notification_templates.dart';

/// ===============================================================
/// UserInfo MODEL
/// ===============================================================
class UserInfo {
  final String id;
  final String fullName;
  final String? photoUrl;

  UserInfo({
    required this.id,
    required this.fullName,
    this.photoUrl,
  });
}

/// ===============================================================
/// CAMADA 3 — Notification Orchestrator (V3)
/// ===============================================================
/// Responsável por:
/// - Criar documentos na coleção Notifications
/// - Batch writes (500 operações)
/// - Aplicar templates padronizados
/// - Enriquecer notificações com dados estruturados
///
/// NÃO FAZ:
/// - Targeting (CAMADA 2)
/// - Geo / Afinidade (CAMADAS 0 e 1)
class NotificationOrchestrator {
  final FirebaseFirestore _firestore;

  static const int BATCH_LIMIT = 500;

  NotificationOrchestrator({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  // ============================================================
  // MÉTODOS UNIVERSAIS (CORE DO SISTEMA)
  // ============================================================

  /// ✨ Função universal para criar 1 notificação
  Future<void> _sendSingleNotification({
    required String receiverId,
    required String type,
    required Map<String, dynamic> params,
    String? senderId,
    String? senderName,
    String? senderPhoto,
    required String relatedId,
  }) async {
    final ref = _firestore.collection(C_NOTIFICATIONS).doc();

    await ref.set({
      if (senderId != null) N_SENDER_ID: senderId,
      if (senderName != null) N_SENDER_FULLNAME: senderName,
      if (senderPhoto != null) N_SENDER_PHOTO_LINK: senderPhoto,
      N_RECEIVER_ID: receiverId,
      N_TYPE: type,
      N_PARAMS: params,
      N_RELATED_ID: relatedId,
      N_READ: false,
      TIMESTAMP: FieldValue.serverTimestamp(),
    });
  }

  /// ✨ Função universal para criar notificações em massa (com batch)
  Future<void> _sendBatchNotifications({
    required List<String> receivers,
    required String type,
    required Map<String, dynamic> Function(String receiverId) buildParams,
    String? senderId,
    String? senderName,
    String? senderPhoto,
    required String relatedId,
  }) async {
    print('📦 [Orchestrator] _sendBatchNotifications INICIANDO');
    print('📦 [Orchestrator] Receivers: ${receivers.length}');
    print('📦 [Orchestrator] Type: $type');
    print('📦 [Orchestrator] Sender: $senderName ($senderId)');
    print('📦 [Orchestrator] Related ID: $relatedId');
    
    if (receivers.isEmpty) {
      print('⚠️ [Orchestrator] Lista de receivers VAZIA - ABORTANDO');
      return;
    }

    var batch = _firestore.batch();
    var count = 0;

    for (final receiverId in receivers) {
      final ref = _firestore.collection(C_NOTIFICATIONS).doc();
      final params = buildParams(receiverId);
      
      final notificationData = {
        if (senderId != null) N_SENDER_ID: senderId,
        if (senderName != null) N_SENDER_FULLNAME: senderName,
        if (senderPhoto != null) N_SENDER_PHOTO_LINK: senderPhoto,
        N_RECEIVER_ID: receiverId,
        N_TYPE: type,
        N_PARAMS: params,
        N_RELATED_ID: relatedId,
        N_READ: false,
        TIMESTAMP: FieldValue.serverTimestamp(),
      };
      
      print('📤 [Orchestrator] Adicionando notificação para: $receiverId');
      print('   • Title: ${params['title']}');
      print('   • Body: ${params['body']}');
      print('   • Receiver ID: $receiverId');
      
      batch.set(ref, notificationData);

      count++;

      if (count >= BATCH_LIMIT) {
        print('💾 [Orchestrator] Comitando batch de $count notificações...');
        await batch.commit();
        print('✅ [Orchestrator] Batch comitado');
        batch = _firestore.batch();
        count = 0;
      }
    }

    if (count > 0) {
      print('💾 [Orchestrator] Comitando batch final de $count notificações...');
      await batch.commit();
      print('✅ [Orchestrator] Batch final comitado com SUCESSO');
    }
    
    print('🎉 [Orchestrator] _sendBatchNotifications CONCLUÍDO - ${receivers.length} notificações criadas');
  }

  // ============================================================
  // NOTIFICAÇÕES POR TIPO (CAMADA 3)
  // ============================================================

  /// 🟦 1 — Atividade Criada
  Future<void> createActivityCreatedNotifications({
    required ActivityModel activity,
    required Map<String, List<String>> affinityMap,
    required UserInfo creator,
  }) async {
    print('🎯 [Orchestrator.createActivityCreatedNotifications] INICIANDO');
    print('🎯 [Orchestrator] Activity: ${activity.id} - ${activity.name}');
    print('🎯 [Orchestrator] Criador: ${creator.fullName} (${creator.id})');
    print('🎯 [Orchestrator] AffinityMap tem ${affinityMap.length} usuários');
    
    if (affinityMap.isEmpty) {
      print('⚠️ [Orchestrator] AffinityMap VAZIO - ABORTANDO');
      return;
    }
    
    final receivers = affinityMap.keys.toList();
    print('🎯 [Orchestrator] Receivers IDs: $receivers');

    await _sendBatchNotifications(
      receivers: receivers,
      type: ActivityNotificationTypes.activityCreated,
      senderId: creator.id,
      senderName: creator.fullName,
      senderPhoto: creator.photoUrl,
      relatedId: activity.id,
      buildParams: (userId) {
        final interests = affinityMap[userId]!;
        final template = NotificationTemplates.activityCreated(
          creatorName: creator.fullName,
          activityName: activity.name,
          emoji: activity.emoji,
          commonInterests: interests,
        );

        return {
          'title': template.title,
          'body': template.body,
          'preview': template.preview,
          'activityId': activity.id,
          'emoji': activity.emoji,
          'commonInterests': interests,
          ...template.extra,
        };
      },
    );
    
    print('✅ [Orchestrator.createActivityCreatedNotifications] CONCLUÍDO');
  }

  /// 🔥 2 — Atividade Esquentando
  Future<void> createActivityHeatingUpNotifications({
    required ActivityModel activity,
    required List<String> participantIds,
    required UserInfo creator,
    required int participantCount,
  }) async {
    if (participantIds.isEmpty) return;

    await _sendBatchNotifications(
      receivers: participantIds,
      type: ActivityNotificationTypes.activityHeatingUp,
      relatedId: activity.id,
      senderId: creator.id,
      senderName: creator.fullName,
      senderPhoto: creator.photoUrl,
      buildParams: (_) {
        final template = NotificationTemplates.activityHeatingUp(
          activityName: activity.name,
          emoji: activity.emoji,
          creatorName: creator.fullName,
          participantCount: participantCount,
        );

        return {
          'title': template.title,
          'body': template.body,
          'preview': template.preview,
          'activityId': activity.id,
          ...template.extra,
        };
      },
    );
  }

  /// 🔐 3 — Pedido para entrar
  Future<void> createJoinRequestNotification({
    required ActivityModel activity,
    required String ownerId,
    required UserInfo requester,
  }) async {
    final template = NotificationTemplates.activityJoinRequest(
      requesterName: requester.fullName,
      activityName: activity.name,
      emoji: activity.emoji,
    );

    await _sendSingleNotification(
      receiverId: ownerId,
      type: ActivityNotificationTypes.activityJoinRequest,
      senderId: requester.id,
      senderName: requester.fullName,
      senderPhoto: requester.photoUrl,
      relatedId: activity.id,
      params: {
        'title': template.title,
        'body': template.body,
        'preview': template.preview,
        'activityId': activity.id,
        ...template.extra,
      },
    );
  }

  /// 🟩 4 — Entrada Aprovada
  Future<void> createJoinApprovedNotification({
    required ActivityModel activity,
    required String approvedUserId,
    required UserInfo owner,
  }) async {
    final template = NotificationTemplates.activityJoinApproved(
      activityName: activity.name,
      emoji: activity.emoji,
    );

    await _sendSingleNotification(
      receiverId: approvedUserId,
      type: ActivityNotificationTypes.activityJoinApproved,
      senderId: owner.id,
      senderName: owner.fullName,
      senderPhoto: owner.photoUrl,
      relatedId: activity.id,
      params: {
        'title': template.title,
        'body': template.body,
        'preview': template.preview,
        'activityId': activity.id,
        ...template.extra,
      },
    );
  }

  /// 🟥 5 — Entrada Recusada
  Future<void> createJoinRejectedNotification({
    required ActivityModel activity,
    required String rejectedUserId,
    required UserInfo owner,
  }) async {
    final template = NotificationTemplates.activityJoinRejected(
      activityName: activity.name,
      emoji: activity.emoji,
    );

    await _sendSingleNotification(
      receiverId: rejectedUserId,
      type: ActivityNotificationTypes.activityJoinRejected,
      senderId: owner.id,
      senderName: owner.fullName,
      senderPhoto: owner.photoUrl,
      relatedId: activity.id,
      params: {
        'title': template.title,
        'body': template.body,
        'preview': template.preview,
        'activityId': activity.id,
        ...template.extra,
      },
    );
  }

  /// 👥 6 — Novo Participante
  Future<void> createNewParticipantNotification({
    required ActivityModel activity,
    required String ownerId,
    required UserInfo participant,
  }) async {
    final template = NotificationTemplates.activityNewParticipant(
      participantName: participant.fullName,
      activityName: activity.name,
      emoji: activity.emoji,
    );

    await _sendSingleNotification(
      receiverId: ownerId,
      type: ActivityNotificationTypes.activityNewParticipant,
      senderId: participant.id,
      senderName: participant.fullName,
      senderPhoto: participant.photoUrl,
      relatedId: activity.id,
      params: {
        'title': template.title,
        'body': template.body,
        'preview': template.preview,
        'activityId': activity.id,
        ...template.extra,
      },
    );
  }

  /// ⏰ 7 — Atividade Expirando
  Future<void> createActivityExpiringNotifications({
    required ActivityModel activity,
    required List<String> participantIds,
    required int hoursRemaining,
  }) async {
    await _sendBatchNotifications(
      receivers: participantIds,
      type: ActivityNotificationTypes.activityExpiringSoon,
      relatedId: activity.id,
      buildParams: (_) {
        final template = NotificationTemplates.activityExpiringSoon(
          activityName: activity.name,
          emoji: activity.emoji,
          hoursRemaining: hoursRemaining,
        );

        return {
          'title': template.title,
          'body': template.body,
          'preview': template.preview,
          'activityId': activity.id,
          ...template.extra,
        };
      },
    );
  }

  /// 🚫 8 — Atividade Cancelada
  Future<void> createActivityCanceledNotifications({
    required ActivityModel activity,
    required List<String> participantIds,
  }) async {
    await _sendBatchNotifications(
      receivers: participantIds,
      type: ActivityNotificationTypes.activityCanceled,
      relatedId: activity.id,
      buildParams: (_) {
        final template = NotificationTemplates.activityCanceled(
          activityName: activity.name,
          emoji: activity.emoji,
        );

        return {
          'title': template.title,
          'body': template.body,
          'preview': template.preview,
          'activityId': activity.id,
          ...template.extra,
        };
      },
    );
  }
}
