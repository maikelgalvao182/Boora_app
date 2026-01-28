import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Serviço responsável por deletar eventos e todos os dados relacionados em cascata
/// 
/// Deleta na seguinte ordem:
/// 1. Messages (subcoleção do EventChats)
/// 2. EventChats (documento principal)
/// 3. Conversations de todos os participantes
/// 4. EventApplications
/// 5. Notificações relacionadas ao evento
/// 6. Documento do evento
class EventDeletionService {
  factory EventDeletionService() => _instance;
  EventDeletionService._internal();
  
  static final EventDeletionService _instance = EventDeletionService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Deleta um evento e todos os dados relacionados em cascata
  /// 
  /// Retorna true se bem-sucedido, false caso contrário
  Future<bool> deleteEvent(String eventId) async {
    debugPrint('🗑️ EventDeletionService.deleteEvent iniciado');
    debugPrint('📋 EventId: $eventId');
    
    try {
      final batch = _firestore.batch();
      
      // 1. Buscar todos os participantes aprovados para remover suas conversas
      debugPrint('🔍 Buscando participantes do evento...');
      final applicationsSnapshot = await _firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .get();
      
      final participantIds = applicationsSnapshot.docs
          .map((doc) => doc.data()['userId'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toList();
      
      debugPrint('👥 ${participantIds.length} participantes encontrados');
      
      // 2. Deletar subcoleção Messages PRIMEIRO (antes de tudo)
      // As regras de Messages precisam que events/{eventId} ainda exista
      debugPrint('🔄 Deletando mensagens do chat...');
      final messagesSnapshot = await _firestore
          .collection('EventChats')
          .doc(eventId)
          .collection('Messages')
          .get();
      
      for (final messageDoc in messagesSnapshot.docs) {
        await messageDoc.reference.delete();
      }
      debugPrint('✅ ${messagesSnapshot.docs.length} mensagens deletadas');
      
      // 3. Deletar documento principal do EventChats
      // Agora pode deletar porque Messages já foram removidas
      debugPrint('🔄 Tentando deletar EventChat document...');
      final eventChatRef = _firestore.collection('EventChats').doc(eventId);
      await eventChatRef.delete();
      debugPrint('✅ EventChat deletado');
      
      // 4. Deletar conversas de todos os participantes
      debugPrint('🔄 Preparando deleção de ${participantIds.length} conversas no batch...');
      for (final participantId in participantIds) {
        final conversationRef = _firestore
            .collection('Connections')
            .doc(participantId)
            .collection('Conversations')
            .doc('event_$eventId');
        
        debugPrint('   📝 Adicionando ao batch: Connections/$participantId/Conversations/event_$eventId');
        batch.delete(conversationRef);
      }
      debugPrint('✅ ${participantIds.length} conversas adicionadas ao batch');
      
      // 5. Deletar todas as aplicações do evento
      debugPrint('🔄 Preparando deleção de ${applicationsSnapshot.docs.length} aplicações no batch...');
      for (final doc in applicationsSnapshot.docs) {
        debugPrint('   📝 Adicionando ao batch: EventApplications/${doc.id}');
        batch.delete(doc.reference);
      }
      debugPrint('✅ ${applicationsSnapshot.docs.length} aplicações adicionadas ao batch');
      
      // 6. Deletar documento do evento
      debugPrint('🔄 Preparando deleção do evento no batch...');
      final eventRef = _firestore.collection('events').doc(eventId);
      debugPrint('   📝 Adicionando ao batch: events/$eventId');
      batch.delete(eventRef);
      debugPrint('✅ Evento adicionado ao batch');
      
      // 7. Deletar notificações relacionadas ao evento (ANTES do batch principal)
      // Necessário fazer antes para que as regras de segurança (isEventCreator) funcionem
      debugPrint('🔔 Deletando notificações do evento (pre-cleanup)...');
      final notificationsDeleted = await _deleteEventNotifications(eventId);
      debugPrint('✅ $notificationsDeleted notificações deletadas');

      // Executar batch
      debugPrint('🔥 Executando batch com ${participantIds.length + applicationsSnapshot.docs.length + 1} operações...');
      debugPrint('   - ${participantIds.length} conversas');
      debugPrint('   - ${applicationsSnapshot.docs.length} aplicações');
      debugPrint('   - 1 evento');
      await batch.commit();
      debugPrint('✅ Batch executado com sucesso');
      
      // Aguardar um breve momento para garantir que o Firestore propagou a deleção
      await Future.delayed(const Duration(milliseconds: 100));
      
      debugPrint('✅ Evento e todos os dados relacionados deletados com sucesso');
      debugPrint('🔔 Stream do Firestore deve emitir atualização automaticamente');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao deletar evento: $e');
      debugPrint('📚 StackTrace: $stackTrace');
      return false;
    }
  }
  
  /// Deleta todas as notificações relacionadas a um evento
  /// 
  /// Busca por múltiplos campos que podem referenciar o evento:
  /// - eventId (campo direto)
  /// - n_params.activityId (nested - nome usado nas notificações)
  /// - n_related_id (relacionamento)
  Future<int> _deleteEventNotifications(String eventId) async {
    int totalDeleted = 0;
    
    try {
      // Busca paralela em todos os campos que podem referenciar o evento
      final results = await Future.wait([
        _firestore
            .collection('Notifications')
            .where('eventId', isEqualTo: eventId)
            .get(),
        _firestore
            .collection('Notifications')
            .where('n_params.activityId', isEqualTo: eventId)
            .get(),
        _firestore
            .collection('Notifications')
            .where('n_related_id', isEqualTo: eventId)
            .get(),
      ]);
      
      // Combinar resultados únicos (evitar duplicatas)
      final docsToDelete = <String, DocumentReference>{};
      
      for (final snapshot in results) {
        for (final doc in snapshot.docs) {
          docsToDelete[doc.id] = doc.reference;
        }
      }
      
      if (docsToDelete.isEmpty) {
        debugPrint('📭 Nenhuma notificação encontrada para evento $eventId');
        return 0;
      }
      
      // Deletar em batches de 500 (limite do Firestore)
      final refs = docsToDelete.values.toList();
      const batchSize = 500;
      
      for (int i = 0; i < refs.length; i += batchSize) {
        final batchEnd = (i + batchSize < refs.length) ? i + batchSize : refs.length;
        final batchRefs = refs.sublist(i, batchEnd);
        
        final deleteBatch = _firestore.batch();
        for (final ref in batchRefs) {
          deleteBatch.delete(ref);
        }
        await deleteBatch.commit();
      }
      
      totalDeleted = refs.length;
    } catch (e) {
      debugPrint('❌ Erro ao deletar notificações do evento $eventId: $e');
    }
    
    return totalDeleted;
  }
}
