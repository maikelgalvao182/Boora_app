import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/create_flow/activity_draft.dart';
import 'package:partiu/features/home/presentation/widgets/schedule/time_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/participants/privacy_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/category/activity_category.dart';
import 'package:partiu/core/utils/geohash_helper.dart';

/// Repositório para gerenciar atividades no Firestore
/// 
/// ✅ Notificações agora são criadas via Cloud Functions:
/// - onActivityCreatedNotification: nova atividade
/// - onActivityCanceledNotification: atividade cancelada
/// - onApplicationApproved: novo participante
class ActivityRepository {
  final FirebaseFirestore _firestore;

  ActivityRepository({
    FirebaseFirestore? firestore,
  })  : _firestore = firestore ?? FirebaseFirestore.instance;

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

    final docRef = _firestore.collection('events').doc();
    final eventId = docRef.id;

    // Construir documento
    final docData = {
      // Id do documento (útil para queries/serialização)
      'eventId': eventId,

      // Informações básicas
      'activityText': draft.activityText!.trim(),
      'emoji': draft.emoji!,
      'category': draft.category != null ? categoryToString(draft.category!) : null,
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
        'state': draft.location!.administrativeAreaLevel1?.shortName ?? '',
        'placeId': draft.location!.placeId,
        // 🗺️ Geohash para queries geográficas mais eficientes (precision 7 = ~150m)
        'geohash': GeohashHelper.encode(
          draft.location!.latLng!.latitude,
          draft.location!.latLng!.longitude,
          precision: 7,
        ),
      },

      // Fotos do lugar (opcional)
      if (draft.photoReferences != null && draft.photoReferences!.isNotEmpty)
        'photoReferences': draft.photoReferences, // URLs reais do Google Places

      // Agendamento
      // Se horário flexível, salvar data às 00:00 para DateFormatter retornar vazio
      'schedule': {
        'date': Timestamp.fromDate(
          draft.timeType == TimeType.flexible
              ? DateTime(draft.selectedDate!.year, draft.selectedDate!.month, draft.selectedDate!.day, 0, 0, 0)
              : (draft.selectedTime ?? draft.selectedDate!),
        ),
        'timeType': _timeTypeToString(draft.timeType!),
      },

      // Participantes
      'participants': {
        'minAge': draft.minAge!,
        'maxAge': draft.maxAge!,
        'privacyType': _privacyTypeToString(draft.privacyType!),
        'currentCount': 1, // Criador já está participando
        'maxCount': 100, // Sempre ilimitado
        'gender': draft.gender,
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
      await docRef.set(docData);
      
      // ✅ Notificações agora são criadas via Cloud Function (onActivityCreatedNotification)
      // O trigger escuta onCreate em "events" e cria notificações automaticamente
      // Removida chamada direta que causava permission-denied
      
      return eventId;
    } catch (e) {
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
      await _firestore.collection('events').doc(activityId).update({
        'status': 'canceled',
        'isActive': false,
        'isCanceled': true,
        'canceledBy': userId,
        'canceledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ [ActivityRepository] Atividade $activityId cancelada');
      
      // ✅ Notificações de cancelamento agora são criadas via Cloud Function:
      // - onActivityCanceledNotification: detecta isActive: true → false
      // Removida chamada direta que causava permission-denied
      debugPrint('✅ [ActivityRepository.cancelActivity] Notificações serão enviadas via Cloud Function');
    } catch (e) {
      debugPrint('❌ [ActivityRepository] Erro ao cancelar atividade: $e');
      rethrow;
    }
  }

  /// Adiciona um participante à atividade
  Future<void> addParticipant(String activityId, String userId) async {
    try {
      await _firestore.collection('events').doc(activityId).update({
        'participants.participantIds': FieldValue.arrayUnion([userId]),
        'participants.currentCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ [ActivityRepository] Participante $userId adicionado');
      
      // ✅ Notificações de novo participante são criadas via Cloud Function:
      // - onApplicationApproved (index.ts): envia push quando EventApplication é aprovada
      // Removida chamada direta que causava permission-denied
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
      case PrivacyType.specificGender:
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
