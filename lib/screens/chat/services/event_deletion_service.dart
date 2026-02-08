import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// Serviço responsável por iniciar a deleção de eventos com soft-delete
/// e cleanup assíncrono no backend.
class EventDeletionService {
  factory EventDeletionService() => _instance;
  EventDeletionService._internal();
  
  static final EventDeletionService _instance = EventDeletionService._internal();

  /// Inicia a deleção de um evento no backend.
  /// Retorna true se bem-sucedido, false caso contrário
  Future<bool> deleteEvent(String eventId) async {
    debugPrint('🗑️ EventDeletionService.deleteEvent iniciado');
    debugPrint('📋 EventId: $eventId');
    
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('deleteEvent');
      debugPrint('📡 Chamando CF deleteEvent...');
      final result = await callable.call({"eventId": eventId});
      final data = result.data;
      debugPrint('📡 CF deleteEvent response type: ${data.runtimeType}');
      debugPrint('📡 CF deleteEvent response data: $data');

      if (data is Map && data["success"] == true) {
        debugPrint('✅ Deleção iniciada com sucesso');
        return true;
      }

      debugPrint('⚠️ Resposta inesperada ao deletar evento: $data');
      return false;
    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao deletar evento: $e');
      debugPrint('📚 StackTrace: $stackTrace');
      return false;
    }
  }
}
