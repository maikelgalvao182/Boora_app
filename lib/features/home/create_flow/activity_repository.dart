import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/create_flow/activity_draft.dart';
import 'package:partiu/features/home/presentation/widgets/schedule/time_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/participants/privacy_type_selector.dart';

/// Repositório para gerenciar atividades no Firestore
class ActivityRepository {
  final FirebaseFirestore _firestore;

  ActivityRepository([FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

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
        'date': Timestamp.fromDate(draft.selectedDate!),
        'timeType': _timeTypeToString(draft.timeType!),
        if (draft.selectedTime != null)
          'specificTime': Timestamp.fromDate(draft.selectedTime!),
      },

      // Participantes
      'participants': {
        'minAge': draft.minAge!,
        'maxAge': draft.maxAge!,
        'privacyType': _privacyTypeToString(draft.privacyType!),
        'currentCount': 1, // Criador já está participando
        'maxCount': draft.maxParticipants ?? 100, // 0 = Aberto (100 padrão), 1-20 = específico
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
      debugPrint('✅ [ActivityRepository] Atividade salva com ID: ${docRef.id}');
      return docRef.id;
    } catch (e, stackTrace) {
      debugPrint('❌ [ActivityRepository] Erro ao salvar atividade: $e');
      debugPrint('Stack trace: $stackTrace');
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
      debugPrint('✅ [ActivityRepository] Atividade $activityId atualizada');
    } catch (e) {
      debugPrint('❌ [ActivityRepository] Erro ao atualizar atividade: $e');
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
