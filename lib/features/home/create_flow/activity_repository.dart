import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/create_flow/activity_draft.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/home/presentation/widgets/schedule/time_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/participants/privacy_type_selector.dart';
import 'package:partiu/features/notifications/services/activity_notification_service.dart';

/// Repositório para gerenciar atividades no Firestore
class ActivityRepository {
  final FirebaseFirestore _firestore;
  final ActivityNotificationService? _notificationService;

  ActivityRepository({
    FirebaseFirestore? firestore,
    ActivityNotificationService? notificationService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _notificationService = notificationService;

  /// Salva uma nova atividade no Firestore
  Future<String> saveActivity(ActivityDraft draft, String userId) async {
    // Validações
    if (!draft.isComplete) {
      throw Exception('ActivityDraft está incompleto. Campos obrigatórios faltando.');
    }

    if (!draft.hasValidTime) {
      throw Exception('Horário específico não foi definido quando necessário.');
    }

    if (draft.location?.latLng == null) {
      throw Exception('Localização inválida ou sem coordenadas.');
    }

    // Construir documento
    final docData = {
      // Informações básicas
      'activityText': draft.activityText!.trim(),
      'emoji': draft.emoji!,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),

      // Localização
      'location': {
        'latitude': draft.location!.latLng!.latitude,
        'longitude': draft.location!.latLng!.longitude,
        'formattedAddress': draft.location!.formattedAddress ?? '',
        'locationName': draft.location!.name ?? '',
        'locality': draft.location!.locality ?? '',
        'placeId': draft.location!.placeId,
      },

      // Fotos do lugar (opcional)
      if (draft.photoReferences != null && draft.photoReferences!.isNotEmpty)
        'photoReferences': draft.photoReferences, // URLs reais do Google Places

      // Agendamento
      'schedule': {
        'date': Timestamp.fromDate(draft.selectedTime ?? draft.selectedDate!),
        'timeType': _timeTypeToString(draft.timeType!),
      },

      // Participantes
      'participants': {
        'minAge': draft.minAge!,
        'maxAge': draft.maxAge!,
        'privacyType': _privacyTypeToString(draft.privacyType!),
        'currentCount': 1, // Criador já está participando
        'maxCount': 100, // Sempre ilimitado
        'participantIds': [userId], // Criador é o primeiro participante
        'pendingApprovalIds': [], // Vazio inicialmente
      },

      // Status
      'status': 'active',
      'isActive': true,
      'isCanceled': false,
      'expiresAt': _calculateExpirationDate(draft.selectedDate!),
    };

    // Salvar no Firestore
    try {
      final docRef = await _firestore.collection('events').add(docData);
      
      // Notificar usuários próximos
      if (_notificationService != null) {
        try {
          final activity = ActivityModel(
            id: docRef.id,
            name: draft.activityText!,
            emoji: draft.emoji!,
            latitude: draft.location!.latLng!.latitude,
            longitude: draft.location!.latLng!.longitude,
            createdBy: userId,
            createdAt: DateTime.now(),
          );
          
          await _notificationService!.notifyActivityCreated(activity);
        } catch (notifError, stackTrace) {
          // Não falhar a criação da atividade por erro de notificação
        }
      }
      
      return docRef.id;
    } catch (e, stackTrace) {
      rethrow;
    }
  }

  /// Atualiza uma atividade existente
  Future<void> updateActivity(String activityId, Map<String, dynamic> updates) async {
    try {
      await _firestore.collection('events').doc(activityId).update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Cancela uma atividade
  Future<void> cancelActivity(String activityId, String userId) async {
    try {
      // Buscar atividade antes de cancelar
      final activityDoc = await _firestore.collection('events').doc(activityId).get();
      
      await _firestore.collection('events').doc(activityId).update({
        'status': 'canceled',
        'isActive': false,
        'isCanceled': true,
        'canceledBy': userId,
        'canceledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ [ActivityRepository] Atividade $activityId cancelada');
      
      // Notificar participantes
      debugPrint('🔔 [ActivityRepository.cancelActivity] Verificando notificações...');
      debugPrint('🔔 [ActivityRepository.cancelActivity] Service: ${_notificationService != null}, Doc exists: ${activityDoc.exists}');
      
      if (_notificationService != null && activityDoc.exists) {
        try {
          debugPrint('🔔 [ActivityRepository.cancelActivity] Criando ActivityModel do documento');
          final data = activityDoc.data()!;
          final activity = ActivityModel(
            id: activityId,
            name: data['activityText'] ?? '',
            emoji: data['emoji'] ?? '',
            latitude: data['location']?['latitude'] ?? 0.0,
            longitude: data['location']?['longitude'] ?? 0.0,
            createdBy: data['createdBy'] ?? '',
            createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          );
          debugPrint('🔔 [ActivityRepository.cancelActivity] ActivityModel: ${activity.id} - ${activity.name}');
          
          debugPrint('🔔 [ActivityRepository.cancelActivity] Chamando notifyActivityCanceled...');
          await _notificationService!.notifyActivityCanceled(activity);
          debugPrint('✅ [ActivityRepository.cancelActivity] Notificações enviadas com sucesso');
        } catch (notifError, stackTrace) {
          debugPrint('❌ [ActivityRepository.cancelActivity] Erro ao enviar notificações: $notifError');
          debugPrint('❌ [ActivityRepository.cancelActivity] StackTrace: $stackTrace');
        }
      } else {
        debugPrint('⚠️ [ActivityRepository.cancelActivity] Notificações puladas - Service: ${_notificationService != null}, Doc: ${activityDoc.exists}');
      }
    } catch (e) {
      debugPrint('❌ [ActivityRepository] Erro ao cancelar atividade: $e');
      rethrow;
    }
  }

  /// Adiciona um participante à atividade
  Future<void> addParticipant(String activityId, String userId) async {
    try {
      // Buscar atividade e dados do usuário antes de adicionar participante
      final activityDoc = await _firestore.collection('events').doc(activityId).get();
      final userDoc = await _firestore.collection('Users').doc(userId).get();
      
      await _firestore.collection('events').doc(activityId).update({
        'participants.participantIds': FieldValue.arrayUnion([userId]),
        'participants.currentCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ [ActivityRepository] Participante $userId adicionado');
      
      // Notificar outros participantes
      debugPrint('🔔 [ActivityRepository.addParticipant] Verificando notificações...');
      debugPrint('🔔 [ActivityRepository.addParticipant] Service: ${_notificationService != null}, Activity: ${activityDoc.exists}, User: ${userDoc.exists}');
      
      if (_notificationService != null && activityDoc.exists && userDoc.exists) {
        try {
          debugPrint('🔔 [ActivityRepository.addParticipant] Extraindo dados dos documentos');
          final data = activityDoc.data()!;
          final userData = userDoc.data()!;
          
          final activity = ActivityModel(
            id: activityId,
            name: data['activityText'] ?? '',
            emoji: data['emoji'] ?? '',
            latitude: data['location']?['latitude'] ?? 0.0,
            longitude: data['location']?['longitude'] ?? 0.0,
            createdBy: data['createdBy'] ?? '',
            createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          );
          final participantName = userData['fullname'] ?? 'Usuário';
          
          debugPrint('🔔 [ActivityRepository.addParticipant] Activity: ${activity.id} - ${activity.name}');
          debugPrint('🔔 [ActivityRepository.addParticipant] Participant: $userId - $participantName');
          
          debugPrint('🔔 [ActivityRepository.addParticipant] Chamando notifyNewParticipant...');
          await _notificationService!.notifyNewParticipant(
            activity: activity,
            participantId: userId,
            participantName: participantName,
          );
          debugPrint('✅ [ActivityRepository.addParticipant] Notificações enviadas com sucesso');
        } catch (notifError, stackTrace) {
          debugPrint('❌ [ActivityRepository.addParticipant] Erro ao enviar notificações: $notifError');
          debugPrint('❌ [ActivityRepository.addParticipant] StackTrace: $stackTrace');
        }
      } else {
        debugPrint('⚠️ [ActivityRepository.addParticipant] Notificações puladas - Service: ${_notificationService != null}, Activity: ${activityDoc.exists}, User: ${userDoc.exists}');
      }
    } catch (e) {
      debugPrint('❌ [ActivityRepository] Erro ao adicionar participante: $e');
      rethrow;
    }
  }

  /// Remove um participante da atividade
  Future<void> removeParticipant(String activityId, String userId) async {
    try {
      await _firestore.collection('events').doc(activityId).update({
        'participants.participantIds': FieldValue.arrayRemove([userId]),
        'participants.currentCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ [ActivityRepository] Participante $userId removido');
    } catch (e) {
      debugPrint('❌ [ActivityRepository] Erro ao remover participante: $e');
      rethrow;
    }
  }

  // Métodos auxiliares privados

  String _timeTypeToString(TimeType type) {
    switch (type) {
      case TimeType.flexible:
        return 'flexible';
      case TimeType.specific:
        return 'specific';
    }
  }

  String _privacyTypeToString(PrivacyType type) {
    switch (type) {
      case PrivacyType.open:
        return 'open';
      case PrivacyType.private:
        return 'private';
    }
  }

  /// Calcula data de expiração (meia-noite do dia da atividade)
  Timestamp _calculateExpirationDate(DateTime activityDate) {
    final expirationDate = DateTime(
      activityDate.year,
      activityDate.month,
      activityDate.day,
      23,
      59,
      59,
    );
    return Timestamp.fromDate(expirationDate);
  }
}
