import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/dialogs/common_dialogs.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/core/services/toast_service.dart';

/// Serviço responsável por remover aplicações de usuários em eventos
/// 
/// IMPORTANTE: As operações são executadas via Cloud Function para garantir:
/// - Segurança (validação server-side)
/// - Atomicidade (todas as operações juntas)
/// - Confiabilidade (não depende do cliente manter conexão)
class EventApplicationRemovalService {
  factory EventApplicationRemovalService() => _instance;
  EventApplicationRemovalService._internal();
  
  static final EventApplicationRemovalService _instance = 
      EventApplicationRemovalService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Remove a aplicação do usuário no evento
  Future<void> handleRemoveUserApplication({
    required BuildContext context,
    required String eventId,
    required AppLocalizations i18n,
    required ProgressDialog progressDialog,
    required VoidCallback onSuccess,
  }) async {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      ToastService.showError(
        message: i18n.translate('user_not_authenticated',
      ),
      );
      return;
    }

    // Busca a aplicação do usuário
    final applicationSnapshot = await _firestore
        .collection('EventApplications')
        .where('eventId', isEqualTo: eventId)
        .where('userId', isEqualTo: currentUserId)
        .limit(1)
        .get();

    if (applicationSnapshot.docs.isEmpty) {
      ToastService.showError(
        message: i18n.translate('application_not_found',
      ),
      );
      return;
    }

    // Busca dados do evento para exibir nome
    final eventDoc = await _firestore.collection('events').doc(eventId).get();
    final eventName = eventDoc.data()?['activityText'] as String? ?? 
                      i18n.translate('this_event');

    // Exibe confirmação antes de remover
    await _showRemoveConfirmation(
      context: context,
      eventId: eventId,
      eventName: eventName,
      applicationId: applicationSnapshot.docs.first.id,
      i18n: i18n,
      progressDialog: progressDialog,
      onSuccess: onSuccess,
    );
  }

  /// Remove o próprio usuário do evento (sair do evento)
  Future<void> handleLeaveEvent({
    required BuildContext context,
    required String eventId,
    required AppLocalizations i18n,
    required ProgressDialog progressDialog,
    required VoidCallback onSuccess,
  }) async {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      ToastService.showError(
        message: i18n.translate('user_not_authenticated',
      ),
      );
      return;
    }

    // Busca a aplicação do usuário
    final applicationSnapshot = await _firestore
        .collection('EventApplications')
        .where('eventId', isEqualTo: eventId)
        .where('userId', isEqualTo: currentUserId)
        .limit(1)
        .get();

    if (applicationSnapshot.docs.isEmpty) {
      ToastService.showError(
        message: i18n.translate('application_not_found',
      ),
      );
      return;
    }

    // Busca dados do evento para exibir nome
    final eventDoc = await _firestore.collection('events').doc(eventId).get();
    final eventName = eventDoc.data()?['activityText'] as String? ?? 
                      i18n.translate('this_event');

    // Exibe confirmação antes de sair
    await _showLeaveConfirmation(
      context: context,
      eventId: eventId,
      eventName: eventName,
      applicationId: applicationSnapshot.docs.first.id,
      i18n: i18n,
      progressDialog: progressDialog,
      onSuccess: onSuccess,
    );
  }

  /// Exibe dialog de confirmação para sair do evento
  Future<void> _showLeaveConfirmation({
    required BuildContext context,
    required String eventId,
    required String eventName,
    required String applicationId,
    required AppLocalizations i18n,
    required ProgressDialog progressDialog,
    required VoidCallback onSuccess,
  }) async {
    confirmDialog(
      context,
      title: i18n.translate('leave_event'),
      message: i18n.translate('leave_event_confirmation')
          .replaceAll('{event}', eventName),
      positiveText: i18n.translate('leave'),
      negativeAction: () => Navigator.of(context).pop(),
      positiveAction: () async {
        Navigator.of(context).pop();
        progressDialog.show(i18n.translate('leaving_event'));
        
        final success = await _removeApplicationData(
          eventId: eventId,
          applicationId: applicationId,
        );
        
        await progressDialog.hide();
        
        if (success && context.mounted) {
          ToastService.showSuccess(
        message: i18n.translate('left_event_successfully',
      )
                .replaceAll('{event}', eventName),
          );
          onSuccess();
        } else if (context.mounted) {
          ToastService.showError(
        message: i18n.translate('failed_to_leave_event',
      ),
          );
        }
      },
    );
  }

  /// Exibe dialog de confirmação para remover aplicação
  Future<void> _showRemoveConfirmation({
    required BuildContext context,
    required String eventId,
    required String eventName,
    required String applicationId,
    required AppLocalizations i18n,
    required ProgressDialog progressDialog,
    required VoidCallback onSuccess,
  }) async {
    confirmDialog(
      context,
      title: i18n.translate('remove_application'),
      message: i18n.translate('remove_application_confirmation')
          .replaceAll('{event}', eventName),
      positiveText: i18n.translate('remove'),
      negativeAction: () => Navigator.of(context).pop(),
      positiveAction: () async {
        Navigator.of(context).pop();
        progressDialog.show(i18n.translate('removing_application'));
        
        final success = await _removeApplicationData(
          eventId: eventId,
          applicationId: applicationId,
        );
        
        await progressDialog.hide();
        
        if (success && context.mounted) {
          ToastService.showSuccess(
        message: i18n.translate('application_removed_successfully',
      )
                .replaceAll('{event}', eventName),
          );
          onSuccess();
        } else if (context.mounted) {
          ToastService.showError(
        message: i18n.translate('failed_to_remove_application',
      ),
          );
        }
      },
    );
  }

  /// Remove todos os dados da aplicação (via Cloud Function)
  Future<bool> _removeApplicationData({
    required String eventId,
    required String applicationId,
  }) async {
    try {
      debugPrint('🔥 Calling Cloud Function: removeUserApplication');
      
      // Chama a Cloud Function que faz todas as operações de forma atômica
      final result = await _functions.httpsCallable('removeUserApplication').call({
        'eventId': eventId,
        // Não precisa passar userId - a Cloud Function usa o auth.uid
      });

      final success = result.data['success'] as bool? ?? false;
      
      if (success) {
        debugPrint('✅ Cloud Function completed successfully');
      } else {
        debugPrint('❌ Cloud Function returned success=false');
      }

      return success;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ Cloud Function error: ${e.code} - ${e.message}');
      
      if (e.code == 'not-found') {
        debugPrint('⚠️ Application not found');
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected error calling Cloud Function: $e');
      return false;
    }
  }

  /// [DEPRECATED] Método antigo - mantido como fallback
  Future<bool> _removeApplicationDataLegacy({
    required String eventId,
    required String applicationId,
  }) async {
    try {
      final currentUserId = AppState.currentUserId;
      if (currentUserId == null) return false;

      final batch = _firestore.batch();

      // 1. Remove aplicação em EventApplications
      batch.delete(
        _firestore.collection('EventApplications').doc(applicationId),
      );

      // 2. Remove usuário do array participants em EventChats
      final eventChatRef = _firestore.collection('EventChats').doc(eventId);
      batch.update(eventChatRef, {
        'participants': FieldValue.arrayRemove([currentUserId]),
        'participantCount': FieldValue.increment(-1),
      });

      // 3. Remove conversa do evento das conversas do usuário
      final eventUserId = 'event_$eventId';
      batch.delete(
        _firestore
            .collection('Connections')
            .doc(currentUserId)
            .collection('Conversations')
            .doc(eventUserId),
      );

      // Executa todas as operações
      await batch.commit();

      debugPrint('✅ Aplicação removida com sucesso: $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ Erro ao remover aplicação: $e');
      return false;
    }
  }

  /// Remove um participante específico do evento (usado pelo criador do evento)
  Future<void> handleRemoveParticipant({
    required BuildContext context,
    required String eventId,
    required String participantUserId,
    required String participantName,
    required AppLocalizations i18n,
    required ProgressDialog progressDialog,
    required VoidCallback onSuccess,
  }) async {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      ToastService.showError(
        message: i18n.translate('user_not_authenticated',
      ),
      );
      return;
    }

    // Verifica se o usuário é o criador do evento
    final eventDoc = await _firestore.collection('events').doc(eventId).get();
    
    if (!eventDoc.exists) {
      ToastService.showError(
        message: i18n.translate('event_not_found',
      ),
      );
      return;
    }

    final createdBy = eventDoc.data()?['createdBy'] as String?;
    
    if (createdBy != currentUserId) {
      ToastService.showError(
        message: i18n.translate('not_event_owner',
      ),
      );
      return;
    }

    // Exibe confirmação
    confirmDialog(
      context,
      title: i18n.translate('remove_participant'),
      message: i18n.translate('remove_participant_confirmation')
          .replaceAll('{user}', participantName),
      positiveText: i18n.translate('remove'),
      negativeAction: () => Navigator.of(context).pop(),
      positiveAction: () async {
        Navigator.of(context).pop();
        progressDialog.show(i18n.translate('removing_participant'));
        
        // Chama Cloud Function para remover participante
        final success = await _removeParticipantViaCloudFunction(
          eventId: eventId,
          participantUserId: participantUserId,
        );
        
        await progressDialog.hide();
        
        if (success && context.mounted) {
          ToastService.showSuccess(
        message: i18n.translate('participant_removed_successfully',
      )
                .replaceAll('{user}', participantName),
          );
          onSuccess();
        } else if (context.mounted) {
          ToastService.showError(
        message: i18n.translate('failed_to_remove_participant',
      ),
          );
        }
      },
    );
  }

  /// Remove participante via Cloud Function (apenas criador)
  Future<bool> _removeParticipantViaCloudFunction({
    required String eventId,
    required String participantUserId,
  }) async {
    try {
      debugPrint('🔥 Calling Cloud Function: removeParticipant');
      
      final result = await _functions.httpsCallable('removeParticipant').call({
        'eventId': eventId,
        'userId': participantUserId,
      });

      final success = result.data['success'] as bool? ?? false;
      
      if (success) {
        debugPrint('✅ Participant removed via Cloud Function');
      } else {
        debugPrint('❌ Cloud Function returned success=false');
      }

      return success;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ Cloud Function error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected error calling Cloud Function: $e');
      return false;
    }
  }
}
