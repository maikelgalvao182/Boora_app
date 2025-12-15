import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/dialogs/common_dialogs.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/core/services/toast_service.dart';

/// Serviço responsável por deletar eventos criados pelo usuário
/// 
/// IMPORTANTE: As operações são executadas via Cloud Function para garantir:
/// - Segurança (validação server-side)
/// - Atomicidade (todas as operações juntas)
/// - Confiabilidade (não depende do cliente manter conexão)
class EventDeletionService {
  factory EventDeletionService() => _instance;
  EventDeletionService._internal();
  
  static final EventDeletionService _instance = EventDeletionService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Deleta um evento e todos os seus dados relacionados
  Future<void> handleDeleteEvent({
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

    // Verifica se o usuário é o criador do evento
    final eventDoc = await _firestore.collection('events').doc(eventId).get();
    
    if (!eventDoc.exists) {
      ToastService.showError(
        message: i18n.translate('event_not_found',
      ),
      );
      return;
    }

    final eventData = eventDoc.data();
    final createdBy = eventData?['createdBy'] as String?;
    
    if (createdBy != currentUserId) {
      ToastService.showError(
        message: i18n.translate('not_event_owner',
      ),
      );
      return;
    }

    // Exibe confirmação antes de deletar
    await _showDeleteConfirmation(
      context: context,
      eventId: eventId,
      eventData: eventData,
      i18n: i18n,
      progressDialog: progressDialog,
      onSuccess: onSuccess,
    );
  }

  /// Exibe dialog de confirmação para deletar evento
  Future<void> _showDeleteConfirmation({
    required BuildContext context,
    required String eventId,
    required Map<String, dynamic>? eventData,
    required AppLocalizations i18n,
    required ProgressDialog progressDialog,
    required VoidCallback onSuccess,
  }) async {
    final eventName = eventData?['activityText'] as String? ?? 
                     i18n.translate('this_event');

    confirmDialog(
      context,
      title: i18n.translate('delete_event'),
      message: i18n.translate('delete_event_confirmation')
          .replaceAll('{event}', eventName),
      positiveText: i18n.translate('delete'),
      negativeAction: () => Navigator.of(context).pop(),
      positiveAction: () async {
        Navigator.of(context).pop();
        progressDialog.show(i18n.translate('deleting_event'));
        
        final success = await _deleteEventData(eventId, eventData);
        await progressDialog.hide();
        
        if (success && context.mounted) {
          ToastService.showSuccess(
        message: i18n.translate('event_deleted_successfully',
      ),
          );
          onSuccess();
        } else if (context.mounted) {
          ToastService.showError(
        message: i18n.translate('failed_to_delete_event',
      ),
          );
        }
      },
    );
  }

  /// Deleta todos os dados do evento (via Cloud Function)
  Future<bool> _deleteEventData(
    String eventId,
    Map<String, dynamic>? eventData,
  ) async {
    try {
      debugPrint('🔥 Calling Cloud Function: deleteEvent');
      
      // Chama a Cloud Function que faz todas as operações de forma atômica
      final result = await _functions.httpsCallable('deleteEvent').call({
        'eventId': eventId,
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
      
      // Mensagens de erro específicas
      if (e.code == 'permission-denied') {
        debugPrint('⚠️ User is not the event creator');
      } else if (e.code == 'not-found') {
        debugPrint('⚠️ Event not found');
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected error calling Cloud Function: $e');
      return false;
    }
  }

  /// [DEPRECATED] Método antigo - mantido como fallback
  /// Use _deleteEventData() que chama a Cloud Function
  Future<bool> _deleteEventDataLegacy(
    String eventId,
    Map<String, dynamic>? eventData,
  ) async {
    try {
      final batch = _firestore.batch();

      // 1. Remove documento do evento
      batch.delete(_firestore.collection('events').doc(eventId));

      // 2. Remove chat do evento em EventChats
      batch.delete(_firestore.collection('EventChats').doc(eventId));

      // 3. Remove mensagens do chat
      final messagesSnapshot = await _firestore
          .collection('EventChats')
          .doc(eventId)
          .collection('Messages')
          .get();

      for (final doc in messagesSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // 4. Remove todas as aplicações em EventApplications
      final applicationsSnapshot = await _firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .get();

      for (final doc in applicationsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // 5. Remove conversas relacionadas ao evento (event_eventId)
      final eventUserId = 'event_$eventId';
      
      // Remove das conversas do criador
      final currentUserId = AppState.currentUserId;
      if (currentUserId != null) {
        batch.delete(
          _firestore
              .collection('Connections')
              .doc(currentUserId)
              .collection('Conversations')
              .doc(eventUserId),
        );
      }

      // Remove conversas de todos os participantes
      for (final appDoc in applicationsSnapshot.docs) {
        final userId = appDoc.data()['userId'] as String?;
        if (userId != null) {
          batch.delete(
            _firestore
                .collection('Connections')
                .doc(userId)
                .collection('Conversations')
                .doc(eventUserId),
          );
        }
      }

      // Executa todas as deleções no Firestore
      await batch.commit();

      // 6. Remove arquivos do Storage (em paralelo, não bloqueia o fluxo)
      _deleteEventStorageFiles(eventId, eventData);

      debugPrint('✅ Evento $eventId deletado com sucesso');
      return true;
    } catch (e) {
      debugPrint('❌ Erro ao deletar evento $eventId: $e');
      return false;
    }
  }

  /// Remove arquivos do Storage relacionados ao evento
  /// Executa de forma assíncrona sem aguardar conclusão
  Future<void> _deleteEventStorageFiles(
    String eventId,
    Map<String, dynamic>? eventData,
  ) async {
    try {
      // Lista de possíveis caminhos de Storage para o evento
      final paths = <String>[
        'events/$eventId', // Pasta principal do evento
        'event_images/$eventId', // Imagens do evento
        'event_media/$eventId', // Mídia geral
      ];

      // Tenta deletar cada caminho
      for (final path in paths) {
        try {
          final ref = _storage.ref(path);
          final listResult = await ref.listAll();
          
          // Deleta todos os arquivos encontrados
          for (final item in listResult.items) {
            await item.delete();
            debugPrint('🗑️ Arquivo deletado: ${item.fullPath}');
          }
          
          // Deleta subpastas recursivamente
          for (final prefix in listResult.prefixes) {
            await _deleteStorageFolder(prefix);
          }
        } catch (e) {
          debugPrint('⚠️ Erro ao deletar caminho $path: $e');
          // Continua tentando outros caminhos mesmo se um falhar
        }
      }

      // Tenta deletar imagens específicas mencionadas no eventData
      if (eventData != null) {
        final coverPhoto = eventData['coverPhoto'] as String?;
        if (coverPhoto != null && coverPhoto.contains('firebase')) {
          try {
            await _storage.refFromURL(coverPhoto).delete();
            debugPrint('🗑️ Cover photo deletada');
          } catch (e) {
            debugPrint('⚠️ Erro ao deletar cover photo: $e');
          }
        }

        // Deleta fotos da galeria se existirem
        final photos = eventData['photos'] as List?;
        if (photos != null) {
          for (final photo in photos) {
            if (photo is String && photo.contains('firebase')) {
              try {
                await _storage.refFromURL(photo).delete();
                debugPrint('🗑️ Foto da galeria deletada');
              } catch (e) {
                debugPrint('⚠️ Erro ao deletar foto da galeria: $e');
              }
            }
          }
        }
      }

      debugPrint('✅ Arquivos do Storage deletados para evento $eventId');
    } catch (e) {
      debugPrint('❌ Erro ao deletar arquivos do Storage: $e');
      // Não propaga erro - deleção do Storage é best-effort
    }
  }

  /// Deleta uma pasta do Storage recursivamente
  Future<void> _deleteStorageFolder(Reference folderRef) async {
    try {
      final listResult = await folderRef.listAll();
      
      for (final item in listResult.items) {
        await item.delete();
      }
      
      for (final prefix in listResult.prefixes) {
        await _deleteStorageFolder(prefix);
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao deletar pasta ${folderRef.fullPath}: $e');
    }
  }
}
